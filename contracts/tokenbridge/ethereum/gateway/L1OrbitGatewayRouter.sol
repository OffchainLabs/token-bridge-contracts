// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { L1GatewayRouter } from "./L1GatewayRouter.sol";
import { IERC20Inbox } from "../L1ArbitrumMessenger.sol";

/**
 * @title Handles deposits from Ethereum into L2 in ERC20-based rollups where custom token is used to pay for fees. Tokens are routed to their appropriate L1 gateway.
 * @notice Router itself also conforms to the Gateway interface. Router also serves as an L1-L2 token address oracle.
 */
contract L1OrbitGatewayRouter is L1GatewayRouter {
    function setDefaultGateway(
        address newL1DefaultGateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        uint256 feeAmount
    ) external onlyOwner returns (uint256) {
        return
            _setDefaultGateway(
                newL1DefaultGateway,
                _maxGas,
                _gasPriceBid,
                _maxSubmissionCost,
                feeAmount
            );
    }

    function setGateway(
        address _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress,
        uint256 feeAmount
    ) public returns (uint256) {
        return
            _setGatewayWithCreditBack(
                _gateway,
                _maxGas,
                _gasPriceBid,
                _maxSubmissionCost,
                _creditBackAddress,
                feeAmount
            );
    }

    function setGateway(
        address _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        uint256 feeAmount
    ) external returns (uint256) {
        return
            setGateway(_gateway, _maxGas, _gasPriceBid, _maxSubmissionCost, msg.sender, feeAmount);
    }

    function setGateways(
        address[] memory _token,
        address[] memory _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        uint256 feeAmount
    ) external payable onlyOwner returns (uint256) {
        return
            _setGateways(
                _token,
                _gateway,
                _maxGas,
                _gasPriceBid,
                _maxSubmissionCost,
                msg.sender,
                feeAmount
            );
    }

    function _createRetryable(
        address _inbox,
        address _to,
        address _refundTo,
        address _user,
        uint256 _totalFeeAmount,
        uint256 _l2CallValue,
        uint256 _maxSubmissionCost,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes memory _data
    ) internal override returns (uint256) {
        return
            IERC20Inbox(_inbox).createRetryableTicket(
                _to,
                _l2CallValue,
                _maxSubmissionCost,
                _refundTo,
                _user,
                _maxGas,
                _gasPriceBid,
                _totalFeeAmount,
                _data
            );
    }

    /**
     * @notice Revert 'setGateway' entrypoint which doesn't have total amount of token fees as an argument.
     */
    function setGateway(
        address,
        uint256,
        uint256,
        uint256,
        address
    ) public payable override returns (uint256) {
        revert("NOT_SUPPORTED_IN_ORBIT");
    }

    /**
     * @notice Revert 'setDefaultGateway' entrypoint which doesn't have total amount of token fees as an argument.
     */
    function setDefaultGateway(
        address,
        uint256,
        uint256,
        uint256
    ) external payable override onlyOwner returns (uint256) {
        revert("NOT_SUPPORTED_IN_ORBIT");
    }

    /**
     * @notice Revert 'setGateway' entrypoint which doesn't have total amount of token fees as an argument.
     */
    function setGateway(
        address,
        uint256,
        uint256,
        uint256
    ) external payable override returns (uint256) {
        revert("NOT_SUPPORTED_IN_ORBIT");
    }

    /**
     * @notice Revert 'setGateways' entrypoint which doesn't have total amount of token fees as an argument.
     */
    function setGateways(
        address[] memory,
        address[] memory,
        uint256,
        uint256,
        uint256
    ) external payable override onlyOwner returns (uint256) {
        revert("NOT_SUPPORTED_IN_ORBIT");
    }
}
