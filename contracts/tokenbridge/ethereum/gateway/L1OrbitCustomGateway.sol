// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { L1CustomGateway } from "./L1CustomGateway.sol";
import { IERC20Inbox } from "../L1ArbitrumMessenger.sol";

/**
 * @title Gateway for "custom" bridging functionality in an ERC20-based rollup.
 * @notice Adds new entrypoints that have `_feeAmount` as parameter, while entrypoints without that parameter are reverted.
 */
contract L1OrbitCustomGateway is L1CustomGateway {
    function registerTokenToL2(
        address _l2Address,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        uint256 _feeAmount
    ) external returns (uint256) {
        return
            registerTokenToL2(
                _l2Address,
                _maxGas,
                _gasPriceBid,
                _maxSubmissionCost,
                msg.sender,
                _feeAmount
            );
    }

    function registerTokenToL2(
        address _l2Address,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress,
        uint256 _feeAmount
    ) public returns (uint256) {
        return
            _registerTokenToL2(
                _l2Address,
                _maxGas,
                _gasPriceBid,
                _maxSubmissionCost,
                _creditBackAddress,
                _feeAmount
            );
    }

    /**
     * @notice Revert 'registerTokenToL2' entrypoint which doesn't have total amount of token fees as an argument.
     */
    function registerTokenToL2(
        address,
        uint256,
        uint256,
        uint256,
        address
    ) public payable override returns (uint256) {
        revert("NOT_SUPPORTED_IN_ORBIT");
    }

    /**
     * @notice Revert 'registerTokenToL2' entrypoint which doesn't have total amount of token fees as an argument.
     */
    function registerTokenToL2(
        address,
        uint256,
        uint256,
        uint256
    ) external payable override returns (uint256) {
        revert("NOT_SUPPORTED_IN_ORBIT");
    }

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
