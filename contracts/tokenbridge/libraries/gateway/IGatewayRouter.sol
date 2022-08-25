// SPDX-License-Identifier: Apache-2.0

/*
 * Copyright 2020, Offchain Labs, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "arb-bridge-eth/contracts/libraries/ProxyUtil.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./TokenGateway.sol";
import "./GatewayMessageHandler.sol";

/**
 * @title Common interface for L1 and L2 Gateway Routers
 */
interface IGatewayRouter is ITokenGateway {
    struct PermitData {
        uint256 deadline;
        uint256 nonce;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function defaultGateway() external view returns (address gateway);

    event TransferRouted(
        address indexed token,
        address indexed _userFrom,
        address indexed _userTo,
        address gateway
    );

    event GatewaySet(address indexed l1Token, address indexed gateway);
    event DefaultGatewayUpdated(address newDefaultGateway);

    function getGateway(address _token) external view returns (address gateway);

    function outboundTransferWithEip2612Permit(
        address _token,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data,
        PermitData calldata _permitData
    ) external payable returns (bytes memory);

    function outboundTransferWithDaiPermit(
        address _token,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data,
        PermitData calldata _permitData
    ) external payable returns (bytes memory);
}
