// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {
    L1OrbitCustomGatewayTest,
    ERC20InboxMock,
    TestERC20,
    IERC20,
    ERC20,
    ERC20PresetMinterPauser
} from "./L1OrbitCustomGateway.t.sol";
import {L1OrbitReverseCustomGateway} from
    "contracts/tokenbridge/ethereum/gateway/L1OrbitReverseCustomGateway.sol";
import {
    MintableTestCustomTokenL1,
    ReverseTestCustomTokenL1
} from "contracts/tokenbridge/test/TestCustomTokenL1.sol";
import {IInbox} from "contracts/tokenbridge/ethereum/L1ArbitrumMessenger.sol";

contract L1OrbitReverseCustomGatewayTest is L1OrbitCustomGatewayTest {
    function setUp() public override {
        inbox = address(new ERC20InboxMock());
        nativeToken = ERC20(address(new ERC20PresetMinterPauser("X", "Y")));
        ERC20PresetMinterPauser(address(nativeToken)).mint(user, 1_000_000 ether);
        ERC20PresetMinterPauser(address(nativeToken)).mint(owner, 1_000_000 ether);
        ERC20InboxMock(inbox).setMockNativeToken(address(nativeToken));

        l1Gateway = new L1OrbitReverseCustomGateway();
        L1OrbitReverseCustomGateway(address(l1Gateway)).initialize(l2Gateway, router, inbox, owner);

        token = IERC20(address(new TestERC20()));

        maxSubmissionCost = 0;
        nativeTokenTotalFee = maxGas * gasPriceBid;

        // fund user and router
        vm.prank(user);
        TestERC20(address(token)).mint();
        vm.deal(router, 100 ether);
        vm.deal(address(token), 100 ether);
        vm.deal(owner, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_finalizeInboundTransfer() public override {
        // fund gateway with bridged tokens
        MintableTestCustomTokenL1 bridgedToken =
            new MintableTestCustomTokenL1(address(l1Gateway), router);
        vm.prank(address(l1Gateway));
        bridgedToken.mint();

        // snapshot state before
        uint256 userBalanceBefore = bridgedToken.balanceOf(user);

        // deposit params
        address from = address(3000);
        uint256 amount = 25;
        uint256 exitNum = 7;
        bytes memory callHookData = "";
        bytes memory data = abi.encode(exitNum, callHookData);

        ERC20InboxMock(address(inbox)).setL2ToL1Sender(l2Gateway);

        // trigger deposit
        vm.prank(address(IInbox(l1Gateway.inbox()).bridge()));
        L1OrbitReverseCustomGateway(address(l1Gateway)).finalizeInboundTransfer(
            address(bridgedToken), from, user, amount, data
        );

        // check tokens are minted
        uint256 userBalanceAfter = bridgedToken.balanceOf(user);
        assertEq(userBalanceAfter - userBalanceBefore, amount, "Wrong user balance");
    }

    function test_outboundTransfer() public override {
        // fund user with tokens
        MintableTestCustomTokenL1 bridgedToken =
            new ReverseTestCustomTokenL1(address(l1Gateway), router);
        vm.prank(address(user));
        bridgedToken.mint();

        // snapshot state before
        uint256 userBalanceBefore = bridgedToken.balanceOf(user);

        uint256 amount = 300;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // approve fees
        ERC20PresetMinterPauser(address(nativeToken)).mint(
            address(bridgedToken), nativeTokenTotalFee
        );
        vm.prank(address(bridgedToken));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // register token to gateway
        vm.mockCall(
            address(bridgedToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.deal(address(bridgedToken), 100 ether);
        vm.prank(address(bridgedToken));
        uint256 seqNum0 = L1OrbitReverseCustomGateway(address(l1Gateway)).registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        // approve token
        vm.prank(user);
        bridgedToken.approve(address(l1Gateway), amount);

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
            l1Gateway.getOutboundCalldata(address(bridgedToken), user, user, amount, callHookData)
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(bridgedToken), user, user, 1, amount);

        // trigger transfer
        vm.prank(router);
        bytes memory seqNum1 = L1OrbitReverseCustomGateway(address(l1Gateway)).outboundTransfer(
            address(bridgedToken), user, amount, maxGas, gasPriceBid, routerEncodedData
        );

        // check tokens are burned
        uint256 userBalanceAfter = bridgedToken.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, amount, "Wrong user balance");

        assertEq(seqNum0, 0, "Invalid seqNum0");
        assertEq(seqNum1, abi.encode(1), "Invalid seqNum1");
    }

    function test_outboundTransferCustomRefund() public override {
        // fund user with tokens
        MintableTestCustomTokenL1 bridgedToken =
            new ReverseTestCustomTokenL1(address(l1Gateway), router);
        vm.prank(address(user));
        bridgedToken.mint();

        // snapshot state before
        uint256 userBalanceBefore = bridgedToken.balanceOf(user);

        uint256 amount = 450;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // approve fees
        ERC20PresetMinterPauser(address(nativeToken)).mint(
            address(bridgedToken), nativeTokenTotalFee
        );
        vm.prank(address(bridgedToken));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // register token to gateway
        vm.mockCall(
            address(bridgedToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.deal(address(bridgedToken), 100 ether);
        vm.prank(address(bridgedToken));
        uint256 seqNum0 = L1OrbitReverseCustomGateway(address(l1Gateway)).registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        // approve token
        vm.prank(user);
        bridgedToken.approve(address(l1Gateway), amount);

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
            l1Gateway.getOutboundCalldata(address(bridgedToken), user, user, amount, callHookData)
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(bridgedToken), user, user, 1, amount);

        // trigger deposit
        vm.prank(router);
        bytes memory seqNum1 = L1OrbitReverseCustomGateway(address(l1Gateway))
            .outboundTransferCustomRefund(
            address(bridgedToken),
            creditBackAddress,
            user,
            amount,
            maxGas,
            gasPriceBid,
            routerEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = bridgedToken.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, amount, "Wrong user balance");

        assertEq(seqNum0, 0, "Invalid seqNum0");
        assertEq(seqNum1, abi.encode(1), "Invalid seqNum1");
    }

    function test_outboundTransferCustomRefund_revert_InsufficientAllowance() public override {
        // fund user with tokens
        MintableTestCustomTokenL1 bridgedToken =
            new ReverseTestCustomTokenL1(address(l1Gateway), router);
        vm.prank(address(user));
        bridgedToken.mint();

        uint256 tooManyTokens = 500 ether;

        // approve fees
        ERC20PresetMinterPauser(address(nativeToken)).mint(
            address(bridgedToken), nativeTokenTotalFee
        );
        vm.prank(address(bridgedToken));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // register token to gateway
        vm.mockCall(
            address(bridgedToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.deal(address(bridgedToken), 100 ether);
        vm.prank(address(bridgedToken));
        L1OrbitReverseCustomGateway(address(l1Gateway)).registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        vm.prank(user);
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        vm.prank(router);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        l1Gateway.outboundTransferCustomRefund(
            address(bridgedToken),
            user,
            user,
            tooManyTokens,
            0.1 ether,
            0.01 ether,
            buildRouterEncodedData("")
        );
    }
}
