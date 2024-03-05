// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L2ArbitrumGateway.t.sol";

import {L2WethGateway} from "contracts/tokenbridge/arbitrum/gateway/L2WethGateway.sol";
import {L2GatewayToken} from "contracts/tokenbridge/libraries/L2GatewayToken.sol";
import {aeWETH} from "contracts/tokenbridge/libraries/aeWETH.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract L2WethGatewayTest is L2ArbitrumGatewayTest {
    L2WethGateway public l2WethGateway;
    address public l2BeaconProxyFactory;

    address public l1Weth = makeAddr("l1Weth");
    address public l2Weth;

    function setUp() public virtual {
        l2WethGateway = new L2WethGateway();
        l2Gateway = L2ArbitrumGateway(address(l2WethGateway));

        ProxyAdmin pa = new ProxyAdmin();
        l2Weth = address(new TransparentUpgradeableProxy(address(new aeWETH()), address(pa), ""));

        L2WethGateway(l2WethGateway).initialize(l1Counterpart, router, l1Weth, l2Weth);
        aeWETH(payable(l2Weth)).initialize("WETH", "WETH", 18, address(l2WethGateway), l1Weth);
    }

    /* solhint-disable func-name-mixedcase */
    function test_calculateL2TokenAddress() public {
        assertEq(l2WethGateway.calculateL2TokenAddress(l1Weth), l2Weth, "Invalid weth address");
    }

    function test_calculateL2TokenAddress_NotWeth() public {
        address randomToken = makeAddr("randomToken");
        assertEq(
            l2WethGateway.calculateL2TokenAddress(randomToken), address(0), "Invalid weth address"
        );
    }

    function test_finalizeInboundTransfer() public override {
        /// deposit params
        bytes memory gatewayData = new bytes(0);
        bytes memory callHookData = new bytes(0);

        // fund gateway
        vm.deal(address(l2WethGateway), 100 ether);

        /// events
        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(l1Weth, sender, receiver, amount);

        /// finalize deposit
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2WethGateway.finalizeInboundTransfer(
            l1Weth, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        );

        /// check tokens have been minted to receiver;
        assertEq(aeWETH(payable(l2Weth)).balanceOf(receiver), amount, "Invalid receiver balance");
    }

    function test_finalizeInboundTransfer_WithCallHook() public override {
        /// deposit params
        bytes memory gatewayData = new bytes(0);
        bytes memory callHookData = new bytes(0x1);

        // fund gateway
        vm.deal(address(l2WethGateway), 100 ether);

        /// events
        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(l1Weth, sender, receiver, amount);

        /// finalize deposit
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2WethGateway.finalizeInboundTransfer(
            l1Weth, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        );

        /// check tokens have been minted to receiver;
        assertEq(aeWETH(payable(l2Weth)).balanceOf(receiver), amount, "Invalid receiver balance");
    }

    function test_finalizeInboundTransfer_ShouldHalt() public {
        /// deposit params
        bytes memory gatewayData = new bytes(0);
        bytes memory callHookData = new bytes(0);

        address notL1Weth = makeAddr("notL1Weth");

        // check that withdrawal is triggered occurs when deposit is halted
        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(notL1Weth, address(l2WethGateway), sender, 0, 0, amount);

        vm.deal(address(l2WethGateway), 100 ether);

        /// finalize deposit
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2WethGateway.finalizeInboundTransfer(
            notL1Weth, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        );
    }

    function test_initialize() public {
        L2WethGateway gateway = new L2WethGateway();
        L2WethGateway(gateway).initialize(l1Counterpart, router, l1Weth, l2Weth);

        assertEq(gateway.counterpartGateway(), l1Counterpart, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.l1Weth(), l1Weth, "Invalid l1Weth");
        assertEq(gateway.l2Weth(), l2Weth, "Invalid l2Weth");
    }

    function test_initialize_revert_InvalidL1Weth() public {
        L2WethGateway gateway = new L2WethGateway();
        vm.expectRevert("INVALID_L1WETH");
        address invalidL1Weth = address(0);
        L2WethGateway(gateway).initialize(l1Counterpart, router, invalidL1Weth, l2Weth);
    }

    function test_initialize_revert_InvalidL2Weth() public {
        L2WethGateway gateway = new L2WethGateway();
        vm.expectRevert("INVALID_L2WETH");
        address invalidL2Weth = address(0);
        L2WethGateway(gateway).initialize(l1Counterpart, router, l1Weth, invalidL2Weth);
    }

    function test_outboundTransfer() public override {
        // mint token to user
        deal(address(this), 100 ether);
        aeWETH(payable(l2Weth)).depositTo{value: 20 ether}(sender);

        // withdrawal params
        bytes memory data = new bytes(0);

        // events
        uint256 expectedId = 0;
        bytes memory expectedData =
            l2WethGateway.getOutboundCalldata(l1Weth, sender, receiver, amount, data);
        vm.expectEmit(true, true, true, true);
        emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1Weth, sender, receiver, expectedId, 0, amount);

        // withdraw
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(sender);
        l2WethGateway.outboundTransfer(l1Weth, receiver, amount, 0, 0, data);
    }

    function test_outboundTransfer_4Args() public override {
        // mint token to user
        deal(address(this), 100 ether);
        aeWETH(payable(l2Weth)).depositTo{value: 20 ether}(sender);

        // withdrawal params
        bytes memory data = new bytes(0);

        // events
        uint256 expectedId = 0;
        bytes memory expectedData =
            l2WethGateway.getOutboundCalldata(l1Weth, sender, receiver, amount, data);
        vm.expectEmit(true, true, true, true);
        emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1Weth, sender, receiver, expectedId, 0, amount);

        // withdraw
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(sender);
        l2WethGateway.outboundTransfer(l1Weth, receiver, amount, data);
    }

    function test_outboundTransfer_revert_NotExpectedL1Token() public override {
        // mock invalid L1 token ref
        address notL1Weth = makeAddr("notL1Weth");
        vm.mockCall(address(l2Weth), abi.encodeWithSignature("l1Address()"), abi.encode(notL1Weth));

        vm.expectRevert("NOT_EXPECTED_L1_TOKEN");
        l2WethGateway.outboundTransfer(l1Weth, address(101), 200, 0, 0, new bytes(0));
    }

    function test_receive() public {
        vm.deal(address(this), 5 ether);
        bool sent = payable(l2WethGateway).send(5 ether);

        assertTrue(sent, "Failed to send");
        assertEq(address(l2WethGateway).balance, 5 ether, "Invalid balance");
    }
}
