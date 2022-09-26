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

/// @title  The L2 component of an token that has been reverse bridged
/// @notice Reverse bridged tokens are said to be native on the L2.
/// @dev    Minting done on L2, transfers from L2 to L1 do not burn tokens but instead escrow
///         them on the L2 gateway. The L1 token should mint and burn when interacting with the
///         gateway to ensure that the L2 supply is respected.
interface IReverseArbToken {
    /// @notice address of layer 1 token
    function l1Address() external view returns (address);
}