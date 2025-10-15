// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MasterVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

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
    error InvalidAllocationBps();
    error MustReduceAllocationBeforeSwitching();
    error NoSubVaultToRebalance();
    error NoAssetsToRebalance();

    ERC4626 public subVault;

    // how many subVault shares one MV2 share can be redeemed for
    // initially 1 to 1
    // constant per subvault
    // changes when subvault is set
    uint256 public subVaultExchRateWad = 1e18;

    uint256 public targetSubVaultAllocationBps = 10000;

    bool public enablePerformanceFee;
    address public beneficiary;
    uint256 totalPrincipal; // total assets deposited, used to calculate profit

    event SubvaultChanged(address indexed oldSubvault, address indexed newSubvault);
    event PerformanceFeeToggled(bool enabled);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event TargetAllocationChanged(uint256 oldBps, uint256 newBps);
    event Rebalanced(uint256 shares, int256 deltaAssets);

    constructor(IERC20 _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC4626(_asset) Ownable() {}

    function deposit(uint256 assets, address receiver, uint256 minSharesMinted) public returns (uint256) {
        uint256 shares = super.deposit(assets, receiver);
        if (shares < minSharesMinted) revert TooFewSharesReceived();
        return shares;
    }

    function withdraw(uint256 assets, address receiver, address _owner, uint256 maxSharesBurned) public returns (uint256) {
        uint256 shares = super.withdraw(assets, receiver, _owner);
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
    function setSubVault(ERC4626 _subVault, uint256 minSubVaultExchRateWad) external onlyOwner {
        if (address(subVault) != address(0)) revert SubVaultAlreadySet();
        _setSubVault(_subVault, minSubVaultExchRateWad);
    }

    /// @notice Revokes the current subvault, moving all assets back to MasterVault
    /// @param minAssetExchRateWad Minimum acceptable ratio (times 1e18) of assets received from subvault to outstanding MasterVault shares
    function revokeSubVault(uint256 minAssetExchRateWad) external onlyOwner {
        _revokeSubVault(minAssetExchRateWad);
    }

    function _setSubVault(ERC4626 _subVault, uint256 minSubVaultExchRateWad) internal {
        if (address(_subVault) == address(0)) revert SubVaultCannotBeZeroAddress();
        if (totalSupply() == 0) revert MustHaveSupplyBeforeSettingSubVault();
        if (address(_subVault.asset()) != address(asset())) revert SubVaultAssetMismatch();

        IERC20(asset()).safeApprove(address(_subVault), type(uint256).max);
        uint256 subShares = _subVault.deposit(totalAssets(), address(this));

        uint256 _subVaultExchRateWad = subShares.mulDiv(1e18, totalSupply(), Math.Rounding.Down);
        if (_subVaultExchRateWad < minSubVaultExchRateWad) revert SubVaultExchangeRateTooLow();
        subVaultExchRateWad = _subVaultExchRateWad;

        subVault = _subVault;

        emit SubvaultChanged(address(0), address(_subVault));
    }

    function _revokeSubVault(uint256 minAssetExchRateWad) internal {
        ERC4626 oldSubVault = subVault;
        if (address(oldSubVault) == address(0)) revert NoExistingSubVault();

        uint256 _totalSupply = totalSupply();
        uint256 maxWithdrawable = oldSubVault.maxWithdraw(address(this));
        uint256 assetReceived = 0;

        if (maxWithdrawable > 0) {
            assetReceived = oldSubVault.withdraw(maxWithdrawable, address(this), address(this));
            uint256 effectiveAssetExchRateWad = assetReceived.mulDiv(1e18, _totalSupply, Math.Rounding.Down);
            if (effectiveAssetExchRateWad < minAssetExchRateWad) revert TooFewAssetsReceived();
        }

        IERC20(asset()).safeApprove(address(oldSubVault), 0);
        subVault = ERC4626(address(0));
        subVaultExchRateWad = 1e18;

        emit SubvaultChanged(address(oldSubVault), address(0));
    }

    /// @notice Switches to a new subvault or revokes current subvault if newSubVault is zero address
    /// @param newSubVault The new subvault to switch to, or zero address to revoke current subvault
    /// @param minAssetExchRateWad Minimum acceptable ratio (times 1e18) of assets received from old subvault to outstanding MasterVault shares
    /// @param minNewSubVaultExchRateWad Minimum acceptable ratio (times 1e18) of new subvault shares to outstanding MasterVault shares after deposit
    function switchSubVault(ERC4626 newSubVault, uint256 minAssetExchRateWad, uint256 minNewSubVaultExchRateWad) external onlyOwner {
        if (targetSubVaultAllocationBps != 0) revert MustReduceAllocationBeforeSwitching();

        _revokeSubVault(minAssetExchRateWad);

        if (address(newSubVault) != address(0)) {
            _setSubVault(newSubVault, minNewSubVaultExchRateWad);
        }
    }

    function setTargetAllocation(uint256 newBps, int256 minSubVaultExchRateWad) external onlyOwner {
        if (newBps > 10000) revert InvalidAllocationBps();
        uint256 oldBps = targetSubVaultAllocationBps;
        targetSubVaultAllocationBps = newBps;
        emit TargetAllocationChanged(oldBps, newBps);

        if (address(subVault) != address(0) && totalAssets() > 0 && oldBps != newBps) {
            _rebalance(minSubVaultExchRateWad);
        }
    }

    function currentAllocationBps() public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        if (_totalAssets == 0) return 0;

        ERC4626 _subVault = subVault;
        if (address(_subVault) == address(0)) return 0;

        uint256 subVaultAssets = _subVault.convertToAssets(_subVault.balanceOf(address(this)));
        return subVaultAssets.mulDiv(10000, _totalAssets, Math.Rounding.Down);
    }

    function rebalance(int256 minSubVaultExchRateWad) external onlyOwner {
        _rebalance(minSubVaultExchRateWad);
    }

    /// @param minSubVaultExchRateWad Minimum acceptable ratio (times 1e18) of subvault shares to underlying assets when depositing to or withdrawing from subvault
    ///                               Negative is withdrawal from subvault, positive is deposit to subvault
    function _rebalance(int256 minSubVaultExchRateWad) internal {
        if (minSubVaultExchRateWad == 0) {
            revert("zero exch rate");
        }

        ERC4626 _subVault = subVault;
        if (address(_subVault) == address(0)) revert NoSubVaultToRebalance();

        uint256 _totalAssets = totalAssets();
        if (_totalAssets == 0) revert NoAssetsToRebalance();

        uint256 currentBps = currentAllocationBps();
        uint256 targetBps = targetSubVaultAllocationBps;

        if (currentBps == targetBps) {
            revert("already at target");
        }

        uint256 targetSubVaultAssets = _totalAssets.mulDiv(targetBps, 10000, Math.Rounding.Down);
        uint256 currentSubVaultAssets = _subVault.convertToAssets(_subVault.balanceOf(address(this)));

        // assumed no casts will flip sign
        int256 deltaSubVaultAssets = int256(targetSubVaultAssets) - int256(currentSubVaultAssets);

        if (deltaSubVaultAssets == 0) {
            revert("no delta");
        }

        // if the delta disagrees with the sign of the slippage tolerance, we should revert
        if (deltaSubVaultAssets < 0 && minSubVaultExchRateWad > 0) {
            revert("negative delta but positive exch rate");
        }
        if (deltaSubVaultAssets > 0 && minSubVaultExchRateWad < 0) {
            revert("positive delta but negative exch rate");
        }

        // make sure we can deposit or withdraw the required amount to get to target
        if (deltaSubVaultAssets < 0 && _subVault.maxWithdraw(address(this)) < uint256(-deltaSubVaultAssets)) {
            revert("cannot withdraw enough");
        }
        if (deltaSubVaultAssets > 0 && IERC20(asset()).balanceOf(address(this)) < uint256(deltaSubVaultAssets)) {
            revert("not enough liquid"); // question: this should be impossible?
        }

        // absolute value of deltaSubVaultAssets
        uint256 absDeltaSubVaultAssets = deltaSubVaultAssets > 0 ? uint256(deltaSubVaultAssets) : uint256(-deltaSubVaultAssets);

        // perform the rebalance and track number of shares received or burned
        uint256 shares = deltaSubVaultAssets > 0
            ? _subVault.deposit(absDeltaSubVaultAssets, address(this))
            : _subVault.withdraw(absDeltaSubVaultAssets, address(this), address(this));

        // compute absolute value of effective exchange rate
        // round against the tolerance to be conservative
        uint256 absEffectiveExchRateWad = shares.mulDiv(1e18, absDeltaSubVaultAssets, deltaSubVaultAssets > 0 ? Math.Rounding.Down : Math.Rounding.Up);
        // give the appropriate sign to the effective exchange rate
        int256 effectiveExchRateWad = deltaSubVaultAssets > 0 ? int256(absEffectiveExchRateWad) : -int256(absEffectiveExchRateWad);

        // make sure the effective exchange rate meets the minimum specified
        if (effectiveExchRateWad < minSubVaultExchRateWad) {
            revert("exch rate too low");
        }

        emit Rebalanced(shares, deltaSubVaultAssets);
    }

    function masterSharesToSubShares(uint256 masterShares, Math.Rounding rounding) public view returns (uint256) {
        return masterShares.mulDiv(subVaultExchRateWad, 1e18, rounding);
    }

    function subSharesToMasterShares(uint256 subShares, Math.Rounding rounding) public view returns (uint256) {
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
            ERC4626 _subVault = subVault;
            if (address(_subVault) != address(0)) {
                _subVault.withdraw(totalProfits, address(this), address(this));
            }
            IERC20(asset()).safeTransfer(beneficiary, totalProfits);
        }
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        ERC4626 _subVault = subVault;
        uint256 liquidAssets = IERC20(asset()).balanceOf(address(this));
        if (address(_subVault) == address(0)) {
            return liquidAssets;
        }
        return liquidAssets + _subVault.convertToAssets(_subVault.balanceOf(address(this)));
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
        return subSharesToMasterShares(subShares, Math.Rounding.Down);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256 shares) {
        ERC4626 _subVault = subVault;
        if (address(_subVault) == address(0)) {
            return super._convertToShares(assets, rounding);
        }
        uint256 subShares = rounding == Math.Rounding.Up ? _subVault.previewWithdraw(assets) : _subVault.previewDeposit(assets);
        return subSharesToMasterShares(subShares, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256 assets) {
        ERC4626 _subVault = subVault;
        if (address(_subVault) == address(0)) {
            return super._convertToAssets(shares, rounding);
        }
        uint256 subShares = masterSharesToSubShares(shares, rounding);
        return rounding == Math.Rounding.Up ? _subVault.previewMint(subShares) : _subVault.previewRedeem(subShares);
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
        ERC4626 _subVault = subVault;
        if (address(_subVault) != address(0)) {
            uint256 assetsToDeposit = assets.mulDiv(targetSubVaultAllocationBps, 10000, Math.Rounding.Down);
            if (assetsToDeposit > 0) {
                _subVault.deposit(assetsToDeposit, address(this));
            }
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

        uint256 liquidAssets = IERC20(asset()).balanceOf(address(this));
        uint256 assetsFromSubVault = 0;

        if (liquidAssets < assets) {
            assetsFromSubVault = assets - liquidAssets;
            ERC4626 _subVault = subVault;
            if (address(_subVault) != address(0)) {
                _subVault.withdraw(assetsFromSubVault, address(this), address(this));
            }
        }

        super._withdraw(caller, receiver, _owner, assets, shares);
    }
}