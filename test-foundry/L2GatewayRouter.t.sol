// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {GatewayRouterTest} from "./GatewayRouter.t.sol";
import {L2GatewayRouter} from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import {L2ERC20Gateway} from "contracts/tokenbridge/arbitrum/gateway/L2ERC20Gateway.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";
import {StandardArbERC20} from "contracts/tokenbridge/arbitrum/StandardArbERC20.sol";
import {BeaconProxyFactory} from "contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ArbSysMock} from "contracts/tokenbridge/test/ArbSysMock.sol";

contract L2GatewayRouterTest is GatewayRouterTest {
    L2GatewayRouter public l2Router;
    ArbSysMock public arbSysMock = new ArbSysMock();

    address public user = makeAddr("user");
    address public counterpartGateway = makeAddr("counterpartGateway");
    address public beaconProxyFactory;

    function setUp() public virtual {
        defaultGateway = address(new L2ERC20Gateway());

        // create beacon
        StandardArbERC20 standardArbERC20 = new StandardArbERC20();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(standardArbERC20));
        beaconProxyFactory = address(new BeaconProxyFactory());
        BeaconProxyFactory(beaconProxyFactory).initialize(address(beacon));

        router = new L2GatewayRouter();
        l2Router = L2GatewayRouter(address(router));
        l2Router.initialize(counterpartGateway, defaultGateway);

        L2ERC20Gateway(defaultGateway).initialize(
            counterpartGateway, address(l2Router), beaconProxyFactory
        );
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public {
        L2GatewayRouter router = new L2GatewayRouter();

        router.initialize(counterpartGateway, defaultGateway);

        assertEq(router.router(), address(0), "Invalid router");
        assertEq(router.counterpartGateway(), counterpartGateway, "Invalid counterpartGateway");
        assertEq(router.defaultGateway(), defaultGateway, "Invalid defaultGateway");
    }

    function test_outboundTransfer() public {
        address l1Token = makeAddr("l1Token");

        // create and init standard l2Token
        bytes32 salt = keccak256(abi.encode(l1Token));
        vm.startPrank(defaultGateway);
        address l2Token = BeaconProxyFactory(beaconProxyFactory).createProxy(salt);
        StandardArbERC20(l2Token).bridgeInit(
            l1Token,
            abi.encode(
                abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
            )
        );
        vm.stopPrank();

        // mint token to user
        deal(l2Token, user, 100 ether);

        // withdrawal params
        address to = makeAddr("to");
        uint256 amount = 2400;
        bytes memory data = new bytes(0);

        // event
        vm.expectEmit(true, true, true, true);
        emit TransferRouted(l1Token, user, to, defaultGateway);

        // withdraw
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(user);
        l2Router.outboundTransfer(l1Token, to, amount, data);
    }

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
