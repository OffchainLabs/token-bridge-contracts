// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev this is an `abstruct` contract that is used to create a sub vault by bridge owner
/// bridge owner must set the master vault address
/// it is up to the owner to implement sub-strategies for this vault
/// this vault will issue shares to the master vault
/// @notice should be ERC4626 compatible. TODO: implement & override ERC4626 functions 
abstract contract SubVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    constructor(IERC20 _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        asset = _asset;
    }

    modifier onlyMasterVault() {
        // TBD let owner set the master vault
        _;
    }

    /// @dev this function is used to deposit assets into the sub vault
    /// @param _amount the amount of assets to deposit
    /// @param _receiver the address that deposit the underlying assets and receive shares,
    /// the receiver would be the gateway.
    function deposit(uint256 _amount, address _receiver) external onlyMasterVault {
        // todo: mint shares to receiver
        // slither-disable-next-line arbitrary-send-erc20
        asset.safeTransferFrom(_receiver, address(this), _amount);
    }

    /// @dev this function is used to withdraw assets from the sub vault
    /// @param _amount the amount of assets to withdraw
    /// @param _recipient the address that withdraw the underlying assets
    /// @param _owner the address that owns the shares
    function withdraw(uint256 _amount, address _recipient, address _owner) external onlyMasterVault {
        // todo: burn shares from owner
        asset.safeTransfer(_recipient, _amount);
    }

    // todo: implement ERC4626 functions
}
