// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {GatewayRouterTest} from "./GatewayRouter.t.sol";
import {L2GatewayRouter} from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import {L2ERC20Gateway} from "contracts/tokenbridge/arbitrum/gateway/L2ERC20Gateway.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";

contract L2GatewayRouterTest is GatewayRouterTest {
    L2GatewayRouter public l2Router;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public counterpartGateway = makeAddr("counterpartGateway");
    address public inbox;

    function setUp() public virtual {
        inbox = makeAddr("Inbox");
        defaultGateway = address(new L2ERC20Gateway());

        router = new L2GatewayRouter();
        l2Router = L2GatewayRouter(address(router));
        l2Router.initialize(counterpartGateway, defaultGateway);

        // maxSubmissionCost = 50000;
        // retryableCost = maxSubmissionCost + maxGas * gasPriceBid;

        // vm.deal(owner, 100 ether);
        // vm.deal(user, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public {
        L2GatewayRouter router = new L2GatewayRouter();

        router.initialize(counterpartGateway, defaultGateway);

        assertEq(router.router(), address(0), "Invalid router");
        assertEq(router.counterpartGateway(), counterpartGateway, "Invalid counterpartGateway");
        assertEq(router.defaultGateway(), defaultGateway, "Invalid defaultGateway");
    }

    function test_setGateway() public virtual {
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("l1Token");
        address[] memory gateways = new address[](1);
        gateways[0] = makeAddr("gateway");

        vm.prank(AddressAliasHelper.applyL1ToL2Alias(counterpartGateway));
        l2Router.setGateway(tokens, gateways);
    }
}
