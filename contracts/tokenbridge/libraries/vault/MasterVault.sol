// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// todo: should we have an arbitrary call function for the vault manager to do stuff with the subvault? like queue withdrawals etc

/// @notice MasterVault is an ERC4626 metavault that deposits assets to an admin defined subVault.
/// @dev    If a subVault is not set, MasterVault shares entitle holders to a pro-rata share of the underlying held by the MasterVault.
///         If a subVault is set, MasterVault shares entitle holders to a pro-rata share of subVault shares held by the MasterVault.
///         On deposit to the MasterVault, if there is a subVault set, the assets are immediately deposited into the subVault.
///         On withdraw from the MasterVault, if there is a subVault set, a pro rata amount of subvault shares are redeemed.
///         On deposit and withdraw, if there is no subVault set, assets are moved to/from the MasterVault itself.
///
///         For a subVault to be compatible with the MasterVault, it must adhere to the following:
///         - It must be able to handle arbitrarily large deposits and withdrawals
///         - Deposit size or withdrawal size must not affect the exchange rate (i.e. no slippage)
///         - convertToAssets and convertToShares must not be manipulable
contract MasterVault is Initializable, ERC4626Upgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;

    /// @notice Vault manager role can set/revoke subvaults, toggle performance fees and set the performance fee beneficiary
    /// @dev    Should never be granted to the zero address
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    /// @notice Pauser role can pause/unpause deposits and withdrawals (todo: pause should pause EVERYTHING)
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    error SubVaultAlreadySet();
    error SubVaultAssetMismatch();
    error SubVaultExchangeRateTooLow();
    error NoExistingSubVault();
    error NewSubVaultExchangeRateTooLow();
    error PerformanceFeeDisabled();
    error BeneficiaryNotSet();
    error InvalidAsset();
    error InvalidOwner();

    // todo: avoid inflation, rounding, other common 4626 vulns
    // we may need a minimum asset or master share amount when setting subvaults (bc of exchange rate calc)
    IERC4626 public subVault;

    uint256 public targetAllocationWad;

    /// @notice Flag indicating if performance fee is enabled
    bool public enablePerformanceFee;

    /// @notice Address that receives performance fees
    address public beneficiary;

    /// @notice totalPrincipal tracks the total assets deposited into the vault (minus withdrawals)
    /// @dev    When performance fees are disabled, totalPrincipal is 0
    uint256 public totalPrincipal;

    event SubvaultChanged(address indexed oldSubvault, address indexed newSubvault);
    event PerformanceFeeToggled(bool enabled);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event PerformanceFeesWithdrawn(address indexed beneficiary, uint256 amount);

    function initialize(IERC4626 _subVault, string memory _name, string memory _symbol, address _owner) external initializer {
        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20Upgradeable(_subVault.asset()));
        __AccessControl_init();
        __Pausable_init();

        _setRoleAdmin(VAULT_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(VAULT_MANAGER_ROLE, _owner);
        _grantRole(PAUSER_ROLE, _owner);

        subVault = _subVault;
    }

    function distributePerformanceFee() external whenNotPaused {
        if (!enablePerformanceFee) revert PerformanceFeeDisabled();
        if (beneficiary == address(0)) {
            revert BeneficiaryNotSet();
        }

        uint256 profit = totalProfit(MathUpgradeable.Rounding.Down);
        if (profit == 0) return;

        if (address(subVault) != address(0)) {
            subVault.redeem(totalProfitInSubVaultShares(MathUpgradeable.Rounding.Down), beneficiary, address(this));
        } else {
            IERC20(asset()).safeTransfer(beneficiary, profit);
        }

        emit PerformanceFeesWithdrawn(beneficiary, profit);
    }

    error NonZeroTargetAllocation(uint256 targetAllocationWad);

    /// @notice Set a subvault. Can only be called if there is not already a subvault set.
    /// @param  _subVault The subvault to set. Must be an ERC4626 vault with the same asset as this MasterVault.
    function setSubVault(IERC4626 _subVault) external onlyRole(VAULT_MANAGER_ROLE) {
        IERC20 underlyingAsset = IERC20(asset());
        if (address(_subVault.asset()) != address(underlyingAsset)) revert SubVaultAssetMismatch();
        if (targetAllocationWad != 0) revert NonZeroTargetAllocation(targetAllocationWad);

        address oldSubVault = address(subVault);
        subVault = _subVault;

        if (oldSubVault != address(0)) IERC20(asset()).safeApprove(address(oldSubVault), 0);
        IERC20(asset()).safeApprove(address(_subVault), type(uint256).max);

        emit SubvaultChanged(oldSubVault, address(_subVault));
    }

    function setTargetAllocationWad(uint256 _targetAllocationWad) external onlyRole(VAULT_MANAGER_ROLE) {
        require(_targetAllocationWad <= 1e18, "Target allocation must be <= 100%");
        
        int256 allocationDelta = int256(_targetAllocationWad) - int256(targetAllocationWad);
        require(allocationDelta != 0, "Allocation unchanged");

        int256 idleDelta = int256(totalAssets()) * allocationDelta / 1e18;

        if (idleDelta > 0) {
            // move assets into subvault
            subVault.deposit(uint256(idleDelta), address(this));
        }
        else if (idleDelta < 0) {
            // move assets out of subvault
            subVault.withdraw(uint256(-idleDelta), address(this), address(this));
        }

        targetAllocationWad = _targetAllocationWad;
    }

    /// @notice Toggle performance fee collection on/off
    /// @param enabled True to enable performance fees, false to disable
    function setPerformanceFee(bool enabled) external onlyRole(VAULT_MANAGER_ROLE) {
        enablePerformanceFee = enabled;

        // reset totalPrincipal to current totalAssets when enabling performance fee
        // this prevents a sudden large profit
        if (enabled) {
            totalPrincipal = _totalAssets(MathUpgradeable.Rounding.Up);
        }
        else {
            totalPrincipal = 0;
        }

        emit PerformanceFeeToggled(enabled);
    }

    /// @notice Set the beneficiary address for performance fees
    /// @param newBeneficiary Address to receive performance fees, zero address defaults to owner
    function setBeneficiary(address newBeneficiary) external onlyRole(VAULT_MANAGER_ROLE) {
        address oldBeneficiary = beneficiary;
        beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(oldBeneficiary, newBeneficiary);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        return _totalAssets(MathUpgradeable.Rounding.Down);
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public view virtual override returns (uint256) {
        if (address(subVault) == address(0)) {
            return type(uint256).max;
        }
        return subVault.maxDeposit(address(this));
    }

    // /** @dev See {IERC4626-maxMint}. */
    function maxMint(address) public view virtual override returns (uint256) {
        if (address(subVault) == address(0)) {
            return type(uint256).max;
        }
        uint256 subShares = subVault.maxMint(address(this));
        if (subShares == type(uint256).max) {
            return type(uint256).max;
        }
        return totalSupply().mulDiv(subShares, subVault.balanceOf(address(this)), MathUpgradeable.Rounding.Down); // todo: check rounding direction
    }

    function totalProfit(MathUpgradeable.Rounding rounding) public view returns (uint256) {
        uint256 __totalAssets = _totalAssets(rounding);
        return __totalAssets > totalPrincipal ? __totalAssets - totalPrincipal : 0;
    }

    function totalProfitInIdleAssets(MathUpgradeable.Rounding rounding) public view returns (uint256) {
        return totalProfit(rounding).mulDiv(1e18 - targetAllocationWad, 1e18, rounding);
    }

    function totalProfitInSubVaultShares(MathUpgradeable.Rounding rounding) public view returns (uint256) {
        uint256 profitAssets = totalProfit(rounding);
        if (profitAssets == 0) {
            return 0;
        }
        return _assetsToSubVaultShares(profitAssets.mulDiv(targetAllocationWad, 1e18, rounding), rounding);
    }

    /** @dev See {IERC4626-deposit}. */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        (uint256 shares, uint256 assetsFromSubVault) = _convertToSharesDetailed(assets, MathUpgradeable.Rounding.Down);
        _deposit(_msgSender(), receiver, assets, shares, assetsFromSubVault);

        return shares;
    }

    /** @dev See {IERC4626-mint}.
     *
     * As opposed to {deposit}, minting is allowed even if the vault is in a state where the price of a share is zero.
     * In this case, the shares will be minted without requiring any assets to be deposited.
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        (uint256 assets, uint256 assetsFromSubVault) = _convertToAssetsDetailed(shares, MathUpgradeable.Rounding.Up);
        _deposit(_msgSender(), receiver, assets, shares, assetsFromSubVault);

        return assets;
    }

    /** @dev See {IERC4626-withdraw}. */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        (uint256 shares, uint256 assetsFromSubVault) = _convertToSharesDetailed(assets, MathUpgradeable.Rounding.Up);
        _withdraw(_msgSender(), receiver, owner, assets, shares, assetsFromSubVault);

        return shares;
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        (uint256 assets, uint256 assetsFromSubVault) = _convertToAssetsDetailed(shares, MathUpgradeable.Rounding.Down);
        _withdraw(_msgSender(), receiver, owner, assets, shares, assetsFromSubVault);

        return assets;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares,
        uint256 assetsToDeposit
    ) internal whenNotPaused {
        _deposit(caller, receiver, assets, shares);
        if (enablePerformanceFee) totalPrincipal += assets;
        subVault.deposit(assetsToDeposit, address(this));
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address _owner,
        uint256 assets,
        uint256 shares,
        uint256 assetsToWithdraw
    ) internal whenNotPaused {
        if (enablePerformanceFee) totalPrincipal -= assets;
        subVault.withdraw(assetsToWithdraw, address(this), address(this));
        _withdraw(caller, receiver, _owner, assets, shares);
    }

    function _totalAssets(MathUpgradeable.Rounding rounding) internal view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + _subVaultSharesToAssets(subVault.balanceOf(address(this)), rounding);
    }

    // todo: question: will this drift over time? i don't think so but worth checking and testing for
    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding) internal view virtual override returns (uint256 shares) {
        (shares,) = _convertToSharesDetailed(assets, rounding);
    }

    function _convertToSharesDetailed(uint256 assets, MathUpgradeable.Rounding rounding) internal view returns (uint256 shares, uint256 assetsForSubVault) {
        uint256 supply = totalSupply();

        uint256 totalIdle = IERC20(asset()).balanceOf(address(this));
        uint256 totalSubShares = subVault.balanceOf(address(this));

        if (enablePerformanceFee) {
            // since we use totalSubShares and totalIdle in the denominators of the final calculation,
            // and we are subtracting profit from it, we should use the same rounding direction for profit
            totalSubShares -= totalProfitInSubVaultShares(_flipRounding(rounding));
            totalIdle -= totalProfitInIdleAssets(_flipRounding(rounding));
        }

        // figure out how much assets should be deposited to subvault vs kept idle
        // same rounding direction since they are used in the numerators of the final calculation
        uint256 assetsForIdle = assets.mulDiv(1e18 - targetAllocationWad, 1e18, rounding);
        assetsForSubVault = assets.mulDiv(targetAllocationWad, 1e18, rounding);

        // figure out how many shares would be issued according to each portion
        uint256 sharesFromIdle = assetsForIdle.mulDiv(supply, totalIdle, rounding);
        uint256 sharesFromSubVault = _assetsToSubVaultShares(assetsForSubVault, rounding).mulDiv(supply, totalSubShares, rounding);

        // take the min if rounding down, max if rounding up
        shares = rounding == MathUpgradeable.Rounding.Down
            ? MathUpgradeable.min(sharesFromIdle, sharesFromSubVault)
            : MathUpgradeable.max(sharesFromIdle, sharesFromSubVault);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding) internal view virtual override returns (uint256 assets) {
        (assets,) = _convertToAssetsDetailed(shares, rounding);
    }

    function _convertToAssetsDetailed(uint256 shares, MathUpgradeable.Rounding rounding) internal view returns (uint256 assets, uint256 assetsFromSubVault) {
        uint256 supply = totalSupply();

        uint256 totalIdle = IERC20(asset()).balanceOf(address(this));
        uint256 totalSubShares = subVault.balanceOf(address(this));

        if (enablePerformanceFee) {
            // since we use totalSubShares and totalIdle in the numerators of the final calculation,
            // and we are subtracting profit from it, we should use the opposite rounding direction for profit
            totalSubShares -= totalProfitInSubVaultShares(_flipRounding(rounding));
            totalIdle -= totalProfitInIdleAssets(_flipRounding(rounding));
        }

        // figure out how many shares should be burned for subvault shares vs idle
        // same rounding direction since they are used in the numerators of the final calculation (todo: confirm rounding direction)
        uint256 sharesForIdle = shares.mulDiv(1e18 - targetAllocationWad, 1e18, rounding);
        uint256 sharesForSubVault = shares.mulDiv(targetAllocationWad, 1e18, rounding);

        // figure out how much assets would be received according to each portion
        uint256 assetsFromIdle = sharesForIdle.mulDiv(totalIdle, supply, rounding);
        assetsFromSubVault = _subVaultSharesToAssets(sharesForSubVault.mulDiv(totalSubShares, supply, rounding), rounding);

        // total it up
        assets = assetsFromIdle + assetsFromSubVault;
    }

    function _assetsToSubVaultShares(uint256 assets, MathUpgradeable.Rounding rounding) internal view returns (uint256 subShares) {
        return rounding == MathUpgradeable.Rounding.Up ? subVault.previewWithdraw(assets) : subVault.previewDeposit(assets);
    }

    function _subVaultSharesToAssets(uint256 subShares, MathUpgradeable.Rounding rounding) internal view returns (uint256 assets) {
        return rounding == MathUpgradeable.Rounding.Up ? subVault.previewMint(subShares) : subVault.previewRedeem(subShares);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    function _flipRounding(MathUpgradeable.Rounding rounding) internal pure returns (MathUpgradeable.Rounding) {
        return rounding == MathUpgradeable.Rounding.Up ? MathUpgradeable.Rounding.Down : MathUpgradeable.Rounding.Up;
    }
}