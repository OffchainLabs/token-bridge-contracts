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


pragma solidity >=0.6.9 <0.9.0;

import "../../libraries/gateway/ICustomGateway.sol";

/// @title Custom Gateway interface
/// @notice Registration interface of the L1 custom gateway
interface IL1CustomGateway is ICustomGateway {
    /// @notice Registers this token on the gateway with its L2 counterpart
    /// @param _l2Address The address of the token on L2
    /// @param _maxGas The max gas to pay in the custom gateway L1->L2 message
    /// @param _gasPriceBid The L2 gas price to use in L1->L2 message
    /// @param _maxSubmissionCost The max submission cost to pay in the custom gateway L1->L2 message
    /// @param _creditBackAddress The address to credit on L2 with any unspent funds from the L1->L2 message
    function registerTokenToL2(
        address _l2Address,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) external payable returns (uint256);
}
