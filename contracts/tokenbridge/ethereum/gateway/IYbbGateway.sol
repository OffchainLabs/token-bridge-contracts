// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @notice Interface implemented by AbsYbbGateway (which is inherited by all YBB gateways).
interface IYbbGateway {
    /// @notice Same as IL1ArbitrumGateway.outboundTransferCustomRefund but supports an optional slippage tolerance parameter.
    /// @param  minReceivedOnL2 Minimum amount of tokens expected to be received on L2 after the transfer, used for slippage protection.
    function outboundTransferCustomRefundWithSlippageTolerance(
        address _l1Token,
        address _refundTo,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data,
        uint256 minReceivedOnL2
    ) external payable returns (bytes memory res);
}