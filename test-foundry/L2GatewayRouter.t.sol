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
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public {
        L2GatewayRouter router = new L2GatewayRouter();

        router.initialize(counterpartGateway, defaultGateway);

        assertEq(router.router(), address(0), "Invalid router");
        assertEq(router.counterpartGateway(), counterpartGateway, "Invalid counterpartGateway");
        assertEq(router.defaultGateway(), defaultGateway, "Invalid defaultGateway");
    }

    function test_outboundTransfer() public {}

    function test_setDefaultGateway() public {
        address newDefaultGateway = makeAddr("newDefaultGateway");

        vm.expectEmit(true, true, true, true);
        emit DefaultGatewayUpdated(newDefaultGateway);

        vm.prank(AddressAliasHelper.applyL1ToL2Alias(counterpartGateway));
        l2Router.setDefaultGateway(newDefaultGateway);

        assertEq(l2Router.defaultGateway(), newDefaultGateway, "New default gateway not set");
    }

    function test_setDefaultGateway_revert_OnlyCounterpart() public {
        vm.expectRevert("ONLY_COUNTERPART_GATEWAY");
        l2Router.setDefaultGateway(address(2));
    }

    function test_setGateway() public {
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("l1Token");
        address[] memory gateways = new address[](1);
        gateways[0] = makeAddr("gateway");

        vm.expectEmit(true, true, true, true);
        emit GatewaySet(tokens[0], gateways[0]);

        vm.prank(AddressAliasHelper.applyL1ToL2Alias(counterpartGateway));
        l2Router.setGateway(tokens, gateways);

        assertEq(l2Router.l1TokenToGateway(tokens[0]), gateways[0], "Gateway[0] not set");
    }

    function test_setGateway_revert_OnlyCounterpart() public {
        vm.expectRevert("ONLY_COUNTERPART_GATEWAY");
        l2Router.setGateway(new address[](1), new address[](1));
    }

    function test_setGateway_revert_WrongLengths() public {
        vm.expectRevert();
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(counterpartGateway));
        l2Router.setGateway(new address[](1), new address[](2));
    }

    ////
    // Event declarations
    ////

    event TransferRouted(
        address indexed token, address indexed _userFrom, address indexed _userTo, address gateway
    );

    event GatewaySet(address indexed l1Token, address indexed gateway);
    event DefaultGatewayUpdated(address newDefaultGateway);
}
