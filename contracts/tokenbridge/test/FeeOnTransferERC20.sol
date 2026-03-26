// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./TestERC20.sol";

/// @dev ERC20 that takes a percentage fee on every transfer (not mint/burn).
///      Used to test that MasterVault correctly handles fee-on-transfer tokens.
contract FeeOnTransferERC20 is TestERC20 {
    uint256 public feeBps; // fee in basis points (100 = 1%)
    address public feeRecipient;

    constructor(uint256 _feeBps, address _feeRecipient) {
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual override {
        uint256 fee = (amount * feeBps) / 10_000;
        uint256 netAmount = amount - fee;
        super._transfer(from, to, netAmount);
        if (fee > 0) {
            super._transfer(from, feeRecipient, fee);
        }
    }
}
