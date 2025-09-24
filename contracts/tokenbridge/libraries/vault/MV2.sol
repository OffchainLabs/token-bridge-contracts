// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MV2 is ERC4626, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    ERC4626 public subVault;

    // how many subVault shares one MV2 share can be redeemed for
    // initially 1 to 1
    // constant per subvault
    // changes when subvault is set
    // todo: this initial rate should be whatever makes 1mstUSDC == 1USDC, not 1mstUSDC == 1stUSDC
    uint256 public subVaultExchRateWad = 1e18;

    event SubvaultChanged(address indexed oldSubvault, address indexed newSubvault);

    constructor(IERC20 _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC4626(_asset) Ownable() {}

    function masterSharesToSubShares(uint256 masterShares, Math.Rounding rounding) public view returns (uint256) {
        return masterShares.mulDiv(subVaultExchRateWad, 1e18, rounding);
    }

    function subSharesToMasterShares(uint256 subShares, Math.Rounding rounding) public view returns (uint256) {
        return subShares.mulDiv(1e18, subVaultExchRateWad, rounding);
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        ERC4626 _subVault = subVault;
        if (address(_subVault) == address(0)) {
            return super.totalAssets();
        }
        return _subVault.convertToAssets(_subVault.balanceOf(address(this)));
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public view virtual override returns (uint256) {
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
        return subSharesToMasterShares(_subVault.convertToShares(assets), rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256 assets) {
        ERC4626 _subVault = subVault;
        if (address(_subVault) == address(0)) {
            return super._convertToAssets(shares, rounding);
        }
        return _subVault.convertToAssets(masterSharesToSubShares(shares, rounding));
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
        ERC4626 _subVault = subVault;
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
        ERC4626 _subVault = subVault;
        if (address(_subVault) != address(0)) {
            _subVault.withdraw(assets, address(this), address(this));
        }
        super._withdraw(caller, receiver, _owner, assets, shares);
    }
}