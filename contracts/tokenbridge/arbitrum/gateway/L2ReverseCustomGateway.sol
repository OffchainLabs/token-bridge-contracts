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

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./L2CustomGateway.sol";

// CHRIS: TODO: docs
contract L2ReverseCustomGateway is L2CustomGateway {
    using SafeERC20 for IERC20;

    // TODO: address oracle validation?

    function inboundEscrowTransfer(address l2Token, address _dest, uint256 _amount) internal override {
        IERC20(l2Token).safeTransfer(_dest, _amount);
    }

    function outboundEscrowTransfer(address l2Token, address _from, uint256 _amount)
        internal
        override
        returns (uint256 amountReceived)
    {
        uint256 prevBalance = IERC20(l2Token).balanceOf(address(this));

        IERC20(l2Token).safeTransferFrom(_from, address(this), _amount);

        uint256 postBalance = IERC20(l2Token).balanceOf(address(this));
        return SafeMath.sub(postBalance, prevBalance);
    }
}
