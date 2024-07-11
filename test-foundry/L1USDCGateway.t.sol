// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ArbitrumExtendedGateway.t.sol";
import {L1USDCGateway} from "contracts/tokenbridge/ethereum/gateway/L1USDCGateway.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract L1USDCGatewayTest is L1ArbitrumExtendedGatewayTest {
    L1USDCGateway usdcGateway;
    address public owner = makeAddr("gw-owner");
    address public L1_USDC = address(new MockUsdc());
    address public L2_USDC = makeAddr("L2_USDC");

    function setUp() public virtual {
        inbox = address(new InboxMock());
        InboxMock(inbox).setL2ToL1Sender(l2Gateway);

        l1Gateway = new L1USDCGateway();
        usdcGateway = L1USDCGateway(payable(address(l1Gateway)));
        usdcGateway.initialize(l2Gateway, router, inbox, L1_USDC, L2_USDC, owner);

        maxSubmissionCost = 4000;
        retryableCost = maxSubmissionCost + gasPriceBid * maxGas;

        vm.deal(owner, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_burnLockedUSDC() public {
        /// add some USDC to the gateway
        uint256 lockedAmount = 234 ether;
        deal(L1_USDC, address(usdcGateway), lockedAmount);
        assertEq(
            ERC20(L1_USDC).balanceOf(address(usdcGateway)), lockedAmount, "Invalid USDC balance"
        );

        /// pause deposits
        vm.prank(owner);
        usdcGateway.pauseDeposits();

        /// set burner
        address burner = makeAddr("burner");
        vm.prank(owner);
        usdcGateway.setBurner(burner);

        /// set burn amount
        vm.prank(owner);
        uint256 l2Supply = lockedAmount - 100;
        usdcGateway.setBurnAmount(l2Supply);

        vm.expectEmit(true, true, true, true);
        emit GatewayUsdcBurned(l2Supply);

        /// burn USDC
        vm.prank(burner);
        usdcGateway.burnLockedUSDC();

        /// checks
        assertEq(
            ERC20(L1_USDC).balanceOf(address(usdcGateway)),
            lockedAmount - l2Supply,
            "Invalid USDC balance"
        );
    }

    function test_burnLockedUSDC_revert_NotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_NotBurner.selector));
        usdcGateway.burnLockedUSDC();
    }

    function test_burnLockedUSDC_revert_NotPaused() public {
        /// set burner
        address burner = makeAddr("burner");
        vm.prank(owner);
        usdcGateway.setBurner(burner);

        vm.prank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_DepositsNotPaused.selector)
        );
        usdcGateway.burnLockedUSDC();
    }

    function test_burnLockedUSDC_revert_BurnAmountNotSet() public {
        /// add some USDC to the gateway
        uint256 lockedAmount = 234 ether;
        deal(L1_USDC, address(usdcGateway), lockedAmount);

        /// pause deposits
        vm.prank(owner);
        usdcGateway.pauseDeposits();

        /// set burner
        address burner = makeAddr("burner");
        vm.prank(owner);
        usdcGateway.setBurner(burner);

        vm.expectRevert(
            abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_BurnAmountNotSet.selector)
        );
        vm.prank(burner);
        usdcGateway.burnLockedUSDC();
    }

    function test_calculateL2TokenAddress() public {
        assertEq(l1Gateway.calculateL2TokenAddress(L1_USDC), L2_USDC, "Invalid usdc address");
    }

    function test_calculateL2TokenAddress_NotUSDC() public {
        address randomToken = makeAddr("randomToken");
        assertEq(l1Gateway.calculateL2TokenAddress(randomToken), address(0), "Invalid usdc address");
    }

    function test_initialize() public {
        L1USDCGateway gateway = new L1USDCGateway();
        gateway.initialize(l2Gateway, router, inbox, L1_USDC, L2_USDC, owner);

        assertEq(gateway.counterpartGateway(), l2Gateway, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.inbox(), inbox, "Invalid inbox");
        assertEq(gateway.l1USDC(), L1_USDC, "Invalid L1_USDC");
        assertEq(gateway.l2USDC(), L2_USDC, "Invalid L2_USDC");
        assertEq(gateway.owner(), owner, "Invalid owner");
        assertEq(gateway.depositsPaused(), false, "Invalid depositPaused");
        assertEq(gateway.burner(), address(0), "Invalid burner");
    }

    function test_initialize_revert_InvalidL1USDC() public {
        L1USDCGateway gateway = new L1USDCGateway();
        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_InvalidL1USDC.selector));
        gateway.initialize(l2Gateway, router, inbox, address(0), L2_USDC, owner);
    }

    function test_initialize_revert_InvalidL2USDC() public {
        L1USDCGateway gateway = new L1USDCGateway();
        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_InvalidL2USDC.selector));
        gateway.initialize(l2Gateway, router, inbox, L1_USDC, address(0), owner);
    }

    function test_initialize_revert_InvalidOwner() public {
        L1USDCGateway gateway = new L1USDCGateway();
        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_InvalidOwner.selector));
        gateway.initialize(l2Gateway, router, inbox, L1_USDC, L2_USDC, address(0));
    }

    function test_initialize_revert_AlreadyInit() public {
        L1USDCGateway gateway = new L1USDCGateway();
        gateway.initialize(l2Gateway, router, inbox, L1_USDC, L2_USDC, owner);
        vm.expectRevert("ALREADY_INIT");
        gateway.initialize(l2Gateway, router, inbox, L1_USDC, L2_USDC, owner);
    }

    function test_finalizeInboundTransfer() public override {
        uint256 withdrawalAmount = 100_000_000;
        deal(L1_USDC, address(l1Gateway), withdrawalAmount);

        // snapshot state before
        uint256 userBalanceBefore = ERC20(L1_USDC).balanceOf(user);
        uint256 l1GatewayBalanceBefore = ERC20(L1_USDC).balanceOf(address(l1Gateway));

        // withdrawal params
        address from = address(3000);
        uint256 exitNum = 7;
        bytes memory callHookData = "";
        bytes memory data = abi.encode(exitNum, callHookData);

        InboxMock(address(inbox)).setL2ToL1Sender(l2Gateway);

        // trigger withdrawal
        vm.prank(address(IInbox(l1Gateway.inbox()).bridge()));
        l1Gateway.finalizeInboundTransfer(L1_USDC, from, user, withdrawalAmount, data);

        // check tokens are properly released
        uint256 userBalanceAfter = ERC20(L1_USDC).balanceOf(user);
        assertEq(userBalanceAfter - userBalanceBefore, withdrawalAmount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = ERC20(L1_USDC).balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceBefore - l1GatewayBalanceAfter,
            withdrawalAmount,
            "Wrong l1 gateway balance"
        );
    }

    function test_outboundTransfer() public virtual override {
        // fund user
        uint256 depositAmount = 300_555;
        deal(L1_USDC, user, depositAmount);
        vm.deal(router, retryableCost);

        // snapshot state before
        uint256 userBalanceBefore = ERC20(L1_USDC).balanceOf(user);
        uint256 l1GatewayBalanceBefore = ERC20(L1_USDC).balanceOf(address(l1Gateway));

        // approve token
        vm.prank(user);
        ERC20(L1_USDC).approve(address(l1Gateway), depositAmount);

        // prepare data
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

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
            l1Gateway.getOutboundCalldata(L1_USDC, user, user, depositAmount, callHookData)
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(L1_USDC, user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);
        bytes memory seqNum0 = l1Gateway.outboundTransfer{value: retryableCost}(
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

        assertEq(seqNum0, abi.encode(0), "Invalid seqNum0");
    }

    function test_outboundTransferCustomRefund() public virtual {
        // fund user
        uint256 depositAmount = 5_500_000_555;
        deal(L1_USDC, user, depositAmount);
        vm.deal(router, retryableCost);

        // snapshot state before
        uint256 userBalanceBefore = ERC20(L1_USDC).balanceOf(user);
        uint256 l1GatewayBalanceBefore = ERC20(L1_USDC).balanceOf(address(l1Gateway));

        // approve token
        vm.prank(user);
        ERC20(L1_USDC).approve(address(l1Gateway), depositAmount);

        // prepare data
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

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
            l1Gateway.getOutboundCalldata(L1_USDC, user, user, depositAmount, callHookData)
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(L1_USDC, user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);
        bytes memory seqNum0 = l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
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

        assertEq(seqNum0, abi.encode(0), "Invalid seqNum0");
    }

    function test_outboundTransfer_revert_DepositsPaused() public {
        vm.deal(router, retryableCost);

        vm.prank(owner);
        usdcGateway.pauseDeposits();

        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_DepositsPaused.selector));
        vm.prank(router);

        l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
            L1_USDC, creditBackAddress, user, 100, maxGas, gasPriceBid, ""
        );
    }

    function test_outboundTransferCustomRefund_revert_DepositsPaused() public {
        vm.deal(router, retryableCost);

        vm.prank(owner);
        usdcGateway.pauseDeposits();

        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_DepositsPaused.selector));
        vm.prank(router);

        l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
            L1_USDC, creditBackAddress, user, 200, maxGas, gasPriceBid, ""
        );
    }

    function test_pauseDeposits() public {
        assertEq(usdcGateway.depositsPaused(), false, "Invalid depositPaused");

        /// expect events
        vm.expectEmit(true, true, true, true);
        emit DepositsPaused();

        /// pause it
        vm.prank(owner);
        usdcGateway.pauseDeposits();

        /// checks
        assertEq(usdcGateway.depositsPaused(), true, "Invalid depositPaused");
    }

    function test_pauseDeposits_revert_NotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_NotOwner.selector));
        usdcGateway.pauseDeposits();
    }

    function test_pauseDeposits_revert_DepositsAlreadyPaused() public {
        vm.prank(owner);
        usdcGateway.pauseDeposits();

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_DepositsAlreadyPaused.selector)
        );
        usdcGateway.pauseDeposits();
    }

    function test_setBurner() public {
        address newBurner = makeAddr("new-burner");
        vm.expectEmit(true, true, true, true);
        emit BurnerSet(newBurner);

        vm.prank(owner);
        usdcGateway.setBurner(newBurner);

        assertEq(usdcGateway.burner(), newBurner, "Invalid burner");
    }

    function test_setBurner_revert_NotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_NotOwner.selector));
        usdcGateway.setBurner(address(0));
    }

    function test_setBurnAmount() public {
        uint256 amount = 100;

        vm.expectEmit(true, true, true, true);
        emit BurnAmountSet(amount);

        vm.prank(owner);
        usdcGateway.setBurnAmount(amount);

        assertEq(usdcGateway.burnAmount(), amount, "Invalid burnAmount");
    }

    function test_setBurnAmount_revert_NotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_NotOwner.selector));
        usdcGateway.setBurnAmount(100);
    }

    function test_setOwner() public {
        address newOwner = makeAddr("new-owner");
        vm.prank(owner);
        usdcGateway.setOwner(newOwner);

        assertEq(usdcGateway.owner(), newOwner, "Invalid owner");
    }

    function test_setOwner_revert_InvalidOwner() public {
        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_InvalidOwner.selector));
        vm.prank(owner);
        usdcGateway.setOwner(address(0));
    }

    function test_setOwner_revert_NotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_NotOwner.selector));
        usdcGateway.setOwner(owner);
    }

    function test_unpauseDeposits() public {
        vm.prank(owner);
        usdcGateway.pauseDeposits();
        assertEq(usdcGateway.depositsPaused(), true, "Invalid depositPaused");

        vm.expectEmit(true, true, true, true);
        emit DepositsUnpaused();

        vm.prank(owner);
        usdcGateway.unpauseDeposits();

        assertEq(usdcGateway.depositsPaused(), false, "Invalid depositPaused");
    }

    function test_unpauseDeposits_revert_NotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_NotOwner.selector));
        usdcGateway.unpauseDeposits();
    }

    function test_unpauseDeposits_revert_DepositsAlreadyUnpaused() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(L1USDCGateway.L1USDCGateway_DepositsAlreadyUnpaused.selector)
        );
        usdcGateway.unpauseDeposits();
    }

    ////
    // Event declarations
    ////
    event DepositsPaused();
    event DepositsUnpaused();
    event GatewayUsdcBurned(uint256 amount);
    event BurnerSet(address indexed burner);
    event BurnAmountSet(uint256 amount);

    event TicketData(uint256 maxSubmissionCost);
    event RefundAddresses(address excessFeeRefundAddress, address callValueRefundAddress);
    event InboxRetryableTicket(address from, address to, uint256 value, uint256 maxGas, bytes data);
    event DepositInitiated(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _sequenceNumber,
        uint256 _amount
    );
}

contract MockUsdc is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }
}
