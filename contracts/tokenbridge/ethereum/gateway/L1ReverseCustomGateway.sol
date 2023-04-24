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

import "./L1CustomGateway.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title   L1 Gateway for reverse "custom" bridging functionality
 * @notice  Handles some (but not all!) reverse custom Gateway needs.
 *          Use the reverse custom gateway instead of the normal custom
 *          gateway if you want total supply to be tracked on the L2
 *          rather than the L1.
 * @dev     The reverse custom gateway burns on the l2 and escrows on the l1
 *          which is the opposite of the way the normal custom gateway works
 *          This means that the total supply L2 isn't affected by briding, which
 *          is helpful for observers calculating the total supply especially if
 *          if minting is also occuring on L2
 */
contract L1ReverseCustomGateway is L1CustomGateway {
    function inboundEscrowTransfer(
        address _l1Address,
        address _dest,
        uint256 _amount
    ) internal virtual override {
        IArbToken(_l1Address).bridgeMint(_dest, _amount);
    }

    function outboundEscrowTransfer(
        address _l1Token,
        address _from,
        uint256 _amount
    ) internal override returns (uint256) {
        IArbToken(_l1Token).bridgeBurn(_from, _amount);
        // by default we assume that the amount we send to bridgeBurn is the amount burnt
        // this might not be the case for every token
        return _amount;
    }
}
