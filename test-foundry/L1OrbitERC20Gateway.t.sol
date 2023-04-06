// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import "contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol";

import { TestERC20 } from "contracts/tokenbridge/test/TestERC20.sol";
import { ERC20InboxMock } from "contracts/tokenbridge/test/InboxMock.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract L1OrbitERC20GatewayTest is Test {
    IL1ArbitrumGateway public l1Gateway;
    IERC20 public token;

    // gateway params
    address public l2Gateway = address(1000);
    address public router = address(1001);
    address public inbox = address(new ERC20InboxMock());
    address public l2BeaconProxyFactory = address(1003);
    bytes32 public cloneableProxyHash =
        0x0000000000000000000000000000000000000000000000000000000000000001;

    address public user = address(1004);

    function setUp() public {
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
    function test_initialize() public {
        assertEq(
            L1OrbitERC20Gateway(address(l1Gateway)).counterpartGateway(),
            l2Gateway,
            "Invalid counterpartGateway"
        );
        assertEq(L1OrbitERC20Gateway(address(l1Gateway)).router(), router, "Invalid router");
        assertEq(l1Gateway.inbox(), inbox, "Invalid inbox");
        assertEq(
            L1OrbitERC20Gateway(address(l1Gateway)).l2BeaconProxyFactory(),
            l2BeaconProxyFactory,
            "Invalid l2BeaconProxyFactory"
        );
        assertEq(
            L1OrbitERC20Gateway(address(l1Gateway)).whitelist(),
            address(0),
            "Invalid whitelist"
        );
    }

    function test_outboundTransfer() public {
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
            nativeTokenTotalFee,
            callHookData
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

    ////
    // Event declarations
    ////
    event DepositInitiated(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _sequenceNumber,
        uint256 _amount
    );
    event TicketData(uint256 maxSubmissionCost);
    event RefundAddresses(address excessFeeRefundAddress, address callValueRefundAddress);
}
