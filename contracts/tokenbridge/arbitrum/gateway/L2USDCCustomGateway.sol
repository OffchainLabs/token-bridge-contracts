// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {L2ArbitrumGateway} from "./L2ArbitrumGateway.sol";

/**
 * @title  Child chain custom gateway for USDC implementing Bridged USDC Standard.
 * @notice Reference to the Circle's Bridged USDC Standard:
 *         https://github.com/circlefin/stablecoin-evm/blob/master/doc/bridged_USDC_standard.md
 *
 * @dev    This contract can be used on new Orbit chains which want to provide USDC
 *         bridging solution and keep the possibility to upgrade to native USDC at
 *         some point later. This solution will NOT be used in existing Arbitrum chains.
 *
 *         Parent chain custom gateway to be used along this parent chain custom gateway is L1USDCCustomGateway.
 *         This custom gateway differs from standard gateway in the following ways:
 *         - it supports a single parent chain - child chain USDC token pair
 *         - withdrawals can be permanently paused by the counterpart gateway
 */
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

    /**
     * @notice Pause all withdrawals. This can only be called by the counterpart gateway.
     *         Pausing is permanent and can not be undone.
     */
    function pauseWithdrawals() external onlyCounterpartGateway {
        if (withdrawalsPaused) {
            revert L2USDCCustomGateway_WithdrawalsAlreadyPaused();
        }
        withdrawalsPaused = true;

        emit WithdrawalsPaused();
    }

    /**
     * @notice Entrypoint for withdrawing USDC, can be used only if withdrawals are not paused.
     */
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

    /**
     * @notice Only parent chain - child chain USDC token pair is supported
     */
    function calculateL2TokenAddress(address l1ERC20) public view override returns (address) {
        if (l1ERC20 != l1USDC) {
            // invalid L1 usdc address
            return address(0);
        }
        return l2USDC;
    }

    /**
     * @notice Withdraw back the USDC if child chain side is not set up properly
     */
    function handleNoContract(
        address l1ERC20,
        address, /* expectedL2Address */
        address _from,
        address, /* _to */
        uint256 _amount,
        bytes memory /* deployData */
    ) internal override returns (bool shouldHalt) {
        // it is assumed that the custom token is deployed to child chain before deposits are made
        triggerWithdrawal(l1ERC20, address(this), _from, _amount, "");
        return true;
    }
}
