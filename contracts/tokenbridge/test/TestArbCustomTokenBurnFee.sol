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

import "./TestArbCustomToken.sol";

contract TestArbCustomTokenBurnFee is TestArbCustomToken {
    constructor(address _l2Gateway, address _l1Address)
        TestArbCustomToken(_l2Gateway, _l1Address)
    {}

    // this token transfer extra 1 wei from the sender as fee when it burn token
    // alternatively, it can also be a callback that pass execution to the user
    function _burn(address account, uint256 amount) internal override {
        super._burn(account, amount);
        _transfer(account, address(1), 1);
    }
}
