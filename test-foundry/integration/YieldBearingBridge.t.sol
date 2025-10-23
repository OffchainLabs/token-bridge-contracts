// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "../L1ArbitrumExtendedGateway.t.sol";
import "contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MasterVault } from "contracts/tokenbridge/libraries/vault/MasterVault.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxyFactory } from "contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";

contract YieldBearingBridgeTest is L1ArbitrumGatewayTest {
    // gateway params
    address public l2BeaconProxyFactory = makeAddr("l2BeaconProxyFactory");
    bytes32 public cloneableProxyHash =
        0x0000000000000000000000000000000000000000000000000000000000000001;

    MasterVault public masterVault;
    TestERC20 public underlyingToken;
    UpgradeableBeacon public beacon;
    BeaconProxyFactory public beaconProxyFactory;

    function setUp() public virtual {
        // fund router
        vm.deal(router, 100 ether);
        maxSubmissionCost = 70;
        retryableCost = maxSubmissionCost + gasPriceBid * maxGas;

        inbox = address(new InboxMock());

        l1Gateway = new L1ERC20Gateway();
        L1ERC20Gateway(address(l1Gateway)).initialize(
            l2Gateway,
            router,
            inbox,
            cloneableProxyHash,
            l2BeaconProxyFactory
        );

        // master vault setup
        underlyingToken = new TestERC20();
        MasterVault implementation = new MasterVault();
        beacon = new UpgradeableBeacon(address(implementation));
        beaconProxyFactory = new BeaconProxyFactory();
        beaconProxyFactory.initialize(address(beacon));

        bytes32 salt = keccak256("yieldBearingBridge");
        address proxyAddress = beaconProxyFactory.createProxy(salt);
        masterVault = MasterVault(proxyAddress);
        masterVault.initialize(
            IERC20(address(underlyingToken)),
            "Master Vault Token",
            "mvToken",
            address(this)
        );

        // bridging master vault shares
        token = IERC20(address(masterVault));

        // deposit underlying & move some master vault shares to gateway for withdrawal tests
        vm.startPrank(user);
        underlyingToken.mint();
        uint256 initialDeposit = underlyingToken.balanceOf(user);
        underlyingToken.approve(address(masterVault), initialDeposit);
        masterVault.deposit(initialDeposit, user, 0);
        token.transfer(address(l1Gateway), 100);
        vm.stopPrank();
    }

    function test_outboundTransfer() public virtual override {
        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        // retryable params
        uint256 depositAmount = 300;
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

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
        emit DepositInitiated(address(token), user, user, 0, depositAmount);

        // trigger deposit
        vm.prank(router);
        l1Gateway.outboundTransfer{ value: retryableCost }(
            address(token),
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
    }

    function test_finalizeInboundTransfer() public override {
        // fund gateway with master vault shares (for withdrawal test)
        // deposit more underlying tokens and mint shares to gateway
        vm.startPrank(user);
        underlyingToken.mint();
        uint256 depositAmount = underlyingToken.balanceOf(user);
        underlyingToken.approve(address(masterVault), depositAmount);
        masterVault.deposit(depositAmount, address(l1Gateway), 0);
        vm.stopPrank();

        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        // withdrawal params
        address from = address(3000);
        uint256 withdrawalAmount = 25;
        uint256 exitNum = 7;
        bytes memory callHookData = "";
        bytes memory data = abi.encode(exitNum, callHookData);

        InboxMock(address(inbox)).setL2ToL1Sender(l2Gateway);

        // trigger withdrawal
        vm.prank(address(IInbox(l1Gateway.inbox()).bridge()));
        l1Gateway.finalizeInboundTransfer(address(token), from, user, withdrawalAmount, data);

        // check tokens are properly released
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceAfter - userBalanceBefore, withdrawalAmount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = token.balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceBefore - l1GatewayBalanceAfter,
            withdrawalAmount,
            "Wrong l1 gateway balance"
        );
    }

    function test_getOutboundCalldata() public override {
        bytes memory outboundCalldata = l1Gateway.getOutboundCalldata({
            _token: address(token),
            _from: user,
            _to: address(800),
            _amount: 355,
            _data: abi.encode("doStuff()")
        });

        bytes memory expectedCalldata = abi.encodeWithSelector(
            ITokenGateway.finalizeInboundTransfer.selector,
            address(token),
            user,
            address(800),
            355,
            abi.encode(
                abi.encode(abi.encode("Master Vault Token"), abi.encode("mvToken"), abi.encode(18)),
                abi.encode("doStuff()")
            )
        );

        assertEq(outboundCalldata, expectedCalldata, "Invalid outboundCalldata");
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
    event InboxRetryableTicket(address from, address to, uint256 value, uint256 maxGas, bytes data);
}
