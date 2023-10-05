// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { L1ERC20Gateway, IERC20 } from "./L1ERC20Gateway.sol";
import { IERC20Inbox } from "../L1ArbitrumMessenger.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Bridge } from "../../libraries/IERC20Bridge.sol";

/**
 * @title Layer 1 Gateway contract for bridging standard ERC20s in ERC20-based rollup
 * @notice This contract handles token deposits, holds the escrowed tokens on layer 1, and (ultimately) finalizes withdrawals.
 * @dev Any ERC20 that requires non-standard functionality should use a separate gateway.
 * Messages to layer 2 use the inbox's createRetryableTicket method.
 */
contract L1OrbitERC20Gateway is L1ERC20Gateway {
    using SafeERC20 for IERC20;

    function outboundTransferCustomRefund(
        address _l1Token,
        address _refundTo,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) public payable override returns (bytes memory res) {
        // fees are paid in native token, so there is no use for ether
        require(msg.value == 0, "NO_VALUE");

        // We don't allow bridging of native token to avoid having multiple representations of it 
        // on child chain. Native token can be bridged directly through inbox using depositERC20().
        require(_l1Token != _getNativeFeeToken(), "NOT_ALLOWED_TO_BRIDGE_FEE_TOKEN");

        return
            super.outboundTransferCustomRefund(
                _l1Token,
                _refundTo,
                _to,
                _amount,
                _maxGas,
                _gasPriceBid,
                _data
            );
    }

    function _parseUserEncodedData(bytes memory data)
        internal
        pure
        override
        returns (
            uint256 maxSubmissionCost,
            bytes memory callHookData,
            uint256 tokenTotalFeeAmount
        )
    {
        (maxSubmissionCost, callHookData, tokenTotalFeeAmount) = abi.decode(
            data,
            (uint256, bytes, uint256)
        );
    }

    function _initiateDeposit(
        address _refundTo,
        address _from,
        uint256, // _amount, this info is already contained in _data
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
        {
            // Transfer native token amount needed to pay for retryable fees to the inbox.
            // Fee tokens will be transferred from user who initiated the action - that's `_user` account in
            // case call was routed by router, or msg.sender in case gateway's entrypoint was called directly.
            address nativeFeeToken = _getNativeFeeToken();
            uint256 inboxNativeTokenBalance = IERC20(nativeFeeToken).balanceOf(_inbox);
            if (inboxNativeTokenBalance < _totalFeeAmount) {
                address transferFrom = isRouter(msg.sender) ? _user : msg.sender;
                IERC20(nativeFeeToken).safeTransferFrom(
                    transferFrom,
                    _inbox,
                    _totalFeeAmount - inboxNativeTokenBalance
                );
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
     * @notice get rollup's native token that's used to pay for fees
     */
    function _getNativeFeeToken() internal view returns (address) {
        address bridge = address(getBridge(inbox));
        return IERC20Bridge(bridge).nativeToken();
    }
}
