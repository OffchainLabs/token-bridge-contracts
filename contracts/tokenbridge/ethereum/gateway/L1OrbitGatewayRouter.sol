// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { L1GatewayRouter } from "./L1GatewayRouter.sol";
import { IERC20Inbox } from "../L1ArbitrumMessenger.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Bridge } from "../../libraries/IERC20Bridge.sol";

/**
 * @title Handles deposits from L1 into L2 in ERC20-based rollups where custom token is used to pay for fees. Tokens are routed to their appropriate L1 gateway.
 * @notice Router itself also conforms to the Gateway interface. Router also serves as an L1-L2 token address oracle.
 */
contract L1OrbitGatewayRouter is L1GatewayRouter {
    using SafeERC20 for IERC20;

    /**
     * @notice Allows owner to register the default gateway.
     * @param newL1DefaultGateway default gateway address
     * @param _maxGas max gas for L2 retryable execution
     * @param _gasPriceBid gas price for L2 retryable ticket
     * @param _maxSubmissionCost base submission cost for L2 retryable ticket
     * @param _feeAmount total amount of fees in native token to cover for retryable ticket costs. This amount will be transferred from user to bridge.
     * @return Retryable ticket ID
     */
    function setDefaultGateway(
        address newL1DefaultGateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        uint256 _feeAmount
    ) external onlyOwner returns (uint256) {
        return
            _setDefaultGateway(
                newL1DefaultGateway,
                _maxGas,
                _gasPriceBid,
                _maxSubmissionCost,
                _feeAmount
            );
    }

    /**
     * @notice Allows L1 Token contract to trustlessly register its gateway.
     * @dev Other setGateway method allows excess eth recovery from _maxSubmissionCost and is recommended.
     * @param _gateway l1 gateway address
     * @param _maxGas max gas for L2 retryable execution
     * @param _gasPriceBid gas price for L2 retryable ticket
     * @param _maxSubmissionCost base submission cost for L2 retryable ticket
     * @param _feeAmount total amount of fees in native token to cover for retryable ticket costs. This amount will be transferred from user to bridge.
     * @return Retryable ticket ID
     */
    function setGateway(
        address _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        uint256 _feeAmount
    ) external returns (uint256) {
        return
            setGateway(_gateway, _maxGas, _gasPriceBid, _maxSubmissionCost, msg.sender, _feeAmount);
    }

    /**
     * @notice Allows L1 Token contract to trustlessly register its gateway.
     * @dev Other setGateway method allows excess eth recovery from _maxSubmissionCost and is recommended.
     * @param _gateway l1 gateway address
     * @param _maxGas max gas for L2 retryable execution
     * @param _gasPriceBid gas price for L2 retryable ticket
     * @param _maxSubmissionCost base submission cost  L2 retryable tick3et
     * @param _creditBackAddress address for crediting back overpayment of _maxSubmissionCost
     * @param _feeAmount total amount of fees in native token to cover for retryable ticket costs. This amount will be transferred from user to bridge.
     * @return Retryable ticket ID
     */
    function setGateway(
        address _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress,
        uint256 _feeAmount
    ) public returns (uint256) {
        return
            _setGatewayWithCreditBack(
                _gateway,
                _maxGas,
                _gasPriceBid,
                _maxSubmissionCost,
                _creditBackAddress,
                _feeAmount
            );
    }

    /**
     * @notice Allows owner to register gateways for specific tokens.
     * @param _token list of L1 token addresses
     * @param _gateway list of L1 gateway addresses
     * @param _maxGas max gas for L2 retryable execution
     * @param _gasPriceBid gas price for L2 retryable ticket
     * @param _maxSubmissionCost base submission cost for L2 retryable ticket
     * @param _feeAmount total amount of fees in native token to cover for retryable ticket costs. This amount will be transferred from user to bridge.
     * @return Retryable ticket ID
     */
    function setGateways(
        address[] memory _token,
        address[] memory _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        uint256 _feeAmount
    ) external onlyOwner returns (uint256) {
        return
            _setGateways(
                _token,
                _gateway,
                _maxGas,
                _gasPriceBid,
                _maxSubmissionCost,
                msg.sender,
                _feeAmount
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
        {
            // Transfer native token amount needed to pay for retryable fees to the inbox.
            // Fee tokens will be transferred from msg.sender
            address nativeFeeToken = IERC20Bridge(address(getBridge(_inbox))).nativeToken();
            uint256 inboxNativeTokenBalance = IERC20(nativeFeeToken).balanceOf(_inbox);
            if (inboxNativeTokenBalance < _totalFeeAmount) {
                uint256 diff = _totalFeeAmount - inboxNativeTokenBalance;
                IERC20(nativeFeeToken).safeTransferFrom(msg.sender, _inbox, diff);
            }
        }

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
