// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L2ArbitrumGateway.t.sol";
import {L2WethGateway} from "contracts/tokenbridge/arbitrum/gateway/L2WethGateway.sol";
import {L2GatewayToken} from "contracts/tokenbridge/libraries/L2GatewayToken.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract L2WethGatewayTest is L2ArbitrumGatewayTest {
    L2WethGateway public l2WethGateway;
    address public l2BeaconProxyFactory;

    address public l1Weth = makeAddr("l1Weth");
    address public l2Weth = makeAddr("l2Weth");

    function setUp() public virtual {
        l2WethGateway = new L2WethGateway();
        l2Gateway = L2ArbitrumGateway(address(l2WethGateway));

        L2WethGateway(l2WethGateway).initialize(l1Counterpart, router, l1Weth, l2Weth);
    }

    /* solhint-disable func-name-mixedcase */
    function test_finalizeInboundTransfer() public override {
        // /// deposit params
        // bytes memory gatewayData = new bytes(0);
        // bytes memory callHookData = new bytes(0);

        // // register custom token
        // address l2CustomToken = _registerToken();

        // /// events
        // vm.expectEmit(true, true, true, true);
        // emit DepositFinalized(l1CustomToken, sender, receiver, amount);

        // /// finalize deposit
        // vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        // l2WethGateway.finalizeInboundTransfer(
        //     l1CustomToken, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        // );

        // /// check tokens have been minted to receiver;
        // assertEq(ERC20(l2CustomToken).balanceOf(receiver), amount, "Invalid receiver balance");
    }

    // function test_finalizeInboundTransfer_NoL2TokenFound() public {
    //     /// deposit params
    //     bytes memory gatewayData = new bytes(0);
    //     bytes memory callHookData = new bytes(0);

    //     // check that withdrawal is triggered occurs when deposit is halted
    //     bytes memory expectedData = l2WethGateway.getOutboundCalldata(
    //         l1CustomToken, address(l2WethGateway), sender, amount, new bytes(0)
    //     );
    //     vm.expectEmit(true, true, true, true);
    //     emit TxToL1(address(l2WethGateway), l1Counterpart, 0, expectedData);

    //     vm.expectEmit(true, true, true, true);
    //     emit WithdrawalInitiated(l1CustomToken, address(l2WethGateway), sender, 0, 0, amount);

    //     /// finalize deposit
    //     vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
    //     vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
    //     l2WethGateway.finalizeInboundTransfer(
    //         l1CustomToken, sender, receiver, amount, abi.encode(gatewayData, callHookData)
    //     );
    // }

    // function test_finalizeInboundTransfer_UnexpectedL1Address() public {
    //     /// deposit params
    //     bytes memory gatewayData = new bytes(0);
    //     bytes memory callHookData = new bytes(0);

    //     /// L2 token returns unexpected L1 address
    //     address l2CustomToken = _registerToken();
    //     address notOriginalL1Token = makeAddr("notOriginalL1Token");
    //     vm.mockCall(
    //         address(l2CustomToken),
    //         abi.encodeWithSignature("l1Address()"),
    //         abi.encode(notOriginalL1Token)
    //     );

    //     // check that withdrawal is triggered occurs when deposit is halted
    //     bytes memory expectedData = l2WethGateway.getOutboundCalldata(
    //         l1CustomToken, address(l2WethGateway), sender, amount, new bytes(0)
    //     );
    //     vm.expectEmit(true, true, true, true);
    //     emit TxToL1(address(l2WethGateway), l1Counterpart, 0, expectedData);

    //     vm.expectEmit(true, true, true, true);
    //     emit WithdrawalInitiated(l1CustomToken, address(l2WethGateway), sender, 0, 0, amount);

    //     /// finalize deposit
    //     vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
    //     vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
    //     l2WethGateway.finalizeInboundTransfer(
    //         l1CustomToken, sender, receiver, amount, abi.encode(gatewayData, callHookData)
    //     );
    // }

    // function test_finalizeInboundTransfer_NoL1AddressImplemented() public {
    //     /// deposit params
    //     bytes memory gatewayData = new bytes(0);
    //     bytes memory callHookData = new bytes(0);

    //     /// L2 token returns doesn't implement l1Address()
    //     address[] memory l1Tokens = new address[](1);
    //     l1Tokens[0] = l1CustomToken;

    //     address[] memory l2Tokens = new address[](1);
    //     l2Tokens[0] = address(new Empty());

    //     vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
    //     l2WethGateway.registerTokenFromL1(l1Tokens, l2Tokens);

    //     // check that withdrawal is triggered occurs
    //     bytes memory expectedData = l2WethGateway.getOutboundCalldata(
    //         l1CustomToken, address(l2WethGateway), sender, amount, new bytes(0)
    //     );
    //     vm.expectEmit(true, true, true, true);
    //     emit TxToL1(address(l2WethGateway), l1Counterpart, 0, expectedData);

    //     vm.expectEmit(true, true, true, true);
    //     emit WithdrawalInitiated(l1CustomToken, address(l2WethGateway), sender, 0, 0, amount);

    //     /// finalize deposit
    //     vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
    //     vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
    //     l2WethGateway.finalizeInboundTransfer(
    //         l1CustomToken, sender, receiver, amount, abi.encode(gatewayData, callHookData)
    //     );
    // }

    function test_finalizeInboundTransfer_WithCallHook() public override {
        // /// deposit params
        // bytes memory gatewayData = abi.encode(
        //     abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        // );
        // bytes memory callHookData = new bytes(0x1);

        // // register custom token
        // address l2CustomToken = _registerToken();

        // /// events
        // vm.expectEmit(true, true, true, true);
        // emit DepositFinalized(l1CustomToken, sender, receiver, amount);

        // /// finalize deposit
        // vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        // l2WethGateway.finalizeInboundTransfer(
        //     l1CustomToken, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        // );

        // /// check tokens have been minted to receiver;
        // assertEq(ERC20(l2CustomToken).balanceOf(receiver), amount, "Invalid receiver balance");
    }

    // function test_initialize() public {
    //     L2WethGateway gateway = new L2WethGateway();
    //     L2WethGateway(gateway).initialize(l1Counterpart, router);

    //     assertEq(gateway.counterpartGateway(), l1Counterpart, "Invalid counterpartGateway");
    //     assertEq(gateway.router(), router, "Invalid router");
    // }

    // function test_initialize_revert_BadRouter() public {
    //     L2WethGateway gateway = new L2WethGateway();
    //     vm.expectRevert("BAD_ROUTER");
    //     L2WethGateway(gateway).initialize(l1Counterpart, address(0));
    // }

    // function test_initialize_revert_InvalidCounterpart() public {
    //     L2WethGateway gateway = new L2WethGateway();
    //     vm.expectRevert("INVALID_COUNTERPART");
    //     L2WethGateway(gateway).initialize(address(0), router);
    // }

    // function test_initialize_revert_AlreadyInit() public {
    //     L2WethGateway gateway = new L2WethGateway();
    //     L2WethGateway(gateway).initialize(l1Counterpart, router);
    //     vm.expectRevert("ALREADY_INIT");
    //     L2WethGateway(gateway).initialize(l1Counterpart, router);
    // }

    function test_outboundTransfer() public override {
        // // create and init custom l2Token
        // address l2CustomToken = _registerToken();

        // // mint token to user
        // deal(l2CustomToken, sender, 100 ether);

        // // withdrawal params
        // bytes memory data = new bytes(0);

        // // events
        // uint256 expectedId = 0;
        // bytes memory expectedData =
        //     l2WethGateway.getOutboundCalldata(l1CustomToken, sender, receiver, amount, data);
        // vm.expectEmit(true, true, true, true);
        // emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        // vm.expectEmit(true, true, true, true);
        // emit WithdrawalInitiated(l1CustomToken, sender, receiver, expectedId, 0, amount);

        // // withdraw
        // vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        // vm.prank(sender);
        // l2WethGateway.outboundTransfer(l1CustomToken, receiver, amount, 0, 0, data);
    }

    function test_outboundTransfer_4Args() public override {
        // // create and init custom l2Token
        // address l2CustomToken = _registerToken();

        // // mint token to user
        // deal(l2CustomToken, sender, 100 ether);

        // // withdrawal params
        // bytes memory data = new bytes(0);

        // // events
        // uint256 expectedId = 0;
        // bytes memory expectedData =
        //     l2WethGateway.getOutboundCalldata(l1CustomToken, sender, receiver, amount, data);
        // vm.expectEmit(true, true, true, true);
        // emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        // vm.expectEmit(true, true, true, true);
        // emit WithdrawalInitiated(l1CustomToken, sender, receiver, expectedId, 0, amount);

        // // withdraw
        // vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        // vm.prank(sender);
        // l2WethGateway.outboundTransfer(l1CustomToken, receiver, amount, data);
    }

    function test_outboundTransfer_revert_NotExpectedL1Token() public override {
        // // create and init custom l2Token
        // address l2CustomToken = _registerToken();

        // // mock invalid L1 token ref
        // address notOriginalL1Token = makeAddr("notOriginalL1Token");
        // vm.mockCall(
        //     address(l2CustomToken),
        //     abi.encodeWithSignature("l1Address()"),
        //     abi.encode(notOriginalL1Token)
        // );

        // vm.expectRevert("NOT_EXPECTED_L1_TOKEN");
        // l2Gateway.outboundTransfer(l1CustomToken, address(101), 200, 0, 0, new bytes(0));
    }
}
