// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Minimal vault mock for fuzz/invariant testing.
/// @dev    Only implements the ERC4626 subset that MasterVault actually calls:
///         asset(), deposit(), withdraw(), maxDeposit(), maxWithdraw(),
///         previewMint(), previewRedeem(), balanceOf() (via ERC20).
///         No full ERC4626 inheritance — keeps the mock auditable.
contract FuzzSubVault is ERC20 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 private immutable _asset;
    uint256 public maxWithdrawLimit = type(uint256).max;
    uint256 public maxDepositLimit = type(uint256).max;

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
        shares = _convertToShares(assets, Math.Rounding.Down);
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        require(assets <= maxWithdrawLimit, "FuzzSubVault: withdraw exceeds max");
        shares = _convertToShares(assets, Math.Rounding.Up);
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        uint256 ownerAssets = _convertToAssets(balanceOf(owner), Math.Rounding.Down);
        uint256 available = totalAssets();
        uint256 natural = ownerAssets < available ? ownerAssets : available;
        return natural < maxWithdrawLimit ? natural : maxWithdrawLimit;
    }

    function maxDeposit(address) public view returns (uint256) {
        return maxDepositLimit;
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Up);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
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

    // --- Internal math ---

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
