// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1CustomGateway.t.sol";
import {L1ReverseCustomGateway} from
    "contracts/tokenbridge/ethereum/gateway/L1ReverseCustomGateway.sol";
import {
    MintableTestCustomTokenL1,
    ReverseTestCustomTokenL1
} from "contracts/tokenbridge/test/TestCustomTokenL1.sol";
import {ERC20PresetMinterPauser} from
    "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract L1ReverseCustomGatewayTest is L1CustomGatewayTest {
    function setUp() public virtual override {
        inbox = address(new InboxMock());

        l1Gateway = new L1ReverseCustomGateway();
        L1ReverseCustomGateway(address(l1Gateway)).initialize(l2Gateway, router, inbox, owner);

        token = IERC20(address(new TestERC20()));

        maxSubmissionCost = 20;
        retryableCost = maxSubmissionCost + gasPriceBid * maxGas;

        // fund user and router
        vm.prank(user);
        TestERC20(address(token)).mint();
        vm.deal(router, 100 ether);
        vm.deal(address(token), 100 ether);
        vm.deal(owner, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_finalizeInboundTransfer() public virtual override {
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

        InboxMock(address(inbox)).setL2ToL1Sender(l2Gateway);

        // trigger deposit
        vm.prank(address(IInbox(l1Gateway.inbox()).bridge()));
        l1Gateway.finalizeInboundTransfer(address(bridgedToken), from, user, amount, data);

        // check tokens are minted
        uint256 userBalanceAfter = bridgedToken.balanceOf(user);
        assertEq(userBalanceAfter - userBalanceBefore, amount, "Wrong user balance");
    }

    function test_outboundTransfer() public virtual override {
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

        // register token to gateway
        vm.mockCall(
            address(bridgedToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.deal(address(bridgedToken), 100 ether);
        vm.prank(address(bridgedToken));
        uint256 seqNum0 = L1ReverseCustomGateway(address(l1Gateway)).registerTokenToL2{
            value: retryableCost
        }(makeAddr("tokenL2Address"), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress);

        // approve token
        vm.prank(user);
        bridgedToken.approve(address(l1Gateway), amount);

        // event checkers
        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(user, user);

        vm.expectEmit(true, true, true, true);
        emit InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            l1Gateway.getOutboundCalldata(address(bridgedToken), user, user, amount, callHookData)
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(bridgedToken), user, user, 1, amount);

        // trigger transfer
        vm.prank(router);
        bytes memory seqNum1 = l1Gateway.outboundTransfer{value: retryableCost}(
            address(bridgedToken), user, amount, maxGas, gasPriceBid, routerEncodedData
        );

        // check tokens are burned
        uint256 userBalanceAfter = bridgedToken.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, amount, "Wrong user balance");

        assertEq(seqNum0, 0, "Invalid seqNum0");
        assertEq(seqNum1, abi.encode(1), "Invalid seqNum1");
    }

    function test_outboundTransferCustomRefund() public virtual override {
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

        // register token to gateway
        vm.mockCall(
            address(bridgedToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.deal(address(bridgedToken), 100 ether);
        vm.prank(address(bridgedToken));
        uint256 seqNum0 = L1ReverseCustomGateway(address(l1Gateway)).registerTokenToL2{
            value: retryableCost
        }(makeAddr("tokenL2Address"), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress);

        // approve token
        vm.prank(user);
        bridgedToken.approve(address(l1Gateway), amount);

        // event checkers
        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(creditBackAddress, user);

        vm.expectEmit(true, true, true, true);
        emit InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            l1Gateway.getOutboundCalldata(address(bridgedToken), user, user, amount, callHookData)
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(bridgedToken), user, user, 1, amount);

        // trigger deposit
        vm.prank(router);
        bytes memory seqNum1 = l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
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

    function test_outboundTransferCustomRefund_revert_InsufficientAllowance()
        public
        virtual
        override
    {
        // fund user with tokens
        MintableTestCustomTokenL1 bridgedToken =
            new ReverseTestCustomTokenL1(address(l1Gateway), router);
        vm.prank(address(user));
        bridgedToken.mint();

        uint256 tooManyTokens = 500 ether;

        // register token to gateway
        vm.mockCall(
            address(bridgedToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.deal(address(bridgedToken), 100 ether);
        vm.prank(address(bridgedToken));
        L1ReverseCustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            makeAddr("creditBackAddress")
        );

        vm.prank(router);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        l1Gateway.outboundTransferCustomRefund{value: 1 ether}(
            address(bridgedToken),
            user,
            user,
            tooManyTokens,
            0.1 ether,
            0.01 ether,
            buildRouterEncodedData("")
        );
    }

    function test_outboundTransferCustomRefund_revert_Reentrancy() public virtual override {
        // fund user with tokens
        MintableTestCustomTokenL1 bridgedToken =
            new ReverseTestCustomTokenL1(address(l1Gateway), router);
        vm.prank(address(user));
        bridgedToken.mint();

        // register token to gateway
        vm.mockCall(
            address(bridgedToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.deal(address(bridgedToken), 100 ether);
        vm.prank(address(bridgedToken));
        L1ReverseCustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            makeAddr("tokenL2Address"), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );

        // approve token
        uint256 amount = 450;
        vm.prank(user);
        bridgedToken.approve(address(l1Gateway), amount);

        // trigger re-entrancy
        MockReentrantERC20 mockReentrantERC20 = new MockReentrantERC20();
        vm.etch(address(bridgedToken), address(mockReentrantERC20).code);

        vm.expectRevert("ReentrancyGuard: reentrant call");
        vm.prank(router);
        l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
            address(bridgedToken),
            creditBackAddress,
            user,
            amount,
            maxGas,
            gasPriceBid,
            buildRouterEncodedData("")
        );
    }
}
