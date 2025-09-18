// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "lib/forge-std/src/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev this is an abstruct contract that is used to create a sub vault by bridge owner
/// bridge owner must set the master vault address 
/// it is up to the owner to implement sub-strategies for this vault
/// this vault will issue shares to the master vault
abstract contract SubVault is ERC20, IERC4626 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        asset = _asset;
    }

    modifier onlyMasterVault() {
        // TBD let owner set the master vault
        _;
    }

    /// @dev this function is used to deposit assets into the sub vault
    /// @param amount the amount of assets to deposit
    /// @param receiver the address that deposit the underlying assets and receive shares
    function deposit(uint256 amount, address receiver) external override onlyMasterVault {
        // todo: mint shares to receiver
        asset.safeTransferFrom(receiver, address(this), amount);
    }

    /// @dev this function is used to withdraw assets from the sub vault
    /// @param amount the amount of assets to withdraw
    /// @param recipient the address that withdraw the underlying assets
    /// @param owner the address that owns the shares
    function withdraw(uint256 amount, address recipient, address owner) external override onlyMasterVault {
        // todo: burn shares from owner
        asset.safeTransfer(recipient, amount);
    }


    // todo: implement ERC4626 functions
}