// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {L2AtomicTokenBridgeFactory, L2RuntimeCode} from "../arbitrum/L2AtomicTokenBridgeFactory.sol";

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
    error L1TokenBridgeRetryableSender_RefundFailed();

    /**
     * @notice Creates retryable which deploys L2 side of the token bridge.
     * @dev Function will build retryable data, calculate submission cost and retryable value, create retryable
     *      and then refund the remaining funds to original delpoyer.
     */
    function sendRetryable(
        RetryableParams calldata retryableParams,
        L2TemplateAddresses calldata l2,
        L1Addresses calldata l1,
        address l2StandardGatewayAddress,
        address rollupOwner,
        address deployer
    ) external payable {
        bytes memory data = abi.encodeCall(
            L2AtomicTokenBridgeFactory.deployL2Contracts,
            (
                L2RuntimeCode(
                    l2.routerTemplate.code,
                    l2.standardGatewayTemplate.code,
                    l2.customGatewayTemplate.code,
                    l2.wethGatewayTemplate.code,
                    l2.wethTemplate.code
                    ),
                l1.router,
                l1.standardGateway,
                l1.customGateway,
                l1.wethGateway,
                l1.weth,
                l2StandardGatewayAddress,
                rollupOwner
            )
        );

        uint256 maxSubmissionCost = IInbox(retryableParams.inbox).calculateRetryableSubmissionFee(data.length, 0);
        uint256 retryableValue = maxSubmissionCost + retryableParams.maxGas * retryableParams.gasPriceBid;
        _createRetryable(retryableParams, maxSubmissionCost, retryableValue, data);

        // refund excess value to the deployer
        uint256 refund = msg.value - retryableValue;
        (bool success,) = deployer.call{value: refund}("");
        if (!success) revert L1TokenBridgeRetryableSender_RefundFailed();
    }

    function _createRetryable(
        RetryableParams calldata retryableParams,
        uint256 maxSubmissionCost,
        uint256 value,
        bytes memory data
    ) internal {
        IInbox(retryableParams.inbox).createRetryableTicket{value: value}(
            retryableParams.target,
            0,
            maxSubmissionCost,
            retryableParams.excessFeeRefundAddress,
            retryableParams.callValueRefundAddress,
            retryableParams.maxGas,
            retryableParams.gasPriceBid,
            data
        );
    }
}

/**
 * retryableParams needed to send retryable ticket
 */
struct RetryableParams {
    address inbox;
    address target;
    address excessFeeRefundAddress;
    address callValueRefundAddress;
    uint256 maxGas;
    uint256 gasPriceBid;
}

/**
 * Addresses of L2 templates deployed on L1
 */
struct L2TemplateAddresses {
    address routerTemplate;
    address standardGatewayTemplate;
    address customGatewayTemplate;
    address wethGatewayTemplate;
    address wethTemplate;
}

/**
 * L1 side of token bridge addresses
 */
struct L1Addresses {
    address router;
    address standardGateway;
    address customGateway;
    address wethGateway;
    address weth;
}
