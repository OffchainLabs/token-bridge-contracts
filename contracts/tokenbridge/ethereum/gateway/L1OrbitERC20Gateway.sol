// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.11;

import "./L1ERC20Gateway.sol";
import { IERC20Inbox } from "../L1ArbitrumMessenger.sol";

/**
 * @title Layer 1 Gateway contract for bridging standard ERC20s in ERC20-based rollup
 * @notice This contract handles token deposits, holds the escrowed tokens on layer 1, and (ultimately) finalizes withdrawals.
 * @dev Any ERC20 that requires non-standard functionality should use a separate gateway.
 * Messages to layer 2 use the inbox's createRetryableTicket method.
 */
contract L1OrbitERC20Gateway is L1ERC20Gateway {
    function _parseUserEncodedData(
        bytes memory data
    )
        internal
        pure
        override
        returns (uint256 maxSubmissionCost, bytes memory callHookData, uint256 tokenTotalFeeAmount)
    {
        (maxSubmissionCost, callHookData, tokenTotalFeeAmount) = abi.decode(
            data,
            (uint256, bytes, uint256)
        );
    }

    function _initiateDeposit(
        address _refundTo,
        address _from,
        uint256,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        uint256 tokenTotalFeeAmount,
        bytes memory _data
    ) internal override returns (uint256) {
        return
            sendTxToL2CustomRefund(
                inbox,
                counterpartGateway,
                _refundTo,
                _from,
                tokenTotalFeeAmount,
                0,
                L2GasParams({
                    _maxSubmissionCost: _maxSubmissionCost,
                    _maxGas: _maxGas,
                    _gasPriceBid: _gasPriceBid
                }),
                _data
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
}
