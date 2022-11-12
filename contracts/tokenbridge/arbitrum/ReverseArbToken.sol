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

// solhint-disable-next-line compiler-version
pragma solidity >=0.6.9 <0.9.0;

import "./IArbToken.sol";

/// @title  Minimum expected interface for L2 token that interacts with the reverse L2 token bridge (this is the interface necessary
///         for a custom token that interacts with the reverse gateway, see TestArbCustomToken.sol for an example implementation).
/// @dev    The L2ArbitrumGateway expects objects of type IArbToken, which includes
///         bridgeMint/burn. However when the L2ReverseCustomGateway overrides the functions
///         that make use of bridgeMint/burn and replaces them with safeTransfer/from.
///         We inherit IArbToken so that we fulfil the interface L2ArbitrumGateway expects
///         but since we know that bridgeMint/burn won't/shouldn't be used we override these
///         functions to ensure that if they throw if called during development
abstract contract ReverseArbToken is IArbToken {
    function bridgeMint(address, uint256) public override {
        revert("BRIDGE_MINT_NOT_IMPLEMENTED");
    }

    function bridgeBurn(address, uint256) public override {
        revert("BRIDGE_BURN_NOT_IMPLEMENTED");
    }
}
