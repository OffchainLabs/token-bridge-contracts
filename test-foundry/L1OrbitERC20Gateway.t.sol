// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ERC20Gateway.t.sol";
import "contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20PresetMinterPauser} from
    "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {TestERC20} from "contracts/tokenbridge/test/TestERC20.sol";
import {ERC20InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";

contract L1OrbitERC20GatewayTest is L1ERC20GatewayTest {
    ERC20 public nativeToken;
    uint256 public nativeTokenTotalFee;

    function setUp() public override {
        inbox = address(new ERC20InboxMock());
        nativeToken = ERC20(address(new ERC20PresetMinterPauser("X", "Y")));
        ERC20PresetMinterPauser(address(nativeToken)).mint(user, 1_000_000 ether);
        ERC20InboxMock(inbox).setMockNativeToken(address(nativeToken));

        l1Gateway = new L1OrbitERC20Gateway();
        L1OrbitERC20Gateway(address(l1Gateway)).initialize(
            l2Gateway, router, inbox, cloneableProxyHash, l2BeaconProxyFactory
        );

        token = IERC20(address(new TestERC20()));
        maxSubmissionCost = 0;
        nativeTokenTotalFee = maxGas * gasPriceBid;

        // fund user and router
        vm.prank(user);
        TestERC20(address(token)).mint();
        vm.deal(router, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public override {
        L1ERC20Gateway gateway = new L1OrbitERC20Gateway();
        gateway.initialize(l2Gateway, router, inbox, cloneableProxyHash, l2BeaconProxyFactory);

        assertEq(gateway.counterpartGateway(), l2Gateway, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.inbox(), inbox, "Invalid inbox");
        assertEq(gateway.l2BeaconProxyFactory(), l2BeaconProxyFactory, "Invalid beacon");
        assertEq(gateway.whitelist(), address(0), "Invalid whitelist");
    }

    function test_outboundTransfer() public override {
        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        // retryable params
        uint256 depositAmount = 300;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

        // approve fees
        vm.prank(user);
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // expect events
        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(user, user);

        vm.expectEmit(true, true, true, true);
        emit ERC20InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            l1Gateway.getOutboundCalldata(address(token), user, user, 300, "")
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(token), user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);
        l1Gateway.outboundTransfer(
            address(token), user, depositAmount, maxGas, gasPriceBid, routerEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = token.balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore,
            depositAmount,
            "Wrong l1 gateway balance"
        );
    }

    function test_outboundTransfer_revert_NotAllowedToBridgeFeeToken() public {
        // trigger deposit
        vm.prank(router);
        vm.expectRevert("NOT_ALLOWED_TO_BRIDGE_FEE_TOKEN");
        l1Gateway.outboundTransfer(address(nativeToken), user, 100, maxGas, gasPriceBid, "");
    }

    function test_outboundTransferCustomRefund() public override {
        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        // retryable params
        uint256 depositAmount = 700;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // approve fees
        vm.prank(user);
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

        // expect events
        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(creditBackAddress, user);

        vm.expectEmit(true, true, true, true);
        emit ERC20InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            l1Gateway.getOutboundCalldata(address(token), user, user, 700, "")
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(token), user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);
        l1Gateway.outboundTransferCustomRefund(
            address(token),
            creditBackAddress,
            user,
            depositAmount,
            maxGas,
            gasPriceBid,
            routerEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = token.balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore,
            depositAmount,
            "Wrong l1 gateway balance"
        );
    }

    function test_outboundTransferCustomRefund_InboxPrefunded() public {
        // retryable params
        uint256 depositAmount = 700;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // pre-fund inbox
        address inbox = address(l1Gateway.inbox());
        vm.prank(user);
        nativeToken.transfer(inbox, nativeTokenTotalFee * 2);

        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 userNativeTokenBalanceBefore = nativeToken.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

        // expect events
        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(creditBackAddress, user);

        vm.expectEmit(true, true, true, true);
        emit ERC20InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            l1Gateway.getOutboundCalldata(address(token), user, user, 700, "")
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(token), user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);
        l1Gateway.outboundTransferCustomRefund(
            address(token),
            creditBackAddress,
            user,
            depositAmount,
            maxGas,
            gasPriceBid,
            routerEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong user balance");

        uint256 userNativeTokenBalanceAfter = nativeToken.balanceOf(user);
        assertEq(
            userNativeTokenBalanceAfter,
            userNativeTokenBalanceBefore,
            "Wrong user native token balance"
        );

        uint256 l1GatewayBalanceAfter = token.balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore,
            depositAmount,
            "Wrong l1 gateway balance"
        );
    }

    function test_outboundTransferCustomRefund_InboxPartiallyPrefunded() public {
        // retryable params
        uint256 depositAmount = 700;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // partially pre-fund inbox
        uint256 prefundAmount = nativeTokenTotalFee / 3;
        address inbox = address(l1Gateway.inbox());
        vm.prank(user);
        nativeToken.transfer(inbox, prefundAmount);

        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 userNativeTokenBalanceBefore = nativeToken.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        // approve fee token
        vm.prank(user);
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee - prefundAmount);

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

        // expect events
        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(creditBackAddress, user);

        vm.expectEmit(true, true, true, true);
        emit ERC20InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            l1Gateway.getOutboundCalldata(address(token), user, user, 700, "")
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(token), user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);
        l1Gateway.outboundTransferCustomRefund(
            address(token),
            creditBackAddress,
            user,
            depositAmount,
            maxGas,
            gasPriceBid,
            routerEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong user balance");

        uint256 userNativeTokenBalanceAfter = nativeToken.balanceOf(user);
        assertEq(
            userNativeTokenBalanceBefore - userNativeTokenBalanceAfter,
            nativeTokenTotalFee - prefundAmount,
            "Wrong user native token balance"
        );

        uint256 l1GatewayBalanceAfter = token.balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore,
            depositAmount,
            "Wrong l1 gateway balance"
        );
    }

    function test_outboundTransferCustomRefund_revert_NoValue() public {
        // trigger deposit
        vm.prank(router);
        vm.expectRevert("NO_VALUE");
        l1Gateway.outboundTransferCustomRefund{value: 1 ether}(
            address(token), creditBackAddress, user, 100, maxGas, gasPriceBid, ""
        );
    }

    function test_outboundTransferCustomRefund_revert_NotAllowedToBridgeFeeToken() public {
        // trigger deposit
        vm.prank(router);
        vm.expectRevert("NOT_ALLOWED_TO_BRIDGE_FEE_TOKEN");
        l1Gateway.outboundTransferCustomRefund(
            address(nativeToken), creditBackAddress, user, 100, maxGas, gasPriceBid, ""
        );
    }

    function test_outboundTransferCustomRefund_revert_Reentrancy() public override {
        // approve fees
        vm.prank(user);
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // approve token
        uint256 depositAmount = 3;
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

        // trigger re-entrancy
        MockReentrantERC20 mockReentrantERC20 = new MockReentrantERC20();
        vm.etch(address(token), address(mockReentrantERC20).code);

        vm.expectRevert("ReentrancyGuard: reentrant call");
        vm.prank(router);
        l1Gateway.outboundTransferCustomRefund(
            address(token),
            creditBackAddress,
            user,
            depositAmount,
            maxGas,
            gasPriceBid,
            buildRouterEncodedData("")
        );
    }

    ////
    // Helper functions
    ////
    function buildRouterEncodedData(bytes memory callHookData)
        internal
        view
        override
        returns (bytes memory)
    {
        bytes memory userEncodedData =
            abi.encode(maxSubmissionCost, callHookData, nativeTokenTotalFee);
        bytes memory routerEncodedData = abi.encode(user, userEncodedData);

        return routerEncodedData;
    }

    event ERC20InboxRetryableTicket(
        address from,
        address to,
        uint256 l2CallValue,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 tokenTotalFeeAmount,
        bytes data
    );
}
