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

pragma solidity ^0.8.4;

import "./L2ArbitrumGateway.sol";

contract L2USDCCustomGateway is L2ArbitrumGateway {
    address public l1USDC;
    address public l2USDC;
    bool public withdrawalsPaused;

    event WithdrawalsPaused();

    error L2USDCCustomGateway_WithdrawalsAlreadyPaused();
    error L2USDCCustomGateway_WithdrawalsPaused();
    error L2USDCCustomGateway_InvalidL1USDC();
    error L2USDCCustomGateway_InvalidL2USDC();

    function initialize(address _l1Counterpart, address _router, address _l1USDC, address _l2USDC)
        public
    {
        if (_l1USDC == address(0)) {
            revert L2USDCCustomGateway_InvalidL1USDC();
        }
        if (_l2USDC == address(0)) {
            revert L2USDCCustomGateway_InvalidL2USDC();
        }
        L2ArbitrumGateway._initialize(_l1Counterpart, _router);
        l1USDC = _l1USDC;
        l2USDC = _l2USDC;
    }

    function pauseWithdrawals() external onlyCounterpartGateway {
        if (withdrawalsPaused) {
            revert L2USDCCustomGateway_WithdrawalsAlreadyPaused();
        }
        withdrawalsPaused = true;

        emit WithdrawalsPaused();
    }

    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint256, /* _maxGas */
        uint256, /* _gasPriceBid */
        bytes calldata _data
    ) public payable override returns (bytes memory res) {
        if (withdrawalsPaused) {
            revert L2USDCCustomGateway_WithdrawalsPaused();
        }
        return super.outboundTransfer(_l1Token, _to, _amount, 0, 0, _data);
    }

    function calculateL2TokenAddress(address l1ERC20) public view override returns (address) {
        if (l1ERC20 != l1USDC) {
            // invalid L1 usdc address
            return address(0);
        }
        return l2USDC;
    }

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
