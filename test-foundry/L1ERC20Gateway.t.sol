// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ArbitrumExtendedGateway.t.sol";
import "contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract L1ERC20GatewayTest is L1ArbitrumExtendedGatewayTest {
    // gateway params
    address public l2BeaconProxyFactory = makeAddr("l2BeaconProxyFactory");
    bytes32 public cloneableProxyHash =
        0x0000000000000000000000000000000000000000000000000000000000000001;

    function setUp() public virtual {
        inbox = address(new InboxMock());

        l1Gateway = new L1ERC20Gateway();
        L1ERC20Gateway(address(l1Gateway)).initialize(
            l2Gateway, router, inbox, cloneableProxyHash, l2BeaconProxyFactory
        );

        token = IERC20(address(new TestERC20()));

        maxSubmissionCost = 70;
        retryableCost = maxSubmissionCost + gasPriceBid * maxGas;

        // fund user and router
        vm.prank(user);
        TestERC20(address(token)).mint();
        vm.deal(router, 100 ether);

        // move some funds to gateway
        vm.prank(user);
        token.transfer(address(l1Gateway), 100);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public virtual {
        L1ERC20Gateway gateway = new L1ERC20Gateway();
        gateway.initialize(l2Gateway, router, inbox, cloneableProxyHash, l2BeaconProxyFactory);

        assertEq(gateway.counterpartGateway(), l2Gateway, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.inbox(), inbox, "Invalid inbox");
        assertEq(gateway.l2BeaconProxyFactory(), l2BeaconProxyFactory, "Invalid beacon");
        assertEq(gateway.whitelist(), address(0), "Invalid whitelist");
    }

    function test_initialize_revert_BadInbox() public {
        L1ERC20Gateway gateway = new L1ERC20Gateway();
        address badInbox = address(0);

        vm.expectRevert("BAD_INBOX");
        gateway.initialize(l2Gateway, router, badInbox, cloneableProxyHash, l2BeaconProxyFactory);
    }

    function test_initialize_revert_BadRouter() public {
        L1ERC20Gateway gateway = new L1ERC20Gateway();
        address badRouter = address(0);

        vm.expectRevert("BAD_ROUTER");
        gateway.initialize(l2Gateway, badRouter, inbox, cloneableProxyHash, l2BeaconProxyFactory);
    }

    function test_initialize_revert_InvalidProxyHash() public {
        L1ERC20Gateway gateway = new L1ERC20Gateway();
        bytes32 invalidProxyHash = bytes32(0);

        vm.expectRevert("INVALID_PROXYHASH");
        gateway.initialize(l2Gateway, router, inbox, invalidProxyHash, l2BeaconProxyFactory);
    }

    function test_initialize_revert_InvalidBeacon() public {
        L1ERC20Gateway gateway = new L1ERC20Gateway();
        address invalidBeaconProxyFactory = address(0);

        vm.expectRevert("INVALID_BEACON");
        gateway.initialize(l2Gateway, router, inbox, cloneableProxyHash, invalidBeaconProxyFactory);
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
        l1Gateway.outboundTransfer{value: retryableCost}(
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
    }

    function test_outboundTransferCustomRefund() public virtual {
        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        // retryable params
        uint256 depositAmount = 450;
        address refundTo = address(2000);
        bytes memory callHookData = "";
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        // approve token
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

        // event checkers
        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(refundTo, user);

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
        l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
            address(token), refundTo, user, depositAmount, maxGas, gasPriceBid, routerEncodedData
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

    function test_outboundTransferCustomRefund_revert_InsufficientAllowance() public {
        uint256 tooManyTokens = 500 ether;

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

    function test_outboundTransferCustomRefund_revert_Reentrancy() public virtual {
        // approve token
        uint256 depositAmount = 3;
        vm.prank(user);
        token.approve(address(l1Gateway), depositAmount);

        // trigger re-entrancy
        MockReentrantInbox mockReentrantInbox = new MockReentrantInbox();
        vm.etch(l1Gateway.inbox(), address(mockReentrantInbox).code);

        vm.expectRevert("ReentrancyGuard: reentrant call");
        vm.prank(router);
        l1Gateway.outboundTransferCustomRefund{value: retryableCost}(
            address(token),
            makeAddr("refundTo"),
            user,
            depositAmount,
            maxGas,
            gasPriceBid,
            buildRouterEncodedData("")
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
                abi.encode(abi.encode("IntArbTestToken"), abi.encode("IARB"), abi.encode(18)),
                abi.encode("doStuff()")
            )
        );

        assertEq(outboundCalldata, expectedCalldata, "Invalid outboundCalldata");
    }

    function test_calculateL2TokenAddress(address tokenAddress) public {
        address l2TokenAddress = l1Gateway.calculateL2TokenAddress(tokenAddress);

        address expectedL2TokenAddress = Create2.computeAddress(
            keccak256(abi.encode(l2Gateway, keccak256(abi.encode(tokenAddress)))),
            cloneableProxyHash,
            l2BeaconProxyFactory
        );

        assertEq(l2TokenAddress, expectedL2TokenAddress, "Invalid calculateL2TokenAddress");
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
