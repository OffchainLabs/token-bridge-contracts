// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ArbitrumExtendedGateway.t.sol";
import {
    L1USDCCustomGateway,
    L2USDCCustomGateway
} from "contracts/tokenbridge/ethereum/gateway/L1USDCCustomGateway.sol";

contract L1USDCCustomGatewayTest is L1ArbitrumExtendedGatewayTest {
    L1USDCCustomGateway usdcGateway;
    address public owner = makeAddr("gw-owner");
    address public L1_USDC = makeAddr("L1_USDC");
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

    function test_pauseDeposits() public {
        assertEq(usdcGateway.depositsPaused(), false, "Invalid depositPaused");

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

        vm.prank(owner);
        usdcGateway.pauseDeposits{value: retryableCost}(
            maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );

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
}
