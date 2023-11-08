// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {L2ERC20Gateway} from "contracts/tokenbridge/arbitrum/gateway/L2ERC20Gateway.sol";

contract L2ERC20GatewayTest is Test {
    address public l2Gateway;

    address public l2BeaconProxyFactory = makeAddr("l2BeaconProxyFactory");
    address public router = makeAddr("router");
    address public l1Counterpart = makeAddr("l1Counterpart");

    function setUp() public virtual {
        l2Gateway = address(new L2ERC20Gateway());
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public {
        L2ERC20Gateway gateway = new L2ERC20Gateway();
        L2ERC20Gateway(gateway).initialize(l1Counterpart, router, l2BeaconProxyFactory);

        assertEq(gateway.counterpartGateway(), l1Counterpart, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.beaconProxyFactory(), l2BeaconProxyFactory, "Invalid beacon");
    }

    function test_initialize_revert_InvalidBeacon() public {
        L2ERC20Gateway gateway = new L2ERC20Gateway();
        vm.expectRevert("INVALID_BEACON");
        L2ERC20Gateway(gateway).initialize(l1Counterpart, router, address(0));
    }

    function test_initialize_revert_BadRouter() public {
        L2ERC20Gateway gateway = new L2ERC20Gateway();
        vm.expectRevert("BAD_ROUTER");
        L2ERC20Gateway(gateway).initialize(l1Counterpart, address(0), l2BeaconProxyFactory);
    }

    function test_initialize_revert_InvalidCounterpart() public {
        L2ERC20Gateway gateway = new L2ERC20Gateway();
        vm.expectRevert("INVALID_COUNTERPART");
        L2ERC20Gateway(gateway).initialize(address(0), router, l2BeaconProxyFactory);
    }

    function test_initialize_revert_AlreadyInit() public {
        L2ERC20Gateway gateway = new L2ERC20Gateway();
        L2ERC20Gateway(gateway).initialize(l1Counterpart, router, l2BeaconProxyFactory);
        vm.expectRevert("ALREADY_INIT");
        L2ERC20Gateway(gateway).initialize(l1Counterpart, router, l2BeaconProxyFactory);
    }
}
