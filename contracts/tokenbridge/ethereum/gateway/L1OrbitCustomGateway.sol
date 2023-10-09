// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { L1CustomGateway } from "./L1CustomGateway.sol";
import { IERC20Inbox } from "../L1ArbitrumMessenger.sol";
import { IERC20Bridge } from "../../libraries/IERC20Bridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Gateway for "custom" bridging functionality in an ERC20-based rollup.
 * @notice Adds new entrypoints that have `_feeAmount` as parameter, while entrypoints without that parameter are reverted.
 */
contract L1OrbitCustomGateway is L1CustomGateway {
    using SafeERC20 for IERC20;

    /**
     * @notice Allows L1 Token contract to trustlessly register its custom L2 counterpart, in an ERC20-based rollup. Retryable costs are paid in native token.
     * @param _l2Address counterpart address of L1 token
     * @param _maxGas max gas for L2 retryable execution
     * @param _gasPriceBid gas price for L2 retryable ticket
     * @param _maxSubmissionCost base submission cost for L2 retryable ticket
     * @param _feeAmount total amount of fees in native token to cover for retryable ticket costs. This amount will be transferred from user to bridge.
     * @return Retryable ticket ID
     */
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

    /**
     * @notice Allows L1 Token contract to trustlessly register its custom L2 counterpart, in an ERC20-based rollup. Retryable costs are paid in native token.
     * @param _l2Address counterpart address of L1 token
     * @param _maxGas max gas for L2 retryable execution
     * @param _gasPriceBid gas price for L2 retryable ticket
     * @param _maxSubmissionCost base submission cost for L2 retryable ticket
     * @param _creditBackAddress address for crediting back overpayment of _maxSubmissionCost
     * @param _feeAmount total amount of fees in native token to cover for retryable ticket costs. This amount will be transferred from user to bridge.
     * @return Retryable ticket ID
     */
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
     * @notice Allows owner to force register a custom L1/L2 token pair.
     * @dev _l1Addresses[i] counterpart is assumed to be _l2Addresses[i]
     * @param _l1Addresses array of L1 addresses
     * @param _l2Addresses array of L2 addresses
     * @param _maxGas max gas for L2 retryable execution
     * @param _gasPriceBid gas price for L2 retryable ticket
     * @param _maxSubmissionCost base submission cost for L2 retryable ticket
     * @param _feeAmount total amount of fees in native token to cover for retryable ticket costs. This amount will be transferred from user to bridge.
     * @return Retryable ticket ID
     */
    function forceRegisterTokenToL2(
        address[] calldata _l1Addresses,
        address[] calldata _l2Addresses,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        uint256 _feeAmount
    ) external onlyOwner returns (uint256) {
        return
            _forceRegisterTokenToL2(
                _l1Addresses,
                _l2Addresses,
                _maxGas,
                _gasPriceBid,
                _maxSubmissionCost,
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

    /**
     * @notice Revert 'forceRegisterTokenToL2' entrypoint which doesn't have total amount of token fees as an argument.
     */
    function forceRegisterTokenToL2(
        address[] calldata,
        address[] calldata,
        uint256,
        uint256,
        uint256
    ) external payable override onlyOwner returns (uint256) {
        revert("NOT_SUPPORTED_IN_ORBIT");
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
            address nativeFeeToken = IERC20Bridge(address(getBridge(_inbox))).nativeToken();
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
}
