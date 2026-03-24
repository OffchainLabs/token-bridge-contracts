// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {L1OrbitERC20Gateway} from "./L1OrbitERC20Gateway.sol";
import {L1ERC20Gateway} from "./L1ERC20Gateway.sol";
import {L1ArbitrumGateway} from "./L1ArbitrumGateway.sol";
import {AbsYbbERC20Gateway} from "./AbsYbbERC20Gateway.sol";
import {AbsYbbGateway} from "./AbsYbbGateway.sol";
import {IMasterVaultFactory} from "../../libraries/vault/IMasterVaultFactory.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {GatewayMessageHandler} from "../../libraries/gateway/GatewayMessageHandler.sol";
import {ITokenGateway} from "../../libraries/gateway/ITokenGateway.sol";

/**
 * @title Layer 1 Gateway contract for bridging standard ERC20s with YBB enabled in ERC20-based rollup
 * @notice Escrows funds into MasterVaults for yield bearing bridging.
 */
contract L1OrbitYbbERC20Gateway is AbsYbbERC20Gateway, L1OrbitERC20Gateway {
    function initialize(
        address _l2Counterpart,
        address _router,
        address _inbox,
        bytes32 _cloneableProxyHash,
        address _l2BeaconProxyFactory,
        address _masterVaultFactory
    ) public {
        L1ERC20Gateway.initialize(
            _l2Counterpart, _router, _inbox, _cloneableProxyHash, _l2BeaconProxyFactory
        );
        AbsYbbGateway._initialize(_masterVaultFactory);
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

    function getOutboundCalldata(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public view override(AbsYbbERC20Gateway, L1ERC20Gateway) returns (bytes memory outboundCalldata) {
        return AbsYbbERC20Gateway.getOutboundCalldata(_token, _from, _to, _amount, _data);   
    }

    function callStatic(address targetContract, bytes4 targetFunction)
        internal
        view
        override(AbsYbbERC20Gateway, L1ERC20Gateway)
        returns (bytes memory)
    {
        return L1ERC20Gateway.callStatic(targetContract, targetFunction);
    }
}
