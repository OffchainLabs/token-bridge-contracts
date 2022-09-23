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

import "./L1CustomGateway.sol";

// CHRIS: TODO: docs
contract L1ReverseCustomGateway is L1CustomGateway {
    // TODO: is the validation currently done enough? do we need to check the reverse mapping?
    function inboundEscrowTransfer(address _l1Token, address _dest, uint256 _amount) internal override {
        IArbToken(_l1Token).bridgeMint(_dest, _amount);
    }
    

    function outboundEscrowTransfer(address _l1Token, address _from, uint256 _amount)
        internal
        override
        returns (uint256 amountReceived)
    {
        uint256 prevBalance = IERC20(_l1Token).balanceOf(_from);

        // in the custom gateway, we do the same behaviour as the superclass, but actually check
        // for the balances of tokens to ensure that inflationary / deflationary changes in the amount
        // are taken into account
        // we ignore the return value since we actually query the token before and after to calculate
        // the amount of tokens that were burnt

        // this method is virtual since different subclasses can handle escrow differently
        // user funds are escrowed on the gateway using this function
        // burns L2 tokens in order to release escrowed L1 tokens
        IArbToken(_l1Token).bridgeBurn(_from, _amount);
        // by default we assume that the amount we send to bridgeBurn is the amount burnt
        // this might not be the case for every token
        return _amount;

        uint256 postBalance = IERC20(_l1Token).balanceOf(_from);
        return SafeMath.sub(prevBalance, postBalance);
    }
}
