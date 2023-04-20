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

pragma solidity ^0.8.0;

import "./L2GatewayToken.sol";

/**
 * @title A basic custom token contract that can be used with the custom gateway
 */
contract L2CustomGatewayToken is L2GatewayToken {
    /**
     * @notice initialize the token
     * @dev the L2 bridge assumes this does not fail or revert
     * @param name_ ERC20 token name
     * @param symbol_ ERC20 token symbol
     * @param decimals_ ERC20 decimals
     * @param l2Gateway_ L2 gateway this token communicates with
     * @param l1Counterpart_ L1 address of ERC20
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address l2Gateway_,
        address l1Counterpart_
    ) public virtual initializer {
        _initialize(name_, symbol_, decimals_, l2Gateway_, l1Counterpart_);
    }
}
