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

import "./L2ArbitrumGateway.sol";

contract L2USDCGateway is L2ArbitrumGateway {
    address public l1USDC;
    address public l2USDC;

    function initialize(address _l1Counterpart, address _router, address _l1USDC, address _l2USDC)
        public
    {
        L2ArbitrumGateway._initialize(_l1Counterpart, _router);
        l1USDC = _l1USDC;
        l2USDC = _l2USDC;
    }

    /**
     * @notice Calculate the address used when bridging an ERC20 token
     * @dev the L1 and L2 address oracles may not always be in sync.
     * For example, a custom token may have been registered but not deploy or the contract self destructed.
     * @param l1ERC20 address of L1 token
     * @return L2 address of a bridged ERC20 token
     */
    function calculateL2TokenAddress(address l1ERC20) public view override returns (address) {
        if (l1ERC20 != l1USDC) {
            // invalid L1 usdc address
            return address(0);
        }
        return l2USDC;
    }

    /**
     * @notice internal utility function used to handle when no contract is deployed at expected address
     * @param l1ERC20 L1 address of ERC20
     */
    function handleNoContract(
        address l1ERC20,
        address, /* expectedL2Address */
        address _from,
        address, /* _to */
        uint256 _amount,
        bytes memory /* deployData */
    ) internal override returns (bool shouldHalt) {
        // it is assumed that the custom token is deployed in the L2 before deposits are made
        // trigger withdrawal
        triggerWithdrawal(l1ERC20, address(this), _from, _amount, "");
        return true;
    }
}
