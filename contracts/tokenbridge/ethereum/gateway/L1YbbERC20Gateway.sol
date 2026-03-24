// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {L1ERC20Gateway} from "./L1ERC20Gateway.sol";
import {YbbGatewayEscrowHandlingLib} from "../../libraries/vault/YbbGatewayEscrowHandlingLib.sol";
import {AbsYbbGateway} from "./AbsYbbGateway.sol";
import {IMasterVaultFactory} from "../../libraries/vault/IMasterVaultFactory.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {GatewayMessageHandler} from "../../libraries/gateway/GatewayMessageHandler.sol";
import {ITokenGateway} from "../../libraries/gateway/ITokenGateway.sol";

/**
 * @title Layer 1 Gateway contract for bridging standard ERC20s with YBB enabled
 * @notice Escrows funds into MasterVaults for yield bearing bridging.
 */
contract L1YbbERC20Gateway is AbsYbbGateway, L1ERC20Gateway {
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
        override
    {
        YbbGatewayEscrowHandlingLib.handleInboundEscrowTransfer(masterVaultFactory, _l1Token, _dest, _amount);
    }

    function outboundEscrowTransfer(address _l1Token, address _from, uint256 _amount)
        internal
        override
        returns (uint256 amountReceived)
    {
        amountReceived = YbbGatewayEscrowHandlingLib.handleOutboundEscrowTransfer(masterVaultFactory, _l1Token, _from, _amount);
    }

    function getOutboundCalldata(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public view override returns (bytes memory outboundCalldata) {
        address vault = IMasterVaultFactory(masterVaultFactory).calculateVaultAddress(_token);

        bytes memory deployData = abi.encode(
            callStatic(_token, ERC20.name.selector),
            callStatic(_token, ERC20.symbol.selector),
            callStatic(vault, ERC20.decimals.selector)
        );

        outboundCalldata = abi.encodeWithSelector(
            ITokenGateway.finalizeInboundTransfer.selector,
            _token,
            _from,
            _to,
            _amount,
            GatewayMessageHandler.encodeToL2GatewayMsg(deployData, _data)
        );
    }
}
