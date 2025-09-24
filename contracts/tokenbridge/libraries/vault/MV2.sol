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

    ERC4626 public subVault;
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

    function setSubVault(ERC4626 _subVault, uint256 minSubVaultShares) external onlyOwner {
        require(address(subVault) == address(0), "subvault already set");

        // deposit to subvault
        IERC20(asset()).safeApprove(address(_subVault), type(uint256).max);
        uint256 subShares = _subVault.deposit(totalAssets(), address(this));
        require(subShares >= minSubVaultShares, "too few subvault shares");

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
        }

        // set subvault
        subVault = newSubVault;

        emit SubvaultChanged(address(oldSubVault), address(newSubVault));
    }

    // todo: make these handle a zero subvault
    function masterSharesToSubShares(uint256 masterShares, Math.Rounding rounding) public view returns (uint256) {
        return masterShares.mulDiv(subVault.totalSupply(), totalSupply(), rounding);
    }
    function subSharesToMasterShares(uint256 subShares, Math.Rounding rounding) public view returns (uint256) {
        return subShares.mulDiv(totalSupply(), subVault.totalSupply(), rounding);
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        ERC4626 _subVault = subVault;
        uint256 _totalAssets = address(_subVault) == address(0) ? super.totalAssets() : _subVault.convertToAssets(_subVault.balanceOf(address(this)));
        uint256 profit = _totalAssets > totalPrincipal ? _totalAssets - totalPrincipal : 0;
        uint256 fee = (profit * performanceFeeBps) / 10_000;
        return _totalAssets - fee;
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
        // determine how much of the users withdrawal is principal vs profit
        // we want to bias this calculation towards increasing the size of profit vs principal
        // so that we bias towards the vault owner instead of the users
        // we'll subtract this user's principal portion from the total principal, so we want to round up
        // shares should be rounded up as well
        totalPrincipal -= totalPrincipal.mulDiv(shares, totalSupply(), Math.Rounding.Up);

        ERC4626 _subVault = subVault;
        if (address(_subVault) != address(0)) {
            _subVault.withdraw(assets, address(this), address(this));
        }
        super._withdraw(caller, receiver, _owner, assets, shares);
    }
}