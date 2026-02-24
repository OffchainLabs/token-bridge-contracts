// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Configurable ERC4626 mock for fuzz/invariant testing.
/// @dev    Unlike MockSubVault (which inherits OZ's fixed implementation), this mock gives
///         explicit control over the behaviors that matter for MasterVault correctness:
///         - Arbitrary exchange rates via adminMint/adminBurn
///         - Configurable maxWithdraw/maxDeposit limits (ERC4626 spec allows arbitrary limits)
contract FuzzSubVault is ERC4626 {
    uint256 public maxWithdrawLimit = type(uint256).max;
    uint256 public maxDepositLimit = type(uint256).max;

    constructor(IERC20 _asset, string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
        ERC4626(_asset)
    {}

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Mint shares without backing assets (creates totalAssets < totalSupply, simulates loss)
    function adminMint(address to, uint256 shares) external {
        _mint(to, shares);
    }

    /// @notice Burn shares without withdrawing assets (creates totalAssets > totalSupply)
    function adminBurn(address from, uint256 shares) external {
        _burn(from, shares);
    }

    function setMaxWithdrawLimit(uint256 limit) external {
        maxWithdrawLimit = limit;
    }

    function setMaxDepositLimit(uint256 limit) external {
        maxDepositLimit = limit;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 natural = super.maxWithdraw(owner);
        return natural < maxWithdrawLimit ? natural : maxWithdrawLimit;
    }

    function maxDeposit(address) public view override returns (uint256) {
        uint256 natural = super.maxDeposit(address(0));
        return natural < maxDepositLimit ? natural : maxDepositLimit;
    }
}
