// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ArbitrumExtendedGateway.t.sol";
import {L1USDCCustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1USDCCustomGateway.sol";

contract L1USDCCustomGatewayTest is L1ArbitrumExtendedGatewayTest {
    // gateway params
    address public owner = makeAddr("owner");

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

    function test_finalizeInboundTransfer() public override {
        // TODO
    }
}
