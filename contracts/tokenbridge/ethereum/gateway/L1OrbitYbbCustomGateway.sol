// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {L1OrbitCustomGateway} from "./L1OrbitCustomGateway.sol";
import {L1CustomGateway} from "./L1CustomGateway.sol";
import {L1ArbitrumGateway} from "./L1ArbitrumGateway.sol";
import {AbsYbbGateway} from "./AbsYbbGateway.sol";

/**
 * @title Layer 1 Gateway contract for bridging Custom ERC20s with YBB enabled in ERC20-based rollup
 * @notice Escrows funds into MasterVaults for yield bearing bridging.
 */
contract L1OrbitYbbCustomGateway is L1OrbitCustomGateway, AbsYbbGateway {
    function initialize(
        address _l1Counterpart,
        address _l1Router,
        address _inbox,
        address _owner,
        address _masterVaultFactory
    ) public virtual {
        L1CustomGateway.initialize(_l1Counterpart, _l1Router, _inbox, _owner);
        __AbsYbbGateway_init(_masterVaultFactory);
    }

    function inboundEscrowTransfer(address _l1Token, address _dest, uint256 _amount)
        internal
        override(AbsYbbGateway, L1ArbitrumGateway)
    {
        AbsYbbGateway.inboundEscrowTransfer(_l1Token, _dest, _amount);
    }

    function outboundEscrowTransfer(address _l1Token, address _from, uint256 _amount)
        internal
        override(AbsYbbGateway, L1ArbitrumGateway)
        returns (uint256 amountReceived)
    {
        return AbsYbbGateway.outboundEscrowTransfer(_l1Token, _from, _amount);
    }

    function _outboundTransferCustomRefund(
        address _l1Token,
        address _refundTo,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) internal override(AbsYbbGateway, L1ArbitrumGateway) returns (bytes memory res, uint256 amountOnL2) {
        return L1ArbitrumGateway._outboundTransferCustomRefund(
            _l1Token,
            _refundTo,
            _to,
            _amount,
            _maxGas,
            _gasPriceBid,
            _data
        );
    }

    // advertise the YBB slippage-tolerance entrypoint (ERC-165)
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(L1ArbitrumGateway)
        returns (bool)
    {
        return interfaceId == this.outboundTransferCustomRefundWithSlippageTolerance.selector
            || super.supportsInterface(interfaceId);
    }
}
