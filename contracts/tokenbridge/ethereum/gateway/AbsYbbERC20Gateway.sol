// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {AbsYbbGateway} from "./AbsYbbGateway.sol";
import {IMasterVaultFactory} from "../../libraries/vault/IMasterVaultFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITokenGateway} from "../../libraries/gateway/ITokenGateway.sol";
import {GatewayMessageHandler} from "../../libraries/gateway/GatewayMessageHandler.sol";

/// @notice Abstract contract inherited by L1OrbitYbbERC20Gateway and L1YbbERC20Gateway.
///         Provides shared logic for getOutboundCalldata.
abstract contract AbsYbbERC20Gateway is AbsYbbGateway {
    function getOutboundCalldata(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public virtual view returns (bytes memory outboundCalldata) {
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

    function callStatic(address targetContract, bytes4 targetFunction)
        internal
        virtual
        view
        returns (bytes memory);
}