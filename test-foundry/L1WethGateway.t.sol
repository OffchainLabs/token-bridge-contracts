// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ArbitrumExtendedGateway.t.sol";
import {
    L1WethGateway,
    IInbox,
    ITokenGateway,
    IERC165,
    IL1ArbitrumGateway,
    IERC20
} from "contracts/tokenbridge/ethereum/gateway/L1WethGateway.sol";
import {L2CustomGateway} from "contracts/tokenbridge/arbitrum/gateway/L2CustomGateway.sol";
import {TestERC20} from "contracts/tokenbridge/test/TestERC20.sol";
import {InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";
import {TestWETH9} from "contracts/tokenbridge/test/TestWETH9.sol";

contract L1WethGatewayTest is L1ArbitrumExtendedGatewayTest {
    // gateway params
    address public owner = makeAddr("owner");

    address public L1_WETH = address(new TestWETH9("weth", "weth"));
    address public L2_WETH = makeAddr("L2_WETH");

    function setUp() public virtual {
        inbox = address(new InboxMock());

        l1Gateway = new L1WethGateway();
        L1WethGateway(payable(address(l1Gateway))).initialize(
            l2Gateway, router, inbox, L1_WETH, L2_WETH
        );

        maxSubmissionCost = 20;
        retryableCost = maxSubmissionCost + gasPriceBid * maxGas;

        vm.deal(router, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */

    function test_finalizeInboundTransfer() public override {
        // fund gateway with tokens being withdrawn
        uint256 withdrawalAmount = 25 ether;
        vm.deal(address(l1Gateway), withdrawalAmount);

        // snapshot state before
        uint256 userBalanceBefore = ERC20(L1_WETH).balanceOf(user);
        uint256 l1GatewayBalanceBefore = address(l1Gateway).balance;

        // withdrawal params
        address from = address(3000);
        uint256 exitNum = 7;
        bytes memory callHookData = "";
        bytes memory data = abi.encode(exitNum, callHookData);

        InboxMock(address(inbox)).setL2ToL1Sender(l2Gateway);

        // trigger withdrawal
        vm.prank(address(IInbox(l1Gateway.inbox()).bridge()));
        l1Gateway.finalizeInboundTransfer(L1_WETH, from, user, withdrawalAmount, data);

        // check tokens are properly released
        uint256 userBalanceAfter = ERC20(L1_WETH).balanceOf(user);
        assertEq(userBalanceAfter - userBalanceBefore, withdrawalAmount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = address(l1Gateway).balance;
        assertEq(
            l1GatewayBalanceBefore - l1GatewayBalanceAfter,
            withdrawalAmount,
            "Wrong l1 gateway balance"
        );
    }

    function test_getExternalCall_Redirected(uint256 exitNum, address initialDest, address newDest)
        public
        override
    {
        // N/A
    }

    function test_transferExitAndCall(uint256, address, address) public override {
        // do it
        address initialDestination = makeAddr("initialDestination");
        vm.prank(initialDestination);
        vm.expectRevert("TRADABLE_EXIT_TEMP_DISABLED");
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            1, initialDestination, makeAddr("newDestination"), bytes(""), bytes("")
        );
    }

    function test_transferExitAndCall_EmptyData_Redirected(
        uint256 exitNum,
        address initialDestination
    ) public override {
        // N/A
    }

    function test_transferExitAndCall_NonEmptyData(uint256 exitNum, address initialDestination)
        public
        override
    {
        bytes memory data = abi.encode("fun()");
        vm.prank(initialDestination);
        vm.expectRevert("TRADABLE_EXIT_TEMP_DISABLED");
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            exitNum, initialDestination, makeAddr("newDestination"), bytes(""), data
        );
    }

    function test_transferExitAndCall_NonEmptyData_Redirected(uint256, address) public override {
        // N/A
    }

    function test_transferExitAndCall_revert_ToNotContract(address initialDestination)
        public
        override
    {
        bytes memory data = abi.encode("execute()");
        address nonContractNewDestination = address(15);

        vm.prank(initialDestination);
        vm.expectRevert("TRADABLE_EXIT_TEMP_DISABLED");
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            4, initialDestination, nonContractNewDestination, "", data
        );
    }

    function test_transferExitAndCall_revert_TransferHookFail(uint256, address) public override {
        // N/A
    }

    function test_transferExitAndCall_revert_TransferHookFail_Redirected(uint256, address)
        public
        override
    {
        // N/A
    }

    function test_calculateL2TokenAddress() public virtual {
        assertEq(l1Gateway.calculateL2TokenAddress(L1_WETH), L2_WETH, "Invalid L2 token address");
    }

    function test_calculateL2TokenAddress(address l1Token) public virtual {
        vm.assume(l1Token != L1_WETH);
        assertEq(l1Gateway.calculateL2TokenAddress(l1Token), address(0), "Invalid L2 token address");
    }

    // function test_forceRegisterTokenToL2() public virtual {
    //     address[] memory l1Tokens = new address[](2);
    //     l1Tokens[0] = makeAddr("l1Token1");
    //     l1Tokens[1] = makeAddr("l1Token2");
    //     address[] memory l2Tokens = new address[](2);
    //     l2Tokens[0] = makeAddr("l2Token1");
    //     l2Tokens[1] = makeAddr("l2Token2");

    //     // expect events
    //     vm.expectEmit(true, true, true, true);
    //     emit TokenSet(l1Tokens[0], l2Tokens[0]);

    //     vm.expectEmit(true, true, true, true);
    //     emit TokenSet(l1Tokens[1], l2Tokens[1]);

    //     vm.expectEmit(true, true, true, true);
    //     emit TicketData(maxSubmissionCost);

    //     vm.expectEmit(true, true, true, true);
    //     emit RefundAddresses(owner, owner);

    //     vm.expectEmit(true, true, true, true);
    //     emit InboxRetryableTicket(
    //         address(l1Gateway),
    //         l2Gateway,
    //         0,
    //         maxGas,
    //         abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
    //     );

    //     // register token to gateway
    //     vm.prank(owner);
    //     uint256 seqNum = L1WethGateway(address(l1Gateway)).forceRegisterTokenToL2{
    //         value: retryableCost
    //     }(l1Tokens, l2Tokens, maxGas, gasPriceBid, maxSubmissionCost);

    //     ///// checks
    //     assertEq(
    //         L1WethGateway(address(l1Gateway)).l1ToL2Token(l1Tokens[0]),
    //         l2Tokens[0],
    //         "Invalid L2 token"
    //     );

    //     assertEq(
    //         L1WethGateway(address(l1Gateway)).l1ToL2Token(l1Tokens[1]),
    //         l2Tokens[1],
    //         "Invalid L2 token"
    //     );

    //     assertEq(seqNum, 0, "Invalid seqNum");
    // }

    // function test_forceRegisterTokenToL2_revert_InvalidLength() public virtual {
    //     vm.prank(owner);
    //     vm.expectRevert("INVALID_LENGTHS");
    //     L1WethGateway(address(l1Gateway)).forceRegisterTokenToL2{value: retryableCost}(
    //         new address[](1), new address[](2), maxGas, gasPriceBid, maxSubmissionCost
    //     );
    // }

    // function test_forceRegisterTokenToL2_revert_OnlyOwner() public {
    //     vm.expectRevert("ONLY_OWNER");
    //     L1WethGateway(address(l1Gateway)).forceRegisterTokenToL2{value: retryableCost}(
    //         new address[](1), new address[](1), maxGas, gasPriceBid, maxSubmissionCost
    //     );
    // }

    // function test_getOutboundCalldata() public {
    //     bytes memory outboundCalldata = l1Gateway.getOutboundCalldata({
    //         _token: address(token),
    //         _from: user,
    //         _to: address(800),
    //         _amount: 355,
    //         _data: abi.encode("doStuff()")
    //     });

    //     bytes memory expectedCalldata = abi.encodeWithSelector(
    //         ITokenGateway.finalizeInboundTransfer.selector,
    //         address(token),
    //         user,
    //         address(800),
    //         355,
    //         abi.encode("", abi.encode("doStuff()"))
    //     );

    //     assertEq(outboundCalldata, expectedCalldata, "Invalid outboundCalldata");
    // }

    function test_initialize() public {
        L1WethGateway gateway = new L1WethGateway();
        gateway.initialize(l2Gateway, router, inbox, L1_WETH, L2_WETH);

        assertEq(gateway.counterpartGateway(), l2Gateway, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.inbox(), inbox, "Invalid inbox");
        assertEq(gateway.l1Weth(), L1_WETH, "Invalid L1_WETH");
        assertEq(gateway.l2Weth(), L2_WETH, "Invalid L2_WETH");
    }

    function test_initialize_revert_InvalidL1Weth() public {
        L1WethGateway gateway = new L1WethGateway();
        vm.expectRevert("INVALID_L1WETH");
        gateway.initialize(l2Gateway, router, inbox, address(0), L2_WETH);
    }

    function test_initialize_revert_InvalidL2Weth() public {
        L1WethGateway gateway = new L1WethGateway();
        vm.expectRevert("INVALID_L2WETH");
        gateway.initialize(l2Gateway, router, inbox, L1_WETH, address(0));
    }

    function test_outboundTransferCustomRefund() public virtual {
        uint256 depositAmountInToken = 2 ether;
        uint256 depositAmountInEth = 4 ether;
        uint256 depositAmount = depositAmountInToken + depositAmountInEth;

        // snapshot state before
        vm.deal(user, depositAmount * 2);
        vm.prank(user);
        TestWETH9(L1_WETH).deposit{value: depositAmountInToken}();
        uint256 userBalanceBefore = user.balance;
        uint256 userWethBalanceBefore = ERC20(L1_WETH).balanceOf(user);
        uint256 bridgeBalanceBefore = address(IInbox(l1Gateway.inbox()).bridge()).balance;

        {
            // approve token
            vm.prank(user);
            ERC20(L1_WETH).approve(address(l1Gateway), depositAmountInToken);

            // event checkers
            vm.expectEmit(true, true, true, true);
            emit TicketData(maxSubmissionCost);

            vm.expectEmit(true, true, true, true);
            emit RefundAddresses(creditBackAddress, user);
        }

        vm.expectEmit(true, true, true, true);
        emit InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            depositAmountInToken,
            maxGas,
            l1Gateway.getOutboundCalldata(address(L1_WETH), user, user, depositAmountInToken, "")
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(L1_WETH), user, user, 0, depositAmountInToken);

        // trigger deposit
        vm.prank(router);
        bytes memory seqNum0 = l1Gateway.outboundTransferCustomRefund{
            value: retryableCost + depositAmountInEth
        }(
            L1_WETH,
            creditBackAddress,
            user,
            depositAmountInToken,
            maxGas,
            gasPriceBid,
            buildRouterEncodedData("")
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = user.balance;
        assertLe(userBalanceBefore - userBalanceAfter, depositAmountInEth, "Wrong user ETH balance");

        uint256 userWethBalanceAfter = ERC20(L1_WETH).balanceOf(user);
        assertEq(
            userWethBalanceBefore - userWethBalanceAfter,
            depositAmountInToken,
            "Wrong user WETH balance"
        );

        uint256 bridgeBalanceAfter = address(IInbox(l1Gateway.inbox()).bridge()).balance;
        assertGe(bridgeBalanceAfter - bridgeBalanceBefore, depositAmount, "Wrong bridge balance");

        assertEq(seqNum0, abi.encode(0), "Invalid seqNum0");
    }

    // function test_outboundTransfer() public virtual {
    //     // snapshot state before
    //     uint256 userBalanceBefore = token.balanceOf(user);
    //     uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

    //     uint256 depositAmount = 300;
    //     bytes memory callHookData = "";
    //     bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

    //     // register token to gateway
    //     vm.mockCall(
    //         address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
    //     );
    //     vm.prank(address(token));
    //     uint256 seqNum0 = L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         makeAddr("tokenL2Address"), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
    //     );

    //     // approve token
    //     vm.prank(user);
    //     token.approve(address(l1Gateway), depositAmount);

    //     // event checkers
    //     vm.expectEmit(true, true, true, true);
    //     emit TicketData(maxSubmissionCost);

    //     vm.expectEmit(true, true, true, true);
    //     emit RefundAddresses(user, user);

    //     vm.expectEmit(true, true, true, true);
    //     emit InboxRetryableTicket(
    //         address(l1Gateway),
    //         l2Gateway,
    //         0,
    //         maxGas,
    //         l1Gateway.getOutboundCalldata(address(token), user, user, depositAmount, callHookData)
    //     );

    //     vm.expectEmit(true, true, true, true);
    //     emit DepositInitiated(address(token), user, user, 1, depositAmount);

    //     // trigger deposit
    //     vm.prank(router);
    //     bytes memory seqNum1 = l1Gateway.outboundTransfer{value: retryableCost}(
    //         address(token), user, depositAmount, maxGas, gasPriceBid, routerEncodedData
    //     );

    //     // check tokens are escrowed
    //     uint256 userBalanceAfter = token.balanceOf(user);
    //     assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong user balance");

    //     uint256 l1GatewayBalanceAfter = token.balanceOf(address(l1Gateway));
    //     assertEq(
    //         l1GatewayBalanceAfter - l1GatewayBalanceBefore,
    //         depositAmount,
    //         "Wrong l1 gateway balance"
    //     );

    //     assertEq(seqNum0, 0, "Invalid seqNum0");
    //     assertEq(seqNum1, abi.encode(1), "Invalid seqNum1");
    // }

    // function test_outboundTransferCustomRefund() public virtual {
    //     // snapshot state before
    //     uint256 userBalanceBefore = token.balanceOf(user);
    //     uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

    //     uint256 depositAmount = 450;
    //     bytes memory callHookData = "";
    //     bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

    //     // register token to gateway
    //     vm.mockCall(
    //         address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
    //     );
    //     vm.prank(address(token));
    //     uint256 seqNum0 = L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         makeAddr("tokenL2Address"), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
    //     );

    //     // approve token
    //     vm.prank(user);
    //     token.approve(address(l1Gateway), depositAmount);

    //     // event checkers
    //     vm.expectEmit(true, true, true, true);
    //     emit TicketData(maxSubmissionCost);

    //     vm.expectEmit(true, true, true, true);
    //     emit RefundAddresses(creditBackAddress, user);

    //     vm.expectEmit(true, true, true, true);
    //     emit InboxRetryableTicket(
    //         address(l1Gateway),
    //         l2Gateway,
    //         0,
    //         maxGas,
    //         l1Gateway.getOutboundCalldata(address(token), user, user, depositAmount, callHookData)
    //     );

    //     vm.expectEmit(true, true, true, true);
    //     emit DepositInitiated(address(token), user, user, 1, depositAmount);

    //     // trigger deposit
    //     vm.prank(router);
    //     bytes memory seqNum1 = l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
    //         address(token),
    //         creditBackAddress,
    //         user,
    //         depositAmount,
    //         maxGas,
    //         gasPriceBid,
    //         routerEncodedData
    //     );

    //     // check tokens are escrowed
    //     uint256 userBalanceAfter = token.balanceOf(user);
    //     assertEq(userBalanceBefore - userBalanceAfter, depositAmount, "Wrong user balance");

    //     uint256 l1GatewayBalanceAfter = token.balanceOf(address(l1Gateway));
    //     assertEq(
    //         l1GatewayBalanceAfter - l1GatewayBalanceBefore,
    //         depositAmount,
    //         "Wrong l1 gateway balance"
    //     );

    //     assertEq(seqNum0, 0, "Invalid seqNum0");
    //     assertEq(seqNum1, abi.encode(1), "Invalid seqNum1");
    // }

    // function test_outboundTransferCustomRefund_revert_InsufficientAllowance() public virtual {
    //     uint256 tooManyTokens = 500 ether;

    //     // register token to gateway
    //     vm.mockCall(
    //         address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
    //     );
    //     vm.prank(address(token));
    //     L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         makeAddr("tokenL2Address"),
    //         maxGas,
    //         gasPriceBid,
    //         maxSubmissionCost,
    //         makeAddr("creditBackAddress")
    //     );

    //     vm.prank(router);
    //     vm.expectRevert("ERC20: insufficient allowance");
    //     l1Gateway.outboundTransferCustomRefund{value: 1 ether}(
    //         address(token),
    //         user,
    //         user,
    //         tooManyTokens,
    //         0.1 ether,
    //         0.01 ether,
    //         buildRouterEncodedData("")
    //     );
    // }

    // function test_outboundTransferCustomRefund_revert_NoL2TokenSet() public virtual {
    //     uint256 tooManyTokens = 500 ether;

    //     // register token to gateway
    //     vm.mockCall(
    //         address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
    //     );
    //     vm.prank(address(token));
    //     L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         address(0), maxGas, gasPriceBid, maxSubmissionCost, makeAddr("creditBackAddress")
    //     );

    //     vm.prank(router);
    //     vm.expectRevert("NO_L2_TOKEN_SET");
    //     l1Gateway.outboundTransferCustomRefund{value: 1 ether}(
    //         address(token),
    //         user,
    //         user,
    //         tooManyTokens,
    //         0.1 ether,
    //         0.01 ether,
    //         buildRouterEncodedData("")
    //     );
    // }

    // function test_outboundTransferCustomRefund_revert_Reentrancy() public virtual {
    //     // register token to gateway
    //     vm.mockCall(
    //         address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
    //     );
    //     vm.prank(address(token));
    //     L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         makeAddr("tokenL2Address"), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
    //     );

    //     // approve token
    //     uint256 depositAmount = 3;
    //     vm.prank(user);
    //     token.approve(address(l1Gateway), depositAmount);

    //     // trigger re-entrancy
    //     MockReentrantInbox mockReentrantInbox = new MockReentrantInbox();
    //     vm.etch(l1Gateway.inbox(), address(mockReentrantInbox).code);

    //     vm.prank(router);
    //     vm.expectRevert("ReentrancyGuard: reentrant call");
    //     l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
    //         address(token),
    //         creditBackAddress,
    //         user,
    //         depositAmount,
    //         maxGas,
    //         gasPriceBid,
    //         buildRouterEncodedData("")
    //     );
    // }

    // function test_registerTokenToL2(address l1Token, address l2Token) public virtual {
    //     vm.assume(l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS);
    //     vm.deal(l1Token, 100 ether);

    //     // event checkers
    //     vm.expectEmit(true, true, true, true);
    //     emit TokenSet(l1Token, l2Token);

    //     vm.expectEmit(true, true, true, true);
    //     emit TicketData(maxSubmissionCost);

    //     vm.expectEmit(true, true, true, true);
    //     emit RefundAddresses(l1Token, l1Token);

    //     address[] memory l1Tokens = new address[](1);
    //     l1Tokens[0] = address(l1Token);
    //     address[] memory l2Tokens = new address[](1);
    //     l2Tokens[0] = address(l2Token);
    //     vm.expectEmit(true, true, true, true);
    //     emit InboxRetryableTicket(
    //         address(l1Gateway),
    //         l2Gateway,
    //         0,
    //         maxGas,
    //         abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
    //     );

    //     // register token to gateway
    //     vm.mockCall(
    //         address(l1Token),
    //         abi.encodeWithSignature("isArbitrumEnabled()"),
    //         abi.encode(uint8(0xb1))
    //     );
    //     vm.prank(address(l1Token));
    //     L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         l2Token, maxGas, gasPriceBid, maxSubmissionCost
    //     );

    //     assertEq(
    //         L1WethGateway(address(l1Gateway)).l1ToL2Token(l1Token), l2Token, "Invalid L2 token"
    //     );
    // }

    // function test_registerTokenToL2_CustomRefund(address l1Token, address l2Token) public virtual {
    //     vm.assume(l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS);
    //     vm.deal(l1Token, 100 ether);

    //     // event checkers
    //     vm.expectEmit(true, true, true, true);
    //     emit TokenSet(l1Token, l2Token);

    //     vm.expectEmit(true, true, true, true);
    //     emit TicketData(maxSubmissionCost);

    //     vm.expectEmit(true, true, true, true);
    //     emit RefundAddresses(creditBackAddress, creditBackAddress);

    //     address[] memory l1Tokens = new address[](1);
    //     l1Tokens[0] = address(l1Token);
    //     address[] memory l2Tokens = new address[](1);
    //     l2Tokens[0] = address(l2Token);
    //     vm.expectEmit(true, true, true, true);
    //     emit InboxRetryableTicket(
    //         address(l1Gateway),
    //         l2Gateway,
    //         0,
    //         maxGas,
    //         abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
    //     );

    //     // register token to gateway
    //     vm.mockCall(
    //         address(l1Token),
    //         abi.encodeWithSignature("isArbitrumEnabled()"),
    //         abi.encode(uint8(0xb1))
    //     );
    //     vm.prank(address(l1Token));
    //     L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         l2Token, maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
    //     );

    //     assertEq(
    //         L1WethGateway(address(l1Gateway)).l1ToL2Token(l1Token), l2Token, "Invalid L2 token"
    //     );
    // }

    // function test_registerTokenToL2_UpdateToSameAddress(address l1Token, address l2Token)
    //     public
    //     virtual
    // {
    //     vm.assume(l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS);
    //     vm.deal(l1Token, 100 ether);

    //     address[] memory l1Tokens = new address[](1);
    //     l1Tokens[0] = address(l1Token);
    //     address[] memory l2Tokens = new address[](1);
    //     l2Tokens[0] = address(l2Token);

    //     // register token to gateway
    //     vm.mockCall(
    //         address(l1Token),
    //         abi.encodeWithSignature("isArbitrumEnabled()"),
    //         abi.encode(uint8(0xb1))
    //     );
    //     vm.prank(address(l1Token));
    //     L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         l2Token, maxGas, gasPriceBid, maxSubmissionCost
    //     );

    //     // re-register
    //     vm.mockCall(
    //         address(l1Token),
    //         abi.encodeWithSignature("isArbitrumEnabled()"),
    //         abi.encode(uint8(0xb1))
    //     );
    //     vm.prank(address(l1Token));
    //     L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         l2Token, maxGas, gasPriceBid, maxSubmissionCost
    //     );

    //     assertEq(
    //         L1WethGateway(address(l1Gateway)).l1ToL2Token(l1Token), l2Token, "Invalid L2 token"
    //     );
    // }

    // function test_registerTokenToL2_revert_NotArbEnabled() public virtual {
    //     // wrong answer
    //     vm.mockCall(
    //         address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xdd))
    //     );

    //     vm.prank(address(token));
    //     vm.expectRevert("NOT_ARB_ENABLED");
    //     L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         address(102), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
    //     );
    // }

    // function test_registerTokenToL2_revert_NoUpdateToDifferentAddress() public virtual {
    //     // register token to gateway
    //     vm.mockCall(
    //         address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
    //     );

    //     // set initial address
    //     address initialL2TokenAddress = makeAddr("initial");
    //     vm.prank(address(token));
    //     L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         initialL2TokenAddress, maxGas, gasPriceBid, maxSubmissionCost
    //     );
    //     assertEq(
    //         L1WethGateway(address(l1Gateway)).l1ToL2Token(address(token)), initialL2TokenAddress
    //     );

    //     // try to set different one
    //     address differentL2TokenAddress = makeAddr("different");
    //     vm.prank(address(token));
    //     vm.expectRevert("NO_UPDATE_TO_DIFFERENT_ADDR");
    //     L1WethGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
    //         differentL2TokenAddress, maxGas, gasPriceBid, maxSubmissionCost
    //     );
    // }

    // function test_setOwner(address newOwner) public {
    //     vm.assume(newOwner != address(0));

    //     vm.prank(owner);
    //     L1WethGateway(address(l1Gateway)).setOwner(newOwner);

    //     assertEq(L1WethGateway(address(l1Gateway)).owner(), newOwner, "Invalid owner");
    // }

    // function test_setOwner_revert_InvalidOwner() public {
    //     address invalidOwner = address(0);

    //     vm.prank(owner);
    //     vm.expectRevert("INVALID_OWNER");
    //     L1WethGateway(address(l1Gateway)).setOwner(invalidOwner);
    // }

    // function test_setOwner_revert_OnlyOwner() public {
    //     address nonOwner = address(250);

    //     vm.prank(nonOwner);
    //     vm.expectRevert("ONLY_OWNER");
    //     L1WethGateway(address(l1Gateway)).setOwner(address(300));
    // }

    ////
    // Event declarations
    ////
    event TokenSet(address indexed l1Address, address indexed l2Address);

    event DepositInitiated(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _sequenceNumber,
        uint256 _amount
    );
    event TicketData(uint256 maxSubmissionCost);
    event RefundAddresses(address excessFeeRefundAddress, address callValueRefundAddress);
    event InboxRetryableTicket(address from, address to, uint256 value, uint256 maxGas, bytes data);
}
