// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1CustomGateway.t.sol";
import {L1OrbitCustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1OrbitCustomGateway.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20PresetMinterPauser} from
    "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {TestERC20} from "contracts/tokenbridge/test/TestERC20.sol";
import {ERC20InboxMock, IBridge} from "contracts/tokenbridge/test/InboxMock.sol";

contract L1OrbitCustomGatewayTest is L1CustomGatewayTest {
    ERC20 public nativeToken;
    uint256 public nativeTokenTotalFee;

    function setUp() public virtual override {
        inbox = address(new ERC20InboxMock());
        nativeToken = ERC20(address(new ERC20PresetMinterPauser("X", "Y")));
        ERC20PresetMinterPauser(address(nativeToken)).mint(user, 1_000_000 ether);
        ERC20PresetMinterPauser(address(nativeToken)).mint(owner, 1_000_000 ether);
        ERC20InboxMock(inbox).setMockNativeToken(address(nativeToken));

        l1Gateway = new L1OrbitCustomGateway();
        L1OrbitCustomGateway(address(l1Gateway)).initialize(l2Gateway, router, inbox, owner);

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
    function test_calculateL2TokenAddress(address l1Token, address l2Token) public override {
        vm.assume(
            l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS
                && l1Token != address(0) && l1Token != router
        );
        vm.deal(l1Token, 100 ether);

        // approve fees
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(l1Token), nativeTokenTotalFee);
        vm.prank(address(l1Token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // register token to gateway
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress, nativeTokenTotalFee
        );

        assertEq(l1Gateway.calculateL2TokenAddress(l1Token), l2Token, "Invalid L2 token address");
    }

    function test_forceRegisterTokenToL2() public override {
        address[] memory l1Tokens = new address[](2);
        l1Tokens[0] = makeAddr("l1Token1");
        l1Tokens[1] = makeAddr("l1Token2");
        address[] memory l2Tokens = new address[](2);
        l2Tokens[0] = makeAddr("l2Token1");
        l2Tokens[1] = makeAddr("l2Token2");

        // approve fees
        vm.prank(owner);
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

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
        emit ERC20InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
        );

        // register token to gateway
        vm.prank(owner);
        uint256 seqNum = L1OrbitCustomGateway(address(l1Gateway)).forceRegisterTokenToL2(
            l1Tokens, l2Tokens, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        ///// checks
        assertEq(
            L1OrbitCustomGateway(address(l1Gateway)).l1ToL2Token(l1Tokens[0]),
            l2Tokens[0],
            "Invalid L2 token"
        );

        assertEq(
            L1OrbitCustomGateway(address(l1Gateway)).l1ToL2Token(l1Tokens[1]),
            l2Tokens[1],
            "Invalid L2 token"
        );

        assertEq(seqNum, 0, "Invalid seqNum");
    }

    function test_forceRegisterTokenToL2_revert_InvalidLength() public override {
        vm.prank(owner);
        vm.expectRevert("INVALID_LENGTHS");
        L1OrbitCustomGateway(address(l1Gateway)).forceRegisterTokenToL2(
            new address[](1),
            new address[](2),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            nativeTokenTotalFee
        );
    }

    function test_forceRegisterTokenToL2_revert_NotSupportedInOrbit() public {
        // register token to gateway
        vm.prank(owner);
        vm.expectRevert("NOT_SUPPORTED_IN_ORBIT");
        L1OrbitCustomGateway(address(l1Gateway)).forceRegisterTokenToL2(
            new address[](1), new address[](1), maxGas, gasPriceBid, maxSubmissionCost
        );
    }

    function test_outboundTransfer() public virtual override {
        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        uint256 depositAmount = 300;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // register token to gateway
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);
        vm.prank(address(token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        uint256 seqNum0 = L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

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
            l1Gateway.getOutboundCalldata(address(token), user, user, depositAmount, callHookData)
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(token), user, user, 1, depositAmount);

        // trigger deposit
        vm.prank(router);
        bytes memory seqNum1 = l1Gateway.outboundTransfer(
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

    function test_outboundTransferCustomRefund() public virtual override {
        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        uint256 depositAmount = 450;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // register token to gateway
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);
        vm.prank(address(token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        uint256 seqNum0 = L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

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
            l1Gateway.getOutboundCalldata(address(token), user, user, depositAmount, callHookData)
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(token), user, user, 1, depositAmount);

        // trigger deposit
        vm.prank(router);
        bytes memory seqNum1 = l1Gateway.outboundTransferCustomRefund(
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

    function test_outboundTransferCustomRefund_revert_InsufficientAllowance()
        public
        virtual
        override
    {
        uint256 tooManyTokens = 500 ether;

        // register token to gateway
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);
        vm.prank(address(token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        vm.prank(router);
        vm.expectRevert("ERC20: insufficient allowance");
        l1Gateway.outboundTransferCustomRefund(
            address(token),
            user,
            user,
            tooManyTokens,
            0.1 ether,
            0.01 ether,
            buildRouterEncodedData("")
        );
    }

    function test_outboundTransferCustomRefund_revert_NoL2TokenSet() public virtual override {
        /// not supported
    }

    function test_outboundTransferCustomRefund_revert_Reentrancy() public virtual override {
        // register token to gateway
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);
        vm.prank(address(token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        // approve token
        uint256 depositAmount = 5;
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

    function test_registerTokenToL2(address l1Token, address l2Token) public override {
        vm.assume(
            l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS
                && l1Token != address(0)
        );
        vm.deal(l1Token, 100 ether);

        // approve fees
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(l1Token), nativeTokenTotalFee);
        vm.prank(address(l1Token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

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
        emit ERC20InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
        );

        // register token to gateway
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        assertEq(
            L1OrbitCustomGateway(address(l1Gateway)).l1ToL2Token(l1Token),
            l2Token,
            "Invalid L2 token"
        );
    }

    function test_registerTokenToL2_InboxPrefunded(address l1Token, address l2Token) public {
        vm.assume(
            l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS
                && l1Token != address(0)
        );
        vm.deal(l1Token, 100 ether);

        // pre-fund inbox
        address inbox = address(l1Gateway.inbox());
        ERC20PresetMinterPauser(address(nativeToken)).mint(inbox, nativeTokenTotalFee);

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
        emit ERC20InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
        );

        // register token to gateway
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        assertEq(
            L1OrbitCustomGateway(address(l1Gateway)).l1ToL2Token(l1Token),
            l2Token,
            "Invalid L2 token"
        );
    }

    function test_registerTokenToL2_InboxPartiallyPrefunded()
        public
    {
        address l1Token = makeAddr("l1Token");
        address l2Token = makeAddr("l2Token");
        vm.deal(l1Token, 100 ether);

        // pre-fund inbox
        uint256 prefundAmount = nativeTokenTotalFee - 100;
        address inbox = address(l1Gateway.inbox());
        ERC20PresetMinterPauser(address(nativeToken)).mint(inbox, prefundAmount);

        // approve fees
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(l1Token), nativeTokenTotalFee);
        vm.prank(address(l1Token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        // snapshot
        uint256 balanceBefore = nativeToken.balanceOf(address(l1Token));

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
        emit ERC20InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
        );

        // register token to gateway
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        assertEq(
            L1OrbitCustomGateway(address(l1Gateway)).l1ToL2Token(l1Token),
            l2Token,
            "Invalid L2 token"
        );

        // snapshot after
        uint256 balanceAfter = nativeToken.balanceOf(address(l1Token));
        assertEq(
            balanceBefore - balanceAfter, nativeTokenTotalFee - prefundAmount, "Wrong user balance"
        );
    }

    function test_registerTokenToL2_CustomRefund(address l1Token, address l2Token)
        public
        override
    {
        vm.assume(
            l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS
                && l1Token != address(0) && l1Token != router && l1Token != creditBackAddress
        );
        vm.deal(l1Token, 100 ether);

        // approve fees
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(l1Token), nativeTokenTotalFee);
        vm.prank(address(l1Token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

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
        emit ERC20InboxRetryableTicket(
            address(l1Gateway),
            l2Gateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(L2CustomGateway.registerTokenFromL1.selector, l1Tokens, l2Tokens)
        );

        // register token to gateway
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress, nativeTokenTotalFee
        );

        assertEq(
            L1OrbitCustomGateway(address(l1Gateway)).l1ToL2Token(l1Token),
            l2Token,
            "Invalid L2 token"
        );
    }

    function test_registerTokenToL2_UpdateToSameAddress(address l1Token, address l2Token)
        public
        virtual
        override
    {
        vm.assume(
            l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS
                && l1Token != address(0)
        );
        vm.deal(l1Token, 100 ether);

        // approve fees
        ERC20PresetMinterPauser(address(nativeToken)).mint(
            address(l1Token), nativeTokenTotalFee * 4
        );
        vm.prank(address(l1Token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee * 4);

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
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        // re-register
        vm.mockCall(
            address(l1Token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(l1Token));
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        assertEq(
            L1OrbitCustomGateway(address(l1Gateway)).l1ToL2Token(l1Token),
            l2Token,
            "Invalid L2 token"
        );
    }

    function test_registerTokenToL2_revert_NotArbEnabled() public override {
        // wrong answer
        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xdd))
        );

        vm.prank(address(token));
        vm.expectRevert("NOT_ARB_ENABLED");
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            address(102),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );
    }

    function test_registerTokenToL2_revert_NoUpdateToDifferentAddress() public override {
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);

        // register token to gateway
        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );

        // set initial address
        address initialL2TokenAddress = makeAddr("initial");
        vm.startPrank(address(token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            initialL2TokenAddress, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );
        vm.stopPrank();
        assertEq(
            L1OrbitCustomGateway(address(l1Gateway)).l1ToL2Token(address(token)),
            initialL2TokenAddress
        );

        // try to set different one
        address differentL2TokenAddress = makeAddr("different");
        vm.startPrank(address(token));
        nativeToken.approve(address(l1Gateway), nativeTokenTotalFee);

        vm.expectRevert("NO_UPDATE_TO_DIFFERENT_ADDR");
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            differentL2TokenAddress, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );
    }

    function test_registerTokenToL2_revert_NotSupportedInOrbit() public {
        vm.expectRevert("NOT_SUPPORTED_IN_ORBIT");
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            address(100), maxGas, gasPriceBid, maxSubmissionCost
        );
    }

    function test_registerTokenToL2_revert_CustomRefund_NotSupportedInOrbit() public {
        vm.expectRevert("NOT_SUPPORTED_IN_ORBIT");
        L1OrbitCustomGateway(address(l1Gateway)).registerTokenToL2(
            address(100), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );
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
