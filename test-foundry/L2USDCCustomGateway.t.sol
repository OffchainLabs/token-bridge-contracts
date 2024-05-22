// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L2ArbitrumGateway.t.sol";

import {L2USDCCustomGateway} from "contracts/tokenbridge/arbitrum/gateway/L2USDCCustomGateway.sol";
import {L1USDCCustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1USDCCustomGateway.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";
import {L2GatewayToken} from "contracts/tokenbridge/libraries/L2GatewayToken.sol";

contract L2USDCCustomGatewayTest is L2ArbitrumGatewayTest {
    L2USDCCustomGateway public l2USDCGateway;
    address public l2BeaconProxyFactory;

    address public l1USDC = makeAddr("l1USDC");
    address public l2USDC;

    function setUp() public virtual {
        l2USDCGateway = new L2USDCCustomGateway();
        l2Gateway = L2ArbitrumGateway(address(l2USDCGateway));

        l2USDC = address(new L2USDC(address(l2USDCGateway), l1USDC));
        l2USDCGateway.initialize(l1Counterpart, router, l1USDC, l2USDC);
    }

    /* solhint-disable func-name-mixedcase */

    function test_calculateL2TokenAddress() public {
        assertEq(l2USDCGateway.calculateL2TokenAddress(l1USDC), l2USDC, "Invalid address");
    }

    function test_calculateL2TokenAddress_NotUSDC() public {
        address randomToken = makeAddr("randomToken");
        assertEq(l2USDCGateway.calculateL2TokenAddress(randomToken), address(0), "Invalid address");
    }

    function test_finalizeInboundTransfer() public override {
        vm.deal(address(l2USDCGateway), 100 ether);

        /// events
        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(l1USDC, sender, receiver, amount);

        /// finalize deposit
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2USDCGateway.finalizeInboundTransfer(
            l1USDC, sender, receiver, amount, abi.encode(new bytes(0), new bytes(0))
        );

        /// check tokens have been minted to receiver
        assertEq(ERC20(l2USDC).balanceOf(receiver), amount, "Invalid receiver balance");
    }

    function test_finalizeInboundTransfer_WithCallHook() public override {
        vm.deal(address(l2USDCGateway), 100 ether);

        /// events
        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(l1USDC, sender, receiver, amount);

        /// finalize deposit
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2USDCGateway.finalizeInboundTransfer(
            l1USDC, sender, receiver, amount, abi.encode(new bytes(0), new bytes(0x1))
        );

        /// check tokens have been minted to receiver
        assertEq(ERC20(l2USDC).balanceOf(receiver), amount, "Invalid receiver balance");
    }

    function test_finalizeInboundTransfer_ShouldHalt() public {
        address notl1USDC = makeAddr("notl1USDC");

        // check that withdrawal is triggered occurs when deposit is halted
        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(notl1USDC, address(l2USDCGateway), sender, 0, 0, amount);

        vm.deal(address(l2USDCGateway), 100 ether);

        /// finalize deposit
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2USDCGateway.finalizeInboundTransfer(
            notl1USDC, sender, receiver, amount, abi.encode(new bytes(0), new bytes(0))
        );
    }

    function test_initialize() public {
        L2USDCCustomGateway gateway = new L2USDCCustomGateway();
        L2USDCCustomGateway(gateway).initialize(l1Counterpart, router, l1USDC, l2USDC);

        assertEq(gateway.counterpartGateway(), l1Counterpart, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.l1USDC(), l1USDC, "Invalid l1USDC");
        assertEq(gateway.l2USDC(), l2USDC, "Invalid l2USDC");
    }

    function test_initialize_revert_InvalidL1USDC() public {
        L2USDCCustomGateway gateway = new L2USDCCustomGateway();
        vm.expectRevert(
            abi.encodeWithSelector(L2USDCCustomGateway.L2USDCCustomGateway_InvalidL1USDC.selector)
        );
        L2USDCCustomGateway(gateway).initialize(l1Counterpart, router, address(0), l2USDC);
    }

    function test_initialize_revert_InvalidL2USDC() public {
        L2USDCCustomGateway gateway = new L2USDCCustomGateway();
        vm.expectRevert(
            abi.encodeWithSelector(L2USDCCustomGateway.L2USDCCustomGateway_InvalidL2USDC.selector)
        );
        L2USDCCustomGateway(gateway).initialize(l1Counterpart, router, l1USDC, address(0));
    }

    function test_initialize_revert_AlreadyInit() public {
        L2USDCCustomGateway gateway = new L2USDCCustomGateway();
        L2USDCCustomGateway(gateway).initialize(l1Counterpart, router, l1USDC, l2USDC);
        vm.expectRevert("ALREADY_INIT");
        L2USDCCustomGateway(gateway).initialize(l1Counterpart, router, l1USDC, l2USDC);
    }

    function test_outboundTransfer() public override {
        //     // mint token to user
        //     deal(address(this), 100 ether);
        //     aeWETH(payable(l2USDC)).depositTo{value: 20 ether}(sender);

        //     // withdrawal params
        //     bytes memory data = new bytes(0);

        //     // events
        //     uint256 expectedId = 0;
        //     bytes memory expectedData =
        //         L2USDCCustomGateway.getOutboundCalldata(l1USDC, sender, receiver, amount, data);
        //     vm.expectEmit(true, true, true, true);
        //     emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        //     vm.expectEmit(true, true, true, true);
        //     emit WithdrawalInitiated(l1USDC, sender, receiver, expectedId, 0, amount);

        //     // withdraw
        //     vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        //     vm.prank(sender);
        //     L2USDCCustomGateway.outboundTransfer(l1USDC, receiver, amount, 0, 0, data);
    }

    function test_outboundTransfer_4Args() public override {
        //     // mint token to user
        //     deal(address(this), 100 ether);
        //     aeWETH(payable(l2USDC)).depositTo{value: 20 ether}(sender);

        //     // withdrawal params
        //     bytes memory data = new bytes(0);

        //     // events
        //     uint256 expectedId = 0;
        //     bytes memory expectedData =
        //         L2USDCCustomGateway.getOutboundCalldata(l1USDC, sender, receiver, amount, data);
        //     vm.expectEmit(true, true, true, true);
        //     emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        //     vm.expectEmit(true, true, true, true);
        //     emit WithdrawalInitiated(l1USDC, sender, receiver, expectedId, 0, amount);

        //     // withdraw
        //     vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        //     vm.prank(sender);
        //     L2USDCCustomGateway.outboundTransfer(l1USDC, receiver, amount, data);
    }

    function test_outboundTransfer_revert_NotExpectedL1Token() public override {
        //     // mock invalid L1 token ref
        //     address notl1USDC = makeAddr("notl1USDC");
        //     vm.mockCall(address(l2USDC), abi.encodeWithSignature("l1Address()"), abi.encode(notl1USDC));

        //     vm.expectRevert("NOT_EXPECTED_L1_TOKEN");
        //     L2USDCCustomGateway.outboundTransfer(l1USDC, address(101), 200, 0, 0, new bytes(0));
        // }

        // function test_receive() public {
        //     vm.deal(address(this), 5 ether);
        //     bool sent = payable(L2USDCCustomGateway).send(5 ether);

        //     assertTrue(sent, "Failed to send");
        //     assertEq(address(L2USDCCustomGateway).balance, 5 ether, "Invalid balance");
    }
}

contract L2USDC is L2GatewayToken {
    constructor(address l2USDCGateway, address l1USDC) {
        L2GatewayToken._initialize("L2 USDC", "USDC", 18, l2USDCGateway, l1USDC);
    }
}
