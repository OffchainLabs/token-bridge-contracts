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

    function initialize(IERC20 _asset, string memory _name, string memory _symbol, address _owner) external initializer {
        if (address(_asset) == address(0)) revert InvalidAsset();
        if (_owner == address(0)) revert InvalidOwner();

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20Upgradeable(address(_asset)));
        __AccessControl_init();
        __Pausable_init();

        _setRoleAdmin(VAULT_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(VAULT_MANAGER_ROLE, _owner);
        _grantRole(PAUSER_ROLE, _owner);

        _pause(); 
    }

    function distributePerformanceFee() external whenNotPaused {
        if (!enablePerformanceFee) revert PerformanceFeeDisabled();
        if (beneficiary == address(0)) {
            revert BeneficiaryNotSet();
        }
        subVault.redeem(totalProfitInSubVaultShares(MathUpgradeable.Rounding.Down), beneficiary, address(this));
        // todo emit event
    }

    /// @notice Set a subvault. Can only be called if there is not already a subvault set.
    /// @param  _subVault The subvault to set. Must be an ERC4626 vault with the same asset as this MasterVault.
    /// @param  minSubVaultExchRateWad Minimum acceptable ratio (times 1e18) of new subvault shares to outstanding MasterVault shares after deposit.
    function setSubVault(IERC4626 _subVault, uint256 minSubVaultExchRateWad) external onlyRole(VAULT_MANAGER_ROLE) {
        IERC20 underlyingAsset = IERC20(asset());
        if (address(subVault) != address(0)) revert SubVaultAlreadySet();
        if (address(_subVault.asset()) != address(underlyingAsset)) revert SubVaultAssetMismatch();

        subVault = _subVault;

        IERC20(asset()).safeApprove(address(_subVault), type(uint256).max);
        _subVault.deposit(underlyingAsset.balanceOf(address(this)), address(this));

        uint256 subVaultExchRateWad = _subVault.balanceOf(address(this)).mulDiv(1e18, totalSupply(), MathUpgradeable.Rounding.Down);
        if (subVaultExchRateWad < minSubVaultExchRateWad) revert NewSubVaultExchangeRateTooLow();

        emit SubvaultChanged(address(0), address(_subVault));
    }

    /// @notice Revokes the current subvault, moving all assets back to MasterVault
    /// @param minAssetExchRateWad Minimum acceptable ratio (times 1e18) of assets received from subvault to outstanding MasterVault shares
    function revokeSubVault(uint256 minAssetExchRateWad) external onlyRole(VAULT_MANAGER_ROLE) {
        IERC4626 oldSubVault = subVault;
        if (address(oldSubVault) == address(0)) revert NoExistingSubVault();

        subVault = IERC4626(address(0));

        oldSubVault.redeem(oldSubVault.balanceOf(address(this)), address(this), address(this));
        IERC20(asset()).safeApprove(address(oldSubVault), 0);

        uint256 assetExchRateWad = IERC20(asset()).balanceOf(address(this)).mulDiv(1e18, totalSupply(), MathUpgradeable.Rounding.Down);
        if (assetExchRateWad < minAssetExchRateWad) revert SubVaultExchangeRateTooLow();

        emit SubvaultChanged(address(oldSubVault), address(0));
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

    function totalProfitInSubVaultShares(MathUpgradeable.Rounding rounding) public view returns (uint256) {
        if (address(subVault) == address(0)) {
            revert("Subvault not set");
        }
        uint256 profitAssets = totalProfit(rounding);
        if (profitAssets == 0) {
            return 0;
        }
        return _assetsToSubVaultShares(profitAssets, rounding);
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override whenNotPaused {
        super._deposit(caller, receiver, assets, shares);

        if (enablePerformanceFee) totalPrincipal += assets;

        IERC4626 _subVault = subVault;
        if (address(_subVault) != address(0)) {
           _subVault.deposit(assets, address(this));
        }
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address _owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override whenNotPaused {
        if (enablePerformanceFee) totalPrincipal -= assets;

        IERC4626 _subVault = subVault;
        if (address(_subVault) != address(0)) {
            _subVault.withdraw(assets, address(this), address(this));
        }

        super._withdraw(caller, receiver, _owner, assets, shares);
    }

    function _totalAssets(MathUpgradeable.Rounding rounding) internal view returns (uint256) {
        if (address(subVault) == address(0)) {
            return IERC20(asset()).balanceOf(address(this));
        }
        return _subVaultSharesToAssets(subVault.balanceOf(address(this)), rounding);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding) internal view virtual override returns (uint256 shares) {
        uint256 supply = totalSupply();

        if (address(subVault) == address(0)) {
            uint256 effectiveTotalAssets = enablePerformanceFee ? _min(totalAssets(), totalPrincipal) : totalAssets();

            if (supply == 0 || effectiveTotalAssets == 0) {
                return assets;  
            }

            return supply.mulDiv(assets, effectiveTotalAssets, rounding);
        }

        uint256 totalSubShares = subVault.balanceOf(address(this));

        if (enablePerformanceFee) {
            // since we use totalSubShares in the denominator of the final calculation,
            // and we are subtracting profit from it, we should use the same rounding direction for profit
            totalSubShares -= totalProfitInSubVaultShares(_flipRounding(rounding));
        }

        uint256 subShares = _assetsToSubVaultShares(assets, rounding);

        return totalSupply().mulDiv(subShares, totalSubShares, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding) internal view virtual override returns (uint256 assets) {
        // if we have no subvault, we just do normal pro-rata calculation
        if (address(subVault) == address(0)) {
            uint256 effectiveTotalAssets = enablePerformanceFee ? _min(totalAssets(), totalPrincipal) : totalAssets();
            return effectiveTotalAssets.mulDiv(shares, totalSupply(), rounding);
        }

        uint256 totalSubShares = subVault.balanceOf(address(this));

        if (enablePerformanceFee) {
            // since we use totalSubShares in the numerator of the final calculation,
            // and we are subtracting profit from it, we should use the opposite rounding direction for profit
            totalSubShares -= totalProfitInSubVaultShares(_flipRounding(rounding));
        }
        
        // totalSubShares * shares / totalMasterShares
        uint256 subShares = totalSubShares.mulDiv(shares, totalSupply(), rounding);

        return _subVaultSharesToAssets(subShares, rounding);
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