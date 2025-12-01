// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { MathUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MasterVault is
    Initializable,
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant MULTIPLIER = 1e18;

    error TooFewSharesReceived();
    error TooManySharesBurned();
    error TooManyAssetsDeposited();
    error TooFewAssetsReceived();
    error InvalidAsset();
    error InvalidOwner();
    error ZeroAddress();
    error PerformanceFeeDisabled();
    error BeneficiaryNotSet();
    error SubVaultAlreadySet();
    error SubVaultAssetMismatch();
    error NewSubVaultExchangeRateTooLow();
    error NoExistingSubVault();
    error SubVaultExchangeRateTooLow();

    event PerformanceFeeToggled(bool enabled);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event PerformanceFeesWithdrawn(address indexed beneficiary, uint256 amount);
    event SubvaultChanged(address indexed oldSubVault, address indexed newSubVault);

    // note: the performance fee can be avoided if the underlying strategy can be sandwiched (eg ETH to wstETH dex swap)
    // maybe a simpler and more robust implementation would be for the owner to adjust the subVaultExchRateWad directly
    // this would also avoid the need for totalPrincipal tracking
    // however, this would require more trust in the owner
    bool public enablePerformanceFee;
    address public beneficiary;
    int256 public totalPrincipal; // total assets deposited, used to calculate profit
    IERC4626 public subVault;

    function initialize(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _owner
    ) external initializer {
        if (address(_asset) == address(0)) revert InvalidAsset();
        if (_owner == address(0)) revert InvalidOwner();

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20Upgradeable(address(_asset)));
        __AccessControl_init();
        __Pausable_init();

        _setRoleAdmin(VAULT_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(FEE_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(VAULT_MANAGER_ROLE, _owner);
        _grantRole(FEE_MANAGER_ROLE, _owner); // todo: consider permissionless by default
        _grantRole(PAUSER_ROLE, _owner);

        // vault paused by default to protect against first depositor attack
        _pause();
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// fee-related methods ///

    /// @notice Toggle performance fee collection on/off
    /// @param enabled True to enable performance fees, false to disable
    function setPerformanceFee(bool enabled) external onlyRole(VAULT_MANAGER_ROLE) {
        enablePerformanceFee = enabled;
        if (enabled) {
            totalPrincipal = 0;
        }
        emit PerformanceFeeToggled(enabled);
    }

    /// @notice Set the beneficiary address for performance fees
    /// @param newBeneficiary Address to receive performance fees
    function setBeneficiary(address newBeneficiary) external onlyRole(FEE_MANAGER_ROLE) {
        if (newBeneficiary == address(0)) revert ZeroAddress();
        address oldBeneficiary = beneficiary;
        beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(oldBeneficiary, newBeneficiary);
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        IERC20 underlyingAsset = IERC20(asset());

        if (address(subVault) == address(0)) {
            return underlyingAsset.balanceOf(address(this));
        }
        uint256 _subShares = subVault.balanceOf(address(this));
        uint256 _assets = subVault.previewRedeem(_subShares);
        return _assets;
    }

    /// @notice calculating total profit
    function totalProfit() public view returns (int256) {
        uint256 _totalAssets = totalAssets();
        return int256(_totalAssets) - totalPrincipal;
    }

    /// @notice Withdraw all accumulated performance fees to beneficiary
    /// @dev Only callable by fee manager when performance fees are enabled
    function withdrawPerformanceFees() external onlyRole(FEE_MANAGER_ROLE) {
        if (!enablePerformanceFee) revert PerformanceFeeDisabled();
        if (beneficiary == address(0)) revert BeneficiaryNotSet();

        int256 _totalProfits = totalProfit();
        if (_totalProfits > 0) {
            if (address(subVault) == address(0)) {
                SafeERC20.safeTransfer(IERC20(asset()), beneficiary, uint256(_totalProfits));
            } else {
                subVault.withdraw(uint256(_totalProfits), beneficiary, address(this));
            }

            emit PerformanceFeesWithdrawn(beneficiary, uint256(_totalProfits));
        }
    }

    /// @notice return share price by asset in 18 decimals
    /// @dev max value is 1e18 if performance fee is enabled
    /// @dev examples:
    /// example 1. sharePrice = 1e18 means we need to pay 1  asset to get 1 share
    /// example 2. sharePrice = 10 * 1e18 means we need to pay 10  asset to get 1 share
    /// example 3. sharePrice = 0.1 * 1e18 means we need to pay 0.1  asset to get 1 share
    /// example 4. vault holds 99 USDC and 100 shares => sharePrice = 99 * 1e18 / 100
    function sharePrice() public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();

        // todo: should we also consider _totalAssets == 0 case?
        if (_totalSupply == 0 || _totalAssets == 0) {
            return 1 * MULTIPLIER;
        }

        uint256 _sharePrice = MathUpgradeable.mulDiv(_totalAssets, MULTIPLIER, _totalSupply);

        if (enablePerformanceFee) {
            _sharePrice = MathUpgradeable.min(_sharePrice, 1e18);
        }

        return _sharePrice;
    }

    /// ERC4626 internal methods ///

    /// @dev Override to implement performance fee logic when converting assets to shares
    /// @dev this follow exactly same precision that ERC4626 impl. does with no deciamls. ie 1 share = 1 wei of share
    /// @dev when user acquiring shares this should round Down [deposit, mint]
    ///      //  and round Up when redeeming [withdraw, redeem]
    /// examples:
    /// 1. sharePrice =   1 * 1e18 & assets = 1; then output should be {Up: 1 , Down: 1 }
    /// 2. sharePrice = 0.1 * 1e18 & assets = 1; then output should be {Up: 10, Down: 10}
    /// 3. sharePrice =  10 * 1e18 & assets = 1; then output should be {Up: 1 , Down: 0 }; this require tests to cover: [deposit, mint, withdraw, redeem]
    /// 4. sharePrice =  100 * 1e18 & assets = 99; then output should be {Up: 1 , Down: 0 }; this require tests to cover: [deposit, mint, withdraw, redeem]
    /// 5. sharePrice =  100 * 1e18 & assets = 199; then output should be {Up: 2 , Down: 1 }; this require tests to cover: [deposit, mint, withdraw, redeem]
    /// @notice sharePrice can be > 1 only if perf fee is disabled
    function _convertToShares(
        uint256 assets,
        MathUpgradeable.Rounding rounding
    ) internal view virtual override returns (uint256) {
        uint256 _sharePrice = sharePrice();
        uint256 _shares = MathUpgradeable.mulDiv(assets, MULTIPLIER, _sharePrice, rounding);
        return _shares;
    }

    /// @dev Override to implement performance fee logic when converting assets to shares
    /// @dev this follow exactly same precision that ERC4626 impl. does with no deciamls. ie 1 share = 1 wei of share
    /// @dev _effectiveAssets is to:
    ///     // 1. let users socialize losses but not profit if perf fee is enable
    ///     // 2. let users socialize losses and profit if perf fee is disabled
    /// @dev when user redeeming shares for assets this should round Down [withdraw, redeem]
    ///      //  and round Up when redeeming [deposit, mint]
    /// examples:
    /// * group (A): perf fee is enable
    /// 1. shares = 1   & _totalAssets = 1 & _totalSupply = 1  ; then output should be {Up: 1 , Down: 1 }
    /// 2. shares = 1   & _totalAssets = 2 & _totalSupply = 1  ; then output should be {Up: 2 , Down: 2 }
    /// 3. shares = 1   & _totalAssets = 1 & _totalSupply = 2  ; then output should be {Up: 1 , Down: 0 }
    /// 4. shares = 99  & _totalAssets = 1 & _totalSupply = 100; then output should be {Up: 1 , Down: 0 }
    /// 5. shares = 1   & _totalAssets = 1 & _totalSupply = 0  ; then output should be {Up: 1 , Down: 1 }
    /// 6. shares = 1   & _totalAssets = 0 & _totalSupply = 1  ; then output should be {Up: 0 , Down: 0 }
    function _convertToAssets(
        uint256 shares,
        MathUpgradeable.Rounding rounding
    ) internal view virtual override returns (uint256) {
        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();
        uint256 _effectiveAssets = enablePerformanceFee
            ? MathUpgradeable.min(_totalAssets, uint256(totalPrincipal))
            : _totalAssets;

        if (_totalSupply == 0) {
            return 1;
        }

        uint256 _assets = MathUpgradeable.mulDiv(shares, _effectiveAssets, _totalSupply, rounding);
        return _assets;
    }

    /// @dev Override internal deposit to track total principal
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override whenNotPaused {
        super._deposit(caller, receiver, assets, shares);

        if (address(subVault) != address(0)) {
            IERC20 underlyingAsset = IERC20(asset());
            // todo: should we deposit only users assets and account for trasnfer fee or keep depositing _idleAssets?
            uint256 _idleAssets = underlyingAsset.balanceOf(address(this));
            subVault.deposit(_idleAssets, address(this));
        }

        totalPrincipal += int256(assets);
    }

    /// @dev Override internal withdraw to track total principal
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override whenNotPaused {
        if (address(subVault) != address(0)) {
            subVault.withdraw(assets, address(this), address(this));
        }

        // todo: account trasnfer fee? should we withdraw all? should we validate against users assets if transfer fee accure?
        super._withdraw(caller, receiver, owner, assets, shares);
        totalPrincipal -= int256(assets);
    }

    /// SubVault management methods ///

    /// @notice Set a subvault. Can only be called if there is not already a subvault set.
    /// @param  _subVault The subvault to set. Must be an ERC4626 vault with the same asset as this MasterVault.
    /// @param  minSubVaultExchRateWad Minimum acceptable ratio (times 1e18) of new subvault shares to outstanding MasterVault shares after deposit.
    function setSubVault(
        IERC4626 _subVault,
        uint256 minSubVaultExchRateWad
    ) external onlyRole(VAULT_MANAGER_ROLE) {
        IERC20 underlyingAsset = IERC20(asset());
        if (address(subVault) != address(0)) revert SubVaultAlreadySet();
        if (address(_subVault.asset()) != address(underlyingAsset)) revert SubVaultAssetMismatch();

        subVault = _subVault;

        IERC20(asset()).safeApprove(address(_subVault), type(uint256).max);
        _subVault.deposit(underlyingAsset.balanceOf(address(this)), address(this));

        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0) {
            uint256 subVaultExchRateWad = MathUpgradeable.mulDiv(
                _subVault.balanceOf(address(this)),
                1e18,
                totalSupply(),
                MathUpgradeable.Rounding.Down
            );
            if (subVaultExchRateWad < minSubVaultExchRateWad)
                revert NewSubVaultExchangeRateTooLow();
        }

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

        uint256 assetExchRateWad = MathUpgradeable.mulDiv(
            IERC20(asset()).balanceOf(address(this)),
            1e18,
            totalSupply(),
            MathUpgradeable.Rounding.Down
        );
        if (assetExchRateWad < minAssetExchRateWad) revert SubVaultExchangeRateTooLow();

        emit SubvaultChanged(address(oldSubVault), address(0));
    }

    /// Max methods needed only if SubVault is set ///

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address receiver) public view virtual override returns (uint256) {
        if (address(subVault) == address(0)) {
            return super.maxDeposit(receiver);
        }
        return subVault.maxDeposit(receiver);
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(address receiver) public view virtual override returns (uint256) {
        if (address(subVault) == address(0)) {
            return super.maxMint(receiver);
        }
        return subVault.maxMint(receiver);
    }

    /** @dev See {IERC4626-maxWithdraw}. */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        if (address(subVault) == address(0)) {
            return super.maxWithdraw(owner);
        }
        return subVault.maxWithdraw(address(this));
    }

    /** @dev See {IERC4626-maxRedeem}. */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        if (address(subVault) == address(0)) {
            return super.maxRedeem(owner);
        }
        return subVault.maxRedeem(address(this));
    }
}
