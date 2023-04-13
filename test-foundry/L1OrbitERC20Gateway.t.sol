// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { L1ERC20GatewayTest } from "./L1ERC20Gateway.t.sol";
import "contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol";

import { TestERC20 } from "contracts/tokenbridge/test/TestERC20.sol";
import { ERC20InboxMock } from "contracts/tokenbridge/test/InboxMock.sol";

contract L1OrbitERC20GatewayTest is L1ERC20GatewayTest {
    function setUp() public override {
        inbox = address(new ERC20InboxMock());

        l1Gateway = new L1OrbitERC20Gateway();
        L1OrbitERC20Gateway(address(l1Gateway)).initialize(
            l2Gateway,
            router,
            inbox,
            cloneableProxyHash,
            l2BeaconProxyFactory
        );

        token = IERC20(address(new TestERC20()));

        // fund user and router
        vm.prank(user);
        TestERC20(address(token)).mint();
        vm.deal(router, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public override {
        L1ERC20Gateway gateway = new L1OrbitERC20Gateway();
        gateway.initialize(l2Gateway, router, inbox, cloneableProxyHash, l2BeaconProxyFactory);

        assertEq(gateway.counterpartGateway(), l2Gateway, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.inbox(), inbox, "Invalid inbox");
        assertEq(gateway.l2BeaconProxyFactory(), l2BeaconProxyFactory, "Invalid beacon");
        assertEq(gateway.whitelist(), address(0), "Invalid whitelist");
    }

    function test_outboundTransfer() public override {
        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        // retryable params
        uint256 maxSubmissionCost = 0;
        uint256 maxGas = 1000000000;
        uint256 gasPrice = 3;

        uint256 depositAmount = 300;
        uint256 nativeTokenTotalFee = maxGas * gasPrice;

        bytes memory callHookData = "";
        bytes memory userEncodedData = abi.encode(
            maxSubmissionCost,
            callHookData,
            nativeTokenTotalFee
        );
        bytes memory routerEncodedData = abi.encode(user, userEncodedData);

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

        // expect events
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
            gasPrice,
            nativeTokenTotalFee,
            l1Gateway.getOutboundCalldata(address(token), user, user, 300, "")
        );

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(token), user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);
        l1Gateway.outboundTransfer(
            address(token),
            user,
            depositAmount,
            maxGas,
            gasPrice,
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
    }

    function test_outboundTransferCustomRefund() public override {
        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        // retryable params
        uint256 maxSubmissionCost = 0;
        uint256 maxGas = 200000000;
        uint256 gasPrice = 4;

        uint256 depositAmount = 700;
        uint256 nativeTokenTotalFee = maxGas * gasPrice;
        address refundTo = address(3000);

        bytes memory callHookData = "";
        bytes memory userEncodedData = abi.encode(
            maxSubmissionCost,
            callHookData,
            nativeTokenTotalFee
        );
        bytes memory routerEncodedData = abi.encode(user, userEncodedData);

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

        // expect events
        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(refundTo, user);

        vm.expectEmit(true, true, true, true);
        emit DepositInitiated(address(token), user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);
        l1Gateway.outboundTransferCustomRefund(
            address(token),
            refundTo,
            user,
            depositAmount,
            maxGas,
            gasPrice,
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
    }

    ////
    // Helper functions
    ////
    function buildRouterEncodedData(
        bytes memory callHookData
    ) internal view override returns (bytes memory) {
        uint256 nativeTokenTotalFee = 350;
        uint256 maxSubmissionCost = 20;

        bytes memory userEncodedData = abi.encode(
            maxSubmissionCost,
            callHookData,
            nativeTokenTotalFee
        );
        bytes memory routerEncodedData = abi.encode(user, userEncodedData);

        return routerEncodedData;
    }

    event ERC20InboxRetryableTicket(
        address from,
        address to,
        uint256 l2CallValue,
        uint256 maxGas,
        uint256 gasPrice,
        uint256 tokenTotalFeeAmount,
        bytes data
    );
}
