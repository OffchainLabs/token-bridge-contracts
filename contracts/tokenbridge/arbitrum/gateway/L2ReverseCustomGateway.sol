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

import "./L2CustomGateway.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   L2 Gateway for reverse "custom" bridging functionality
 * @notice  Handles some (but not all!) reverse custom Gateway needs.
 *          Use the reverse custom gateway instead of the normal custom
 *          gateway if you want total supply to be tracked on the L2
 *          rather than the L1.
 * @dev     The reverse custom gateway burns on the l2 and escrows on the l1
 *          which is the opposite of the way the normal custom gateway works
 *          This means that the total supply L2 isn't affected by briding, which
 *          is helpful for obeservers calculating the total supply especially if
 *          if minting is also occuring on L2
 */
contract L2ReverseCustomGateway is L2CustomGateway {
    using SafeERC20 for IERC20;

    function inboundEscrowTransfer(
        address _l2Token,
        address _dest,
        uint256 _amount
    ) internal virtual override {
        IERC20(_l2Token).safeTransfer(_dest, _amount);
    }

    function outboundEscrowTransfer(
        address _l2Token,
        address _from,
        uint256 _amount
    ) internal override returns (uint256) {
        uint256 prevBalance = IERC20(_l2Token).balanceOf(address(this));
        // as in the normal custom gateway, in the reverse custom gateway we check
        // for the balances of tokens to ensure that inflationary / deflationary changes in the amount
        // are taken into account we ignore the return value since we actually query the token before
        // and after to calculate the amount of tokens that were transferred
        IERC20(_l2Token).safeTransferFrom(_from, address(this), _amount);
        uint256 postBalance = IERC20(_l2Token).balanceOf(address(this));
        return postBalance - prevBalance;
    }
}
