// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ArbitrumExtendedGateway.t.sol";
import {L1USDCCustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1USDCCustomGateway.sol";

contract L1USDCCustomGatewayTest is L1ArbitrumExtendedGatewayTest {
    // gateway params
    address public owner = makeAddr("gw-owner");

    address public L1_USDC = makeAddr("L1_USDC");
    address public L2_USDC = makeAddr("L2_USDC");

    function setUp() public virtual {
        inbox = address(new InboxMock());

        l1Gateway = new L1USDCCustomGateway();
        L1USDCCustomGateway(payable(address(l1Gateway))).initialize(
            l2Gateway, router, inbox, L1_USDC, L2_USDC, owner
        );

        maxSubmissionCost = 20;
        retryableCost = maxSubmissionCost + gasPriceBid * maxGas;

        vm.deal(router, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_calculateL2TokenAddress() public {
        assertEq(l1Gateway.calculateL2TokenAddress(L1_USDC), L2_USDC, "Invalid usdc address");
    }

    function test_calculateL2TokenAddress_NotUSDC() public {
        address randomToken = makeAddr("randomToken");
        assertEq(l1Gateway.calculateL2TokenAddress(randomToken), address(0), "Invalid usdc address");
    }

    function test_initialize() public {
        L1USDCCustomGateway gateway = new L1USDCCustomGateway();
        gateway.initialize(l2Gateway, router, inbox, L1_USDC, L2_USDC, owner);

        assertEq(gateway.counterpartGateway(), l2Gateway, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.inbox(), inbox, "Invalid inbox");
        assertEq(gateway.l1USDC(), L1_USDC, "Invalid L1_USDC");
        assertEq(gateway.l2USDC(), L2_USDC, "Invalid L2_USDC");
        assertEq(gateway.owner(), owner, "Invalid owner");
    }

    function test_finalizeInboundTransfer() public override {
        // TODO
    }
}
