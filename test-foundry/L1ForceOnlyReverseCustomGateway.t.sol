// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ReverseCustomGateway.t.sol";
import {L1ForceOnlyReverseCustomGateway} from
    "contracts/tokenbridge/ethereum/gateway/L1ForceOnlyReverseCustomGateway.sol";
import {
    MintableTestCustomTokenL1,
    ReverseTestCustomTokenL1
} from "contracts/tokenbridge/test/TestCustomTokenL1.sol";
import {ERC20PresetMinterPauser} from
    "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract L1ForceOnlyReverseCustomGatewayTest is L1ReverseCustomGatewayTest {
    function setUp() public virtual override {
        inbox = address(new InboxMock());

        l1Gateway = new L1ForceOnlyReverseCustomGateway();
        L1ForceOnlyReverseCustomGateway(address(l1Gateway)).initialize(
            l2Gateway, router, inbox, owner
        );

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
    function test_calculateL2TokenAddress(address l1Token, address l2Token)
        public
        virtual
        override
    {
        vm.assume(l1Token != FOUNDRY_CHEATCODE_ADDRESS && l2Token != FOUNDRY_CHEATCODE_ADDRESS);
        vm.deal(l1Token, 100 ether);

        // register token to gateway
        // register token to gateway
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = l1Token;
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = l2Token;

        vm.prank(owner);
        uint256 seqNum0 = L1CustomGateway(address(l1Gateway)).forceRegisterTokenToL2{
            value: retryableCost
        }(l1Tokens, l2Tokens, maxGas, gasPriceBid, maxSubmissionCost);

        assertEq(l1Gateway.calculateL2TokenAddress(l1Token), l2Token, "Invalid L2 token address");
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

        // register token to gateway
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(bridgedToken);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = makeAddr("tokenL2Address");

        vm.prank(owner);
        uint256 seqNum0 = L1CustomGateway(address(l1Gateway)).forceRegisterTokenToL2{
            value: retryableCost
        }(l1Tokens, l2Tokens, maxGas, gasPriceBid, maxSubmissionCost);

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

        // register token to gateway
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(bridgedToken);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = makeAddr("tokenL2Address");

        vm.prank(owner);
        uint256 seqNum0 = L1CustomGateway(address(l1Gateway)).forceRegisterTokenToL2{
            value: retryableCost
        }(l1Tokens, l2Tokens, maxGas, gasPriceBid, maxSubmissionCost);

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

    function test_outboundTransferCustomRefund_revert_InsufficientAllowance() public override {
        // fund user with tokens
        MintableTestCustomTokenL1 bridgedToken =
            new ReverseTestCustomTokenL1(address(l1Gateway), router);
        vm.prank(address(user));
        bridgedToken.mint();

        uint256 tooManyTokens = 500 ether;

        // register token to gateway
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(bridgedToken);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = makeAddr("tokenL2Address");

        vm.prank(owner);
        uint256 seqNum0 = L1CustomGateway(address(l1Gateway)).forceRegisterTokenToL2{
            value: retryableCost
        }(l1Tokens, l2Tokens, maxGas, gasPriceBid, maxSubmissionCost);

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

    function test_outboundTransferCustomRefund_revert_NoL2TokenSet() public virtual override {
        uint256 tooManyTokens = 500 ether;

        // register token to gateway
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(token);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = address(0);

        vm.prank(owner);
        L1CustomGateway(address(l1Gateway)).forceRegisterTokenToL2{value: retryableCost}(
            l1Tokens, l2Tokens, maxGas, gasPriceBid, maxSubmissionCost
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

    function test_outboundTransferCustomRefund_revert_Reentrancy() public override {
        // fund user with tokens
        MintableTestCustomTokenL1 bridgedToken =
            new ReverseTestCustomTokenL1(address(l1Gateway), router);
        vm.prank(address(user));
        bridgedToken.mint();

        // register token to gateway
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(bridgedToken);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = makeAddr("tokenL2Address");

        vm.prank(owner);
        L1CustomGateway(address(l1Gateway)).forceRegisterTokenToL2{value: retryableCost}(
            l1Tokens, l2Tokens, maxGas, gasPriceBid, maxSubmissionCost
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

    function test_registerTokenToL2(address, address l2Token) public virtual override {
        vm.expectRevert("REGISTER_TOKEN_ON_L2_DISABLED");
        L1CustomGateway(address(l1Gateway)).registerTokenToL2{value: retryableCost}(
            l2Token, maxGas, gasPriceBid, maxSubmissionCost
        );
    }

    function test_registerTokenToL2_CustomRefund(address, address) public virtual override {
        0; // N/A
    }

    function test_registerTokenToL2_UpdateToSameAddress(address, address) public virtual override {
        0; // N/A
    }

    function test_registerTokenToL2_revert_NoUpdateToDifferentAddress() public virtual override {
        0; // N/A
    }

    function test_registerTokenToL2_revert_NotArbEnabled() public virtual override {
        0; // N/A
    }
}
