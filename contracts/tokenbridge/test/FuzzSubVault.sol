// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Minimal vault mock for fuzz/invariant testing.
/// @dev    Only implements the ERC4626 subset that MasterVault actually calls:
///         asset(), deposit(), withdraw(), redeem(), maxDeposit(), maxWithdraw(),
///         maxRedeem(), previewMint(), previewRedeem(), balanceOf() (via ERC20).
///         No full ERC4626 inheritance — keeps the mock auditable.
contract FuzzSubVault is ERC20 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 private immutable _asset;
    uint256 public maxWithdrawLimit = type(uint256).max;
    uint256 public maxDepositLimit = type(uint256).max;
    uint256 public maxRedeemLimit = type(uint256).max;

    uint256 public depositErrorWad;
    uint256 public withdrawErrorWad;
    uint256 public redeemErrorWad;
    uint256 public previewMintErrorWad;
    uint256 public previewRedeemErrorWad;

    constructor(IERC20 asset_, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _asset = asset_;
    }

    function asset() public view returns (address) {
        return address(_asset);
    }

    function totalAssets() public view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(assets <= maxDepositLimit, "FuzzSubVault: deposit exceeds max");
        shares = _penalizeDown(_convertToShares(assets, Math.Rounding.Down), depositErrorWad);
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        require(assets <= maxWithdrawLimit, "FuzzSubVault: withdraw exceeds max");
        shares = _penalizeUp(_convertToShares(assets, Math.Rounding.Up), withdrawErrorWad);
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        uint256 ownerAssets = _convertToAssets(balanceOf(owner), Math.Rounding.Down);
        uint256 available = totalAssets();
        uint256 natural = ownerAssets < available ? ownerAssets : available;
        return natural < maxWithdrawLimit ? natural : maxWithdrawLimit;
    }

    function maxRedeem(address owner) public view returns (uint256) {
        uint256 bal = balanceOf(owner);
        return bal < maxRedeemLimit ? bal : maxRedeemLimit;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = _penalizeDown(_convertToAssets(shares, Math.Rounding.Down), redeemErrorWad);
        require(shares <= maxRedeemLimit, "FuzzSubVault: redeem exceeds max");
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
    }

    function maxDeposit(address) public view returns (uint256) {
        return maxDepositLimit;
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return _penalizeUp(_convertToAssets(shares, Math.Rounding.Up), previewMintErrorWad);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _penalizeDown(_convertToAssets(shares, Math.Rounding.Down), previewRedeemErrorWad);
    }

    // --- Test helpers ---

    function adminMint(address to, uint256 shares) external {
        _mint(to, shares);
    }

    function adminBurn(address from, uint256 shares) external {
        _burn(from, shares);
    }

    function setMaxWithdrawLimit(uint256 limit) external {
        maxWithdrawLimit = limit;
    }

    function setMaxDepositLimit(uint256 limit) external {
        maxDepositLimit = limit;
    }

    function setMaxRedeemLimit(uint256 limit) external {
        maxRedeemLimit = limit;
    }

    function setDepositErrorWad(uint256 wad) external {
        depositErrorWad = wad;
    }

    function setWithdrawErrorWad(uint256 wad) external {
        withdrawErrorWad = wad;
    }

    function setRedeemErrorWad(uint256 wad) external {
        redeemErrorWad = wad;
    }

    function setPreviewMintErrorWad(uint256 wad) external {
        previewMintErrorWad = wad;
    }

    function setPreviewRedeemErrorWad(uint256 wad) external {
        previewRedeemErrorWad = wad;
    }

    // --- Internal math ---

    function _penalizeDown(uint256 value, uint256 errWad) private pure returns (uint256) {
        if (errWad == 0) return value;
        return value.mulDiv(1e18 - errWad, 1e18, Math.Rounding.Down);
    }

    function _penalizeUp(uint256 value, uint256 errWad) private pure returns (uint256) {
        if (errWad == 0) return value;
        return value.mulDiv(1e18 + errWad, 1e18, Math.Rounding.Up);
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) private view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return assets;
        return assets.mulDiv(supply, totalAssets(), rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) private view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        return shares.mulDiv(totalAssets(), supply, rounding);
    }
}
