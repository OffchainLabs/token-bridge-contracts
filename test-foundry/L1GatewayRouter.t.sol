// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { GatewayRouterTest } from "./GatewayRouter.t.sol";
import { L1GatewayRouter } from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";

contract L1GatewayRouterTest is GatewayRouterTest {
    L1GatewayRouter l1Router;

    address owner = makeAddr("owner");
    address defaultGateway = makeAddr("defaultGateway");
    address counterpartGateway = makeAddr("counterpartGateway");
    address inbox = makeAddr("inbox");

    function setUp() public {
        l1Router = new L1GatewayRouter();
    }

    function test_initialize() public {
        L1GatewayRouter router = new L1GatewayRouter();

        router.initialize(owner, defaultGateway, address(0), counterpartGateway, inbox);

        assertEq(router.router(), address(0), "Invalid router");
        assertEq(router.counterpartGateway(), counterpartGateway, "Invalid counterpartGateway");
        assertEq(router.defaultGateway(), defaultGateway, "Invalid defaultGateway");
        assertEq(router.owner(), owner, "Invalid owner");
        assertEq(router.whitelist(), address(0), "Invalid whitelist");
        assertEq(router.inbox(), inbox, "Invalid inbox");
    }

    function test_initialize_revert_AlreadyInit() public {
        L1GatewayRouter router = new L1GatewayRouter();
        router.initialize(owner, defaultGateway, address(0), counterpartGateway, inbox);
        vm.expectRevert("ALREADY_INIT");
        router.initialize(owner, defaultGateway, address(0), counterpartGateway, inbox);
    }

    function test_initialize_revert_InvalidCounterPart() public {
        L1GatewayRouter router = new L1GatewayRouter();
        address invalidCounterpart = address(0);
        vm.expectRevert("INVALID_COUNTERPART");
        router.initialize(owner, defaultGateway, address(0), invalidCounterpart, inbox);
    }
}
