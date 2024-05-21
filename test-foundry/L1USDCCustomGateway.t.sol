// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ArbitrumExtendedGateway.t.sol";
import {
    L1USDCCustomGateway,
    L2USDCCustomGateway
} from "contracts/tokenbridge/ethereum/gateway/L1USDCCustomGateway.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract L1USDCCustomGatewayTest is L1ArbitrumExtendedGatewayTest {
    L1USDCCustomGateway usdcGateway;
    address public owner = makeAddr("gw-owner");
    address public L1_USDC = address(new MockUsdc());
    address public L2_USDC = makeAddr("L2_USDC");

    function setUp() public virtual {
        inbox = address(new InboxMock());

        l1Gateway = new L1USDCCustomGateway();
        usdcGateway = L1USDCCustomGateway(payable(address(l1Gateway)));
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
        usdcGateway.pauseDeposits{value: retryableCost}(
            maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );

        vm.expectEmit(true, true, true, true);
        emit GatewayUsdcBurned(lockedAmount);

        /// burn USDC
        vm.prank(owner);
        usdcGateway.burnLockedUSDC();

        /// checks
        assertEq(ERC20(L1_USDC).balanceOf(address(usdcGateway)), 0, "Invalid USDC balance");
    }

    function test_burnLockedUSDC_revert_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        usdcGateway.burnLockedUSDC();
    }

    function test_burnLockedUSDC_revert_NotPaused() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                L1USDCCustomGateway.L1USDCCustomGateway_DepositsNotPaused.selector
            )
        );
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
        L1USDCCustomGateway gateway = new L1USDCCustomGateway();
        gateway.initialize(l2Gateway, router, inbox, L1_USDC, L2_USDC, owner);

        assertEq(gateway.counterpartGateway(), l2Gateway, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.inbox(), inbox, "Invalid inbox");
        assertEq(gateway.l1USDC(), L1_USDC, "Invalid L1_USDC");
        assertEq(gateway.l2USDC(), L2_USDC, "Invalid L2_USDC");
        assertEq(gateway.owner(), owner, "Invalid owner");
        assertEq(gateway.depositsPaused(), false, "Invalid depositPaused");
    }

    function test_finalizeInboundTransfer() public override {
        // TODO
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

    function test_outboundTransferCustomRefund() public {
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
        usdcGateway.pauseDeposits{value: retryableCost}(
            maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );

        vm.expectRevert(
            abi.encodeWithSelector(L1USDCCustomGateway.L1USDCCustomGateway_DepositsPaused.selector)
        );
        vm.prank(router);

        l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
            L1_USDC, creditBackAddress, user, 100, maxGas, gasPriceBid, ""
        );
    }

    function test_outboundTransferCustomRefund_revert_DepositsPaused() public {
        vm.deal(router, retryableCost);

        vm.prank(owner);
        usdcGateway.pauseDeposits{value: retryableCost}(
            maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );

        vm.expectRevert(
            abi.encodeWithSelector(L1USDCCustomGateway.L1USDCCustomGateway_DepositsPaused.selector)
        );
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

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(creditBackAddress, creditBackAddress);

        vm.expectEmit(true, true, true, true);
        emit InboxRetryableTicket(
            address(usdcGateway),
            l2Gateway,
            0,
            maxGas,
            abi.encodeWithSelector(L2USDCCustomGateway.pauseWithdrawals.selector)
        );

        /// pause it
        vm.prank(owner);
        usdcGateway.pauseDeposits{value: retryableCost}(
            maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );

        /// checks
        assertEq(usdcGateway.depositsPaused(), true, "Invalid depositPaused");
    }

    function test_pauseDeposits_revert_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        usdcGateway.pauseDeposits{value: retryableCost}(
            maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );
    }

    function test_pauseDeposits_revert_DepositsAlreadyPaused() public {
        vm.prank(owner);
        usdcGateway.pauseDeposits{value: retryableCost}(
            maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                L1USDCCustomGateway.L1USDCCustomGateway_DepositsAlreadyPaused.selector
            )
        );
        usdcGateway.pauseDeposits{value: retryableCost}(
            maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );
    }

    ////
    // Event declarations
    ////
    event DepositsPaused();
    event GatewayUsdcBurned(uint256 amount);

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
