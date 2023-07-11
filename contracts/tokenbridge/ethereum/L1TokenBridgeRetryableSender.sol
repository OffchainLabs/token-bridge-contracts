// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

/**
 * @title Token Bridge Retryable Ticket Sender
 * @notice This contract is intended to simply send out retryable ticket to deploy L2 side of the token bridge.
 *         Ticket data is prepared by L1AtomicTokenBridgeCreator. Retryable ticket issuance is done separately
 *         from L1 creator in order to have different senders for deployment of L2 factory vs. deployment of
 *         rest of L2 contracts. Having same sender can lead to edge cases where retryables are executed out
 *         order - that would prevent us from having canonical set of L2 addresses.
 *
 */
contract L1TokenBridgeRetryableSender {
    function sendRetryable(
        address inbox,
        address target,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable {
        IInbox(inbox).createRetryableTicket{value: msg.value}(
            target, 0, maxSubmissionCost, excessFeeRefundAddress, callValueRefundAddress, maxGas, gasPriceBid, data
        );
    }
}
