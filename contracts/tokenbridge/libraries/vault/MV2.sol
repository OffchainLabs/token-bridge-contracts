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

    // todo: avoid inflation, rounding, other common 4626 vulns
    // we may need a minimum asset or master share amount when setting subvaults (bc of exchange rate calc)

    ERC4626 public subVault;

    // how many subVault shares one MV2 share can be redeemed for
    // initially 1 to 1
    // constant per subvault
    // changes when subvault is set
    uint256 public subVaultExchRateWad = 1e18;

    // note: the performance fee can be avoided if the underlying strategy can be sandwiched (eg ETH to wstETH dex swap)
    // maybe a simpler and more robust implementation would be for the owner to adjust the subVaultExchRateWad directly
    // this would also avoid the need for totalPrincipal tracking
    // however, this would require more trust in the owner
    uint256 public performanceFeeBps; // in basis points, e.g. 200 = 2% | todo a way to set this
    uint256 totalPrincipal; // total assets deposited, used to calculate profit

    event SubvaultChanged(address indexed oldSubvault, address indexed newSubvault);

    constructor(IERC20 _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC4626(_asset) Ownable() {}

    function deposit(uint256 assets, address receiver, uint256 minSharesMinted) public returns (uint256) {
        uint256 shares = super.deposit(assets, receiver);
        require(shares >= minSharesMinted, "too few shares received");
        return shares;
    }

    function withdraw(uint256 assets, address receiver, address _owner, uint256 maxSharesBurned) public returns (uint256) {
        uint256 shares = super.withdraw(assets, receiver, _owner);
        require(shares <= maxSharesBurned, "too many shares burned");
        return shares;
    }

    function mint(uint256 shares, address receiver, uint256 maxAssetsDeposited) public returns (uint256) {
        uint256 assets = super.mint(shares, receiver);
        require(assets <= maxAssetsDeposited, "too many assets deposited");
        return assets;
    }

    function redeem(uint256 shares, address receiver, address _owner, uint256 minAssetsReceived) public returns (uint256) {
        uint256 assets = super.redeem(shares, receiver, _owner);
        require(assets >= minAssetsReceived, "too few assets received");
        return assets;
    }

    // todo: can probably pull some of this stuff out into internal functions
    function setSubVault(ERC4626 _subVault, uint256 minSubVaultShares) external onlyOwner {
        require(address(subVault) == address(0), "subvault already set");
        require(totalSupply() > 0, "must have supply before setting subvault");

        // deposit to subvault
        IERC20(asset()).safeApprove(address(_subVault), type(uint256).max);
        uint256 subShares = _subVault.deposit(totalAssets(), address(this));
        require(subShares >= minSubVaultShares, "too few subvault shares");

        // set new exchange rate
        subVaultExchRateWad = subShares.mulDiv(1e18, totalSupply(), Math.Rounding.Down);

        // set subvault
        subVault = _subVault;

        emit SubvaultChanged(address(0), address(_subVault));
    }

    function switchSubVault(ERC4626 newSubVault, uint256 minAssetReceived, uint256 minNewSubVaultShares) external onlyOwner {
        ERC4626 oldSubVault = subVault;
        require(address(oldSubVault) != address(0), "no existing subvault");

        // withdraw from old subvault
        uint256 assetReceived = oldSubVault.withdraw(oldSubVault.maxWithdraw(address(this)), address(this), address(this));
        require(assetReceived >= minAssetReceived, "too few assets received");

        // revoke approval from old subvault
        IERC20(asset()).safeApprove(address(oldSubVault), 0);

        // deposit to new subvault
        if (address(newSubVault) != address(0)) {
            IERC20(asset()).safeApprove(address(newSubVault), type(uint256).max);
            uint256 newSubShares = newSubVault.deposit(totalAssets(), address(this));
            require(newSubShares >= minNewSubVaultShares, "too few new subvault shares");

            // set new exchange rate
            subVaultExchRateWad = newSubShares.mulDiv(1e18, totalSupply(), Math.Rounding.Down);
        }
        else {
            subVaultExchRateWad = 1e18;
        }

        // set subvault
        subVault = newSubVault;

        emit SubvaultChanged(address(oldSubVault), address(newSubVault));
    }

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

        ////// PERF FEE STUFF //////
        // determine profit portion and principal portion of assets
        uint256 _totalProfit = totalProfit();
        // use shares because they are rounded up vs assets which are rounded down
        uint256 profitPortion = shares.mulDiv(_totalProfit, totalSupply(), Math.Rounding.Up);
        uint256 principalPortion = assets - profitPortion;
      
        // subtract principal portion from totalPrincipal
        totalPrincipal -= principalPortion;

        // send fee to owner
        if (performanceFeeBps > 0 && profitPortion > 0) {
            uint256 fee = profitPortion.mulDiv(performanceFeeBps, 10000, Math.Rounding.Up);
            // send fee to owner
            IERC20(asset()).safeTransfer(owner(), fee);

            // note subtraction
            assets -= fee;
        }

        ////// END PERF FEE STUFF //////

        // call super._withdraw with remaining assets
        super._withdraw(caller, receiver, _owner, assets, shares);
    }
}