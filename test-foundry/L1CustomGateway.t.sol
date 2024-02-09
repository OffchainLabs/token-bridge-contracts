// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ArbitrumExtendedGateway.t.sol";
import {
    L1CustomGateway,
    IInbox,
    ITokenGateway,
    IERC165,
    IL1ArbitrumGateway,
    IERC20
} from "contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol";
import {L2CustomGateway} from "contracts/tokenbridge/arbitrum/gateway/L2CustomGateway.sol";
import {TestERC20} from "contracts/tokenbridge/test/TestERC20.sol";
import {InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";

contract L1CustomGatewayTest is L1ArbitrumExtendedGatewayTest {
    // gateway params
    address public owner = makeAddr("owner");

    function setUp() public virtual {
        inbox = address(new InboxMock());

        l1Gateway = new L1CustomGateway();
        L1CustomGateway(address(l1Gateway)).initialize(l2Gateway, router, inbox, owner);

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
    function test_calculateL2TokenAddress(address l1Token, address l2Token) public virtual {
        vm.assume(l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS);
        vm.deal(l1Token, 100 ether);

        // register token to gateway
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost, makeAddr("creditBackAddress")
        );

        assertEq(l1Gateway.calculateL2TokenAddress(l1Token), l2Token, "Invalid L2 token address");
    }

    function test_forceRegisterTokenToL2() public virtual {
        address[] memory l1Tokens = new address[](2);
        l1Tokens[0] = makeAddr("l1Token1");
        l1Tokens[1] = makeAddr("l1Token2");
        address[] memory l2Tokens = new address[](2);
        l2Tokens[0] = makeAddr("l2Token1");
        l2Tokens[1] = makeAddr("l2Token2");

        // expect events
        vm.expectEmit(true, true, true, true);
        emit TokenSet(l1Tokens[0], l2Tokens[0]);

        vm.expectEmit(true, true, true, true);
        emit TokenSet(l1Tokens[1], l2Tokens[1]);

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(owner, owner);

        vm.expectEmit(true, true, true, true);
        emit InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
        );

        // register token to gateway
        vm.prank(owner);
        uint256 seqNum = L1CustomGateway(address(l1Gateway)).forceRegisterTokenToL2{
            value: retryableCost
        }(l1Tokens, l2Tokens, maxGas, gasPriceBid, maxSubmissionCost);

        ///// checks
        assertEq(
            L1CustomGateway(address(l1Gateway)).l1ToL2Token(l1Tokens[0]),
            l2Tokens[0],
            "Invalid L2 token"
        );

        assertEq(
            L1CustomGateway(address(l1Gateway)).l1ToL2Token(l1Tokens[1]),
            l2Tokens[1],
            "Invalid L2 token"
        );

        assertEq(seqNum, 0, "Invalid seqNum");
    }

    function test_forceRegisterTokenToL2_revert_InvalidLength() public virtual {
        vm.prank(owner);
        vm.expectRevert("INVALID_LENGTHS");
        L1CustomGateway(address(l1Gateway)).forceRegisterTokenToL2{value: retryableCost}(
            new address[](1), new address[](2), maxGas, gasPriceBid, maxSubmissionCost
        );
    }

    function test_forceRegisterTokenToL2_revert_OnlyOwner() public {
        vm.expectRevert("ONLY_OWNER");
        L1CustomGateway(address(l1Gateway)).forceRegisterTokenToL2{value: retryableCost}(
            new address[](1), new address[](1), maxGas, gasPriceBid, maxSubmissionCost
        );
    }

    function test_initialize() public virtual {
        L1CustomGateway gateway = new L1CustomGateway();
        gateway.initialize(l2Gateway, router, inbox, owner);

        assertEq(gateway.counterpartGateway(), l2Gateway, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.inbox(), inbox, "Invalid inbox");
        assertEq(gateway.owner(), owner, "Invalid owner");
        assertEq(gateway.whitelist(), address(0), "Invalid whitelist");
    }

    function test_initialize_revert_BadInbox() public {
        L1CustomGateway gateway = new L1CustomGateway();
        address badInbox = address(0);

        vm.expectRevert("BAD_INBOX");
        gateway.initialize(l2Gateway, router, badInbox, owner);
    }

    function test_initialize_revert_BadRouter() public {
        L1CustomGateway gateway = new L1CustomGateway();
        address badRouter = address(0);

        vm.expectRevert("BAD_ROUTER");
        gateway.initialize(l2Gateway, badRouter, inbox, owner);
    }

    function test_outboundTransfer() public virtual override {
        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        uint256 depositAmount = 300;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // register token to gateway
        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        uint256 seqNum0 = L1CustomGateway(address(l1Gateway)).registerTokenToL2{
            value: retryableCost
        }(makeAddr("tokenL2Address"), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress);

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

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
            l1Gateway.getOutboundCalldata(address(token), user, user, depositAmount, callHookData)
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(token), user, user, 1, depositAmount);

        // trigger deposit
        vm.prank(router);
        bytes memory seqNum1 = l1Gateway.outboundTransfer{value: retryableCost}(
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

        assertEq(seqNum0, 0, "Invalid seqNum0");
        assertEq(seqNum1, abi.encode(1), "Invalid seqNum1");
    }

    function test_outboundTransferCustomRefund() public virtual {
        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        uint256 depositAmount = 450;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // register token to gateway
        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        uint256 seqNum0 = L1CustomGateway(address(l1Gateway)).registerTokenToL2{
            value: retryableCost
        }(makeAddr("tokenL2Address"), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress);

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

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
            l1Gateway.getOutboundCalldata(address(token), user, user, depositAmount, callHookData)
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(token), user, user, 1, depositAmount);

        // trigger deposit
        vm.prank(router);
        bytes memory seqNum1 = l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
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

        assertEq(seqNum0, 0, "Invalid seqNum0");
        assertEq(seqNum1, abi.encode(1), "Invalid seqNum1");
    }

    function test_outboundTransferCustomRefund_revert_InsufficientAllowance() public virtual {
        uint256 tooManyTokens = 500 ether;

        // register token to gateway
        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            makeAddr("creditBackAddress")
        );

        vm.prank(router);
        vm.expectRevert("ERC20: insufficient allowance");
        l1Gateway.outboundTransferCustomRefund{value: 1 ether}(
            address(token),
            user,
            user,
            tooManyTokens,
            0.1 ether,
            0.01 ether,
            buildRouterEncodedData("")
        );
    }

    function test_outboundTransferCustomRefund_revert_NoL2TokenSet() public virtual {
        uint256 tooManyTokens = 500 ether;

        // register token to gateway
        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            address(0), maxGas, gasPriceBid, maxSubmissionCost, makeAddr("creditBackAddress")
        );

        vm.prank(router);
        vm.expectRevert("NO_L2_TOKEN_SET");
        l1Gateway.outboundTransferCustomRefund{value: 1 ether}(
            address(token),
            user,
            user,
            tooManyTokens,
            0.1 ether,
            0.01 ether,
            buildRouterEncodedData("")
        );
    }

    function test_outboundTransferCustomRefund_revert_Reentrancy() public virtual {
        // register token to gateway
        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            makeAddr("tokenL2Address"), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );

        // approve token
        uint256 depositAmount = 3;
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

        // trigger re-entrancy
        MockReentrantInbox mockReentrantInbox = new MockReentrantInbox();
        vm.etch(l1Gateway.inbox(), address(mockReentrantInbox).code);

        vm.prank(router);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
            address(token),
            creditBackAddress,
            user,
            depositAmount,
            maxGas,
            gasPriceBid,
            buildRouterEncodedData("")
        );
    }

    function test_registerTokenToL2(address l1Token, address l2Token) public virtual {
        vm.assume(l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS);
        vm.deal(l1Token, 100 ether);

        // event checkers
        vm.expectEmit(true, true, true, true);
        emit TokenSet(l1Token, l2Token);

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(l1Token, l1Token);

        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(l1Token);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = address(l2Token);
        vm.expectEmit(true, true, true, true);
        emit InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
        );

        // register token to gateway
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost
        );

        assertEq(
            L1CustomGateway(address(l1Gateway)).l1ToL2Token(l1Token), l2Token, "Invalid L2 token"
        );
    }

    function test_registerTokenToL2_CustomRefund(address l1Token, address l2Token) public virtual {
        vm.assume(l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS);
        vm.deal(l1Token, 100 ether);

        // event checkers
        vm.expectEmit(true, true, true, true);
        emit TokenSet(l1Token, l2Token);

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(creditBackAddress, creditBackAddress);

        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(l1Token);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = address(l2Token);
        vm.expectEmit(true, true, true, true);
        emit InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
        );

        // register token to gateway
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );

        assertEq(
            L1CustomGateway(address(l1Gateway)).l1ToL2Token(l1Token), l2Token, "Invalid L2 token"
        );
    }

    function test_registerTokenToL2_UpdateToSameAddress(address l1Token, address l2Token)
        public
        virtual
    {
        vm.assume(l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS);
        vm.deal(l1Token, 100 ether);

        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(l1Token);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = address(l2Token);

        // register token to gateway
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost
        );

        // re-register
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost
        );

        assertEq(
            L1CustomGateway(address(l1Gateway)).l1ToL2Token(l1Token), l2Token, "Invalid L2 token"
        );
    }

    function test_registerTokenToL2_revert_NotArbEnabled() public virtual {
        // wrong answer
        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xdd))
        );

        vm.prank(address(token));
        vm.expectRevert("NOT_ARB_ENABLED");
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            address(102), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );
    }

    function test_registerTokenToL2_revert_NoUpdateToDifferentAddress() public virtual {
        // register token to gateway
        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );

        // set initial address
        address initialL2TokenAddress = makeAddr("initial");
        vm.prank(address(token));
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            initialL2TokenAddress, maxGas, gasPriceBid, maxSubmissionCost
        );
        assertEq(
            L1CustomGateway(address(l1Gateway)).l1ToL2Token(address(token)), initialL2TokenAddress
        );

        // try to set different one
        address differentL2TokenAddress = makeAddr("different");
        vm.prank(address(token));
        vm.expectRevert("NO_UPDATE_TO_DIFFERENT_ADDR");
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            differentL2TokenAddress, maxGas, gasPriceBid, maxSubmissionCost
        );
    }

    function test_setOwner(address newOwner) public {
        vm.assume(newOwner != address(0));

        vm.prank(owner);
        L1CustomGateway(address(l1Gateway)).setOwner(newOwner);

        assertEq(L1CustomGateway(address(l1Gateway)).owner(), newOwner, "Invalid owner");
    }

    function test_setOwner_revert_InvalidOwner() public {
        address invalidOwner = address(0);

        vm.prank(owner);
        vm.expectRevert("INVALID_OWNER");
        L1CustomGateway(address(l1Gateway)).setOwner(invalidOwner);
    }

    function test_setOwner_revert_OnlyOwner() public {
        address nonOwner = address(250);

        vm.prank(nonOwner);
        vm.expectRevert("ONLY_OWNER");
        L1CustomGateway(address(l1Gateway)).setOwner(address(300));
    }

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
