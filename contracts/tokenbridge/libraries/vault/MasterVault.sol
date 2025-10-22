// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MasterVault is Initializable, ERC4626Upgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;

    error TooFewSharesReceived();
    error TooManySharesBurned();
    error TooManyAssetsDeposited();
    error TooFewAssetsReceived();
    error SubVaultAlreadySet();
    error SubVaultCannotBeZeroAddress();
    error MustHaveSupplyBeforeSettingSubVault();
    error SubVaultAssetMismatch();
    error SubVaultExchangeRateTooLow();
    error NoExistingSubVault();
    error MustHaveSupplyBeforeSwitchingSubVault();
    error NewSubVaultExchangeRateTooLow();
    error BeneficiaryNotSet();
    error PerformanceFeeDisabled();
    error InvalidAsset();
    error InvalidOwner();

    // todo: avoid inflation, rounding, other common 4626 vulns
    // we may need a minimum asset or master share amount when setting subvaults (bc of exchange rate calc)
    IERC4626 public subVault;

    // how many subVault shares one MV2 share can be redeemed for
    // initially 1 to 1
    // constant per subvault
    // changes when subvault is set
    uint256 public subVaultExchRateWad;

    // note: the performance fee can be avoided if the underlying strategy can be sandwiched (eg ETH to wstETH dex swap)
    // maybe a simpler and more robust implementation would be for the owner to adjust the subVaultExchRateWad directly
    // this would also avoid the need for totalPrincipal tracking
    // however, this would require more trust in the owner
    bool public enablePerformanceFee;
    address public beneficiary;
    uint256 totalPrincipal; // total assets deposited, used to calculate profit

    event SubvaultChanged(address indexed oldSubvault, address indexed newSubvault);
    event PerformanceFeeToggled(bool enabled);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);

    function initialize(IERC20 _asset, string memory _name, string memory _symbol, address _owner) external initializer {
        if (address(_asset) == address(0)) revert InvalidAsset();
        if (_owner == address(0)) revert InvalidOwner();

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20Upgradeable(address(_asset)));
        _transferOwnership(_owner);

        subVaultExchRateWad = 1e18;
    }


    function deposit(uint256 assets, address receiver, uint256 minSharesMinted) public returns (uint256) {
        uint256 shares = deposit(assets, receiver);
        if (shares < minSharesMinted) revert TooFewSharesReceived();
        return shares;
    }

    function withdraw(uint256 assets, address receiver, address _owner, uint256 maxSharesBurned) public returns (uint256) {
        uint256 shares = withdraw(assets, receiver, _owner);
        if (shares > maxSharesBurned) revert TooManySharesBurned();
        return shares;
    }

    function mint(uint256 shares, address receiver, uint256 maxAssetsDeposited) public returns (uint256) {
        uint256 assets = super.mint(shares, receiver);
        if (assets > maxAssetsDeposited) revert TooManyAssetsDeposited();
        return assets;
    }

    function redeem(uint256 shares, address receiver, address _owner, uint256 minAssetsReceived) public returns (uint256) {
        uint256 assets = super.redeem(shares, receiver, _owner);
        if (assets < minAssetsReceived) revert TooFewAssetsReceived();
        return assets;
    }

    /// @notice Set a subvault. Can only be called if there is not already a subvault set.
    /// @param  _subVault The subvault to set. Must be an ERC4626 vault with the same asset as this MasterVault.
    /// @param  minSubVaultExchRateWad Minimum acceptable ratio (times 1e18) of new subvault shares to outstanding MasterVault shares after deposit.
    function setSubVault(IERC4626 _subVault, uint256 minSubVaultExchRateWad) external onlyOwner {
        if (address(subVault) != address(0)) revert SubVaultAlreadySet();
        _setSubVault(_subVault, minSubVaultExchRateWad);
    }

    /// @notice Revokes the current subvault, moving all assets back to MasterVault
    /// @param minAssetExchRateWad Minimum acceptable ratio (times 1e18) of assets received from subvault to outstanding MasterVault shares
    function revokeSubVault(uint256 minAssetExchRateWad) external onlyOwner {
        _revokeSubVault(minAssetExchRateWad);
    }

    function _setSubVault(IERC4626 _subVault, uint256 minSubVaultExchRateWad) internal {
        if (address(_subVault) == address(0)) revert SubVaultCannotBeZeroAddress();
        if (totalSupply() == 0) revert MustHaveSupplyBeforeSettingSubVault();
        if (address(_subVault.asset()) != address(asset())) revert SubVaultAssetMismatch();

        IERC20(asset()).safeApprove(address(_subVault), type(uint256).max);
        uint256 subShares = _subVault.deposit(totalAssets(), address(this));

        subVault = _subVault;

        uint256 _subVaultExchRateWad = subShares.mulDiv(1e18, totalAssets(), MathUpgradeable.Rounding.Down);
        if (_subVaultExchRateWad < minSubVaultExchRateWad) revert SubVaultExchangeRateTooLow();
        subVaultExchRateWad = _subVaultExchRateWad;

        emit SubvaultChanged(address(0), address(_subVault));
    }

    function _revokeSubVault(uint256 minAssetExchRateWad) internal {
        IERC4626 oldSubVault = subVault;
        if (address(oldSubVault) == address(0)) revert NoExistingSubVault();

        uint256 _totalSupply = totalSupply();
        uint256 assetReceived = oldSubVault.withdraw(oldSubVault.maxWithdraw(address(this)), address(this), address(this));
        uint256 effectiveAssetExchRateWad = assetReceived.mulDiv(1e18, _totalSupply, MathUpgradeable.Rounding.Down);
        if (effectiveAssetExchRateWad < minAssetExchRateWad) revert TooFewAssetsReceived();

        IERC20(asset()).safeApprove(address(oldSubVault), 0);
        subVault = IERC4626(address(0));
        subVaultExchRateWad = 1e18;

        emit SubvaultChanged(address(oldSubVault), address(0));
    }

    /// @notice Switches to a new subvault or revokes current subvault if newSubVault is zero address
    /// @param newSubVault The new subvault to switch to, or zero address to revoke current subvault
    /// @param minAssetExchRateWad Minimum acceptable ratio (times 1e18) of assets received from old subvault to outstanding MasterVault shares
    /// @param minNewSubVaultExchRateWad Minimum acceptable ratio (times 1e18) of new subvault shares to outstanding MasterVault shares after deposit
    function switchSubVault(IERC4626 newSubVault, uint256 minAssetExchRateWad, uint256 minNewSubVaultExchRateWad) external onlyOwner {
        _revokeSubVault(minAssetExchRateWad);

        if (address(newSubVault) != address(0)) {
            _setSubVault(newSubVault, minNewSubVaultExchRateWad);
        }
    }

    function masterSharesToSubShares(uint256 masterShares, MathUpgradeable.Rounding rounding) public view returns (uint256) {
        return masterShares.mulDiv(subVaultExchRateWad, 1e18, rounding);
    }

    function subSharesToMasterShares(uint256 subShares, MathUpgradeable.Rounding rounding) public view returns (uint256) {
        return subShares.mulDiv(1e18, subVaultExchRateWad, rounding);
    }

    /// @notice Toggle performance fee collection on/off
    /// @param enabled True to enable performance fees, false to disable
    function setPerformanceFee(bool enabled) external onlyOwner {
        enablePerformanceFee = enabled;
        emit PerformanceFeeToggled(enabled);
    }

    /// @notice Set the beneficiary address for performance fees
    /// @param newBeneficiary Address to receive performance fees, zero address defaults to owner
    function setBeneficiary(address newBeneficiary) external onlyOwner {
        address oldBeneficiary = beneficiary;
        beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(oldBeneficiary, newBeneficiary);
    }

    /// @notice Withdraw all accumulated performance fees to beneficiary
    /// @dev Only callable by owner when performance fees are enabled
    function withdrawPerformanceFees() external onlyOwner {
        if (!enablePerformanceFee) revert PerformanceFeeDisabled();
        if (beneficiary == address(0)) revert BeneficiaryNotSet();

        uint256 totalProfits = totalProfit();
        if (totalProfits > 0) {
            IERC4626 _subVault = subVault;
            if (address(_subVault) != address(0)) {
                _subVault.withdraw(totalProfits, address(this), address(this));
            }
            IERC20(asset()).safeTransfer(beneficiary, totalProfits);
        }
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        IERC4626 _subVault = subVault;
        if (address(_subVault) == address(0)) {
            return super.totalAssets();
        }
        return _subVault.convertToAssets(_subVault.balanceOf(address(this)));
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public view virtual override returns (uint256) {
        if (address(subVault) == address(0)) {
            return type(uint256).max;
        }
        return subVault.maxDeposit(address(this));
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(address) public view virtual override returns (uint256) {
        uint256 subShares = subVault.maxMint(address(this));
        if (subShares == type(uint256).max) {
            return type(uint256).max;
        }
        return subSharesToMasterShares(subShares, MathUpgradeable.Rounding.Down);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding) internal view virtual override returns (uint256 shares) {
        IERC4626 _subVault = subVault;
        if (address(_subVault) == address(0)) {
            return super._convertToShares(assets, rounding);
        }
        uint256 subShares = rounding == MathUpgradeable.Rounding.Up ? _subVault.previewWithdraw(assets) : _subVault.previewDeposit(assets);
        return subSharesToMasterShares(subShares, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding) internal view virtual override returns (uint256 assets) {
        IERC4626 _subVault = subVault;
        if (address(_subVault) == address(0)) {
            return super._convertToAssets(shares, rounding);
        }
        uint256 subShares = masterSharesToSubShares(shares, rounding);
        return rounding == MathUpgradeable.Rounding.Up ? _subVault.previewMint(subShares) : _subVault.previewRedeem(subShares);
    }

    function totalProfit() public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        return _totalAssets > totalPrincipal ? _totalAssets - totalPrincipal : 0;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        super._deposit(caller, receiver, assets, shares);

        totalPrincipal += assets;
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
    ) internal virtual override {
        totalPrincipal -= assets;

        IERC4626 _subVault = subVault;
        if (address(_subVault) != address(0)) {
            _subVault.withdraw(assets, address(this), address(this));
        }

        super._withdraw(caller, receiver, _owner, assets, shares);
    }
}