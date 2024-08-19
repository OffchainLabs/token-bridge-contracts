// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1USDCGateway.t.sol";
import {L1OrbitUSDCGateway} from "contracts/tokenbridge/ethereum/gateway/L1OrbitUSDCGateway.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";
import {ERC20PresetMinterPauser} from
    "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract L1OrbitUSDCGatewayTest is L1USDCGatewayTest {
    ERC20 public nativeToken;
    uint256 public nativeTokenTotalFee;

    function setUp() public virtual override {
        inbox = address(new ERC20InboxMock());
        InboxMock(inbox).setL2ToL1Sender(l2Gateway);

        nativeToken = ERC20(address(new ERC20PresetMinterPauser("X", "Y")));
        ERC20PresetMinterPauser(address(nativeToken)).mint(user, 1_000_000 ether);
        ERC20PresetMinterPauser(address(nativeToken)).mint(owner, 1_000_000 ether);
        ERC20InboxMock(inbox).setMockNativeToken(address(nativeToken));

        usdcGateway = new L1OrbitUSDCGateway();
        l1Gateway = IL1ArbitrumGateway(address(usdcGateway));

        L1OrbitUSDCGateway(address(l1Gateway)).initialize(
            l2Gateway, router, inbox, L1_USDC, L2_USDC, owner
        );

        maxSubmissionCost = 0;
        nativeTokenTotalFee = maxGas * gasPriceBid;

        // fund user and router
        vm.deal(router, 100 ether);
        vm.deal(owner, 100 ether);
    }

    function test_outboundTransfer() public override {
        uint256 depositAmount = 300;
        deal(L1_USDC, user, depositAmount);
        bytes memory routerEncodedData = buildRouterEncodedData("");

        // snapshot state before
        uint256 userNativeTokenBalanceBefore = nativeToken.balanceOf(user);
        uint256 userBalanceBefore = ERC20(L1_USDC).balanceOf(user);
        uint256 l1GatewayBalanceBefore = ERC20(L1_USDC).balanceOf(address(l1Gateway));

        // approve token
        vm.prank(user);
        ERC20(L1_USDC).approve(address(l1Gateway), depositAmount);

        // approve fees
        vm.prank(user);
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // event checkers
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
            l1Gateway.getOutboundCalldata(L1_USDC, user, user, 300, "")
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(L1_USDC, user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);

        bytes memory seqNum = l1Gateway.outboundTransfer(
            L1_USDC, user, depositAmount, maxGas, gasPriceBid, routerEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = ERC20(L1_USDC).balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = ERC20(L1_USDC).balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore,
            depositAmount,
            "Wrong l1 gateway balance"
        );

        uint256 userNativeTokenBalanceAfter = nativeToken.balanceOf(user);
        assertEq(
            userNativeTokenBalanceBefore - userNativeTokenBalanceAfter,
            nativeTokenTotalFee,
            "Wrong user native token balance"
        );

        assertEq(seqNum, abi.encode(0), "Invalid seqNum");
    }

    function test_outboundTransferCustomRefund() public override {
        uint256 depositAmount = 100;
        deal(L1_USDC, user, depositAmount);
        bytes memory routerEncodedData = buildRouterEncodedData("");

        // snapshot state before
        uint256 userNativeTokenBalanceBefore = nativeToken.balanceOf(user);
        uint256 userBalanceBefore = ERC20(L1_USDC).balanceOf(user);
        uint256 l1GatewayBalanceBefore = ERC20(L1_USDC).balanceOf(address(l1Gateway));

        // approve token
        vm.prank(user);
        ERC20(L1_USDC).approve(address(l1Gateway), depositAmount);

        // approve fees
        vm.prank(user);
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // event checkers
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
            l1Gateway.getOutboundCalldata(L1_USDC, user, user, 100, "")
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(L1_USDC, user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);

        bytes memory seqNum = l1Gateway.outboundTransferCustomRefund(
            L1_USDC, creditBackAddress, user, depositAmount, maxGas, gasPriceBid, routerEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = ERC20(L1_USDC).balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = ERC20(L1_USDC).balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore,
            depositAmount,
            "Wrong l1 gateway balance"
        );

        uint256 userNativeTokenBalanceAfter = nativeToken.balanceOf(user);
        assertEq(
            userNativeTokenBalanceBefore - userNativeTokenBalanceAfter,
            nativeTokenTotalFee,
            "Wrong user native token balance"
        );

        assertEq(seqNum, abi.encode(0), "Invalid seqNum");
    }

    function test_outboundTransferCustomRefund_InboxPrefunded() public {
        uint256 depositAmount = 100;
        deal(L1_USDC, user, depositAmount);
        bytes memory routerEncodedData = buildRouterEncodedData("");

        // pre-fund inbox
        address inbox = address(l1Gateway.inbox());
        vm.prank(user);
        nativeToken.transfer(inbox, nativeTokenTotalFee * 2);

        // snapshot state before
        uint256 userNativeTokenBalanceBefore = nativeToken.balanceOf(user);
        uint256 userBalanceBefore = ERC20(L1_USDC).balanceOf(user);
        uint256 l1GatewayBalanceBefore = ERC20(L1_USDC).balanceOf(address(l1Gateway));

        // approve token
        vm.prank(user);
        ERC20(L1_USDC).approve(address(l1Gateway), depositAmount);

        // approve fees
        vm.prank(user);
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // event checkers
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
            l1Gateway.getOutboundCalldata(L1_USDC, user, user, 100, "")
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(L1_USDC, user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);

        bytes memory seqNum = l1Gateway.outboundTransferCustomRefund(
            L1_USDC, creditBackAddress, user, depositAmount, maxGas, gasPriceBid, routerEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = ERC20(L1_USDC).balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = ERC20(L1_USDC).balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore,
            depositAmount,
            "Wrong l1 gateway balance"
        );

        uint256 userNativeTokenBalanceAfter = nativeToken.balanceOf(user);
        assertEq(
            userNativeTokenBalanceAfter,
            userNativeTokenBalanceBefore,
            "Wrong user native token balance"
        );

        assertEq(seqNum, abi.encode(0), "Invalid seqNum");
    }

    function test_outboundTransferCustomRefund_InboxPartiallyPrefunded() public {
        uint256 depositAmount = 100;
        deal(L1_USDC, user, depositAmount);
        bytes memory routerEncodedData = buildRouterEncodedData("");

        // pre-fund inbox
        uint256 prefundAmount = nativeTokenTotalFee / 3;
        address inbox = address(l1Gateway.inbox());
        vm.prank(user);
        nativeToken.transfer(inbox, prefundAmount);

        // snapshot state before
        uint256 userNativeTokenBalanceBefore = nativeToken.balanceOf(user);
        uint256 userBalanceBefore = ERC20(L1_USDC).balanceOf(user);
        uint256 l1GatewayBalanceBefore = ERC20(L1_USDC).balanceOf(address(l1Gateway));

        // approve token
        vm.prank(user);
        ERC20(L1_USDC).approve(address(l1Gateway), depositAmount);

        // approve fees
        vm.prank(user);
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee - prefundAmount);

        // event checkers
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
            l1Gateway.getOutboundCalldata(L1_USDC, user, user, 100, "")
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(L1_USDC, user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);

        bytes memory seqNum = l1Gateway.outboundTransferCustomRefund(
            L1_USDC, creditBackAddress, user, depositAmount, maxGas, gasPriceBid, routerEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = ERC20(L1_USDC).balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = ERC20(L1_USDC).balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore,
            depositAmount,
            "Wrong l1 gateway balance"
        );

        uint256 userNativeTokenBalanceAfter = nativeToken.balanceOf(user);
        assertEq(
            userNativeTokenBalanceBefore - userNativeTokenBalanceAfter,
            nativeTokenTotalFee - prefundAmount,
            "Wrong user native token balance"
        );

        assertEq(seqNum, abi.encode(0), "Invalid seqNum");
    }

    ///
    // Helper functions
    ///
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
