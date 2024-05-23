// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L2ArbitrumGateway.t.sol";

import {L2USDCCustomGateway} from "contracts/tokenbridge/arbitrum/gateway/L2USDCCustomGateway.sol";
import {L1USDCCustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1USDCCustomGateway.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";
import {L2GatewayToken} from "contracts/tokenbridge/libraries/L2GatewayToken.sol";

contract L2USDCCustomGatewayTest is L2ArbitrumGatewayTest {
    L2USDCCustomGateway public l2USDCGateway;
    address public l1USDC = makeAddr("l1USDC");
    address public l2USDC;
    address public user = makeAddr("usdc_user");

    function setUp() public virtual {
        l2USDCGateway = new L2USDCCustomGateway();
        l2Gateway = L2ArbitrumGateway(address(l2USDCGateway));

        l2USDC = address(new L2USDC(address(l2USDCGateway), l1USDC));
        l2USDCGateway.initialize(l1Counterpart, router, l1USDC, l2USDC);

        console.log(l2USDCGateway.counterpartGateway());
    }

    /* solhint-disable func-name-mixedcase */

    function test_calculateL2TokenAddress() public {
        assertEq(l2USDCGateway.calculateL2TokenAddress(l1USDC), l2USDC, "Invalid address");
    }

    function test_calculateL2TokenAddress_NotUSDC() public {
        address randomToken = makeAddr("randomToken");
        assertEq(l2USDCGateway.calculateL2TokenAddress(randomToken), address(0), "Invalid address");
    }

    function test_finalizeInboundTransfer() public override {
        vm.deal(address(l2USDCGateway), 100 ether);

        /// events
        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(l1USDC, sender, receiver, amount);

        /// finalize deposit
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2USDCGateway.finalizeInboundTransfer(
            l1USDC, sender, receiver, amount, abi.encode(new bytes(0), new bytes(0))
        );

        /// check tokens have been minted to receiver
        assertEq(ERC20(l2USDC).balanceOf(receiver), amount, "Invalid receiver balance");
    }

    function test_finalizeInboundTransfer_WithCallHook() public override {
        vm.deal(address(l2USDCGateway), 100 ether);

        /// events
        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(l1USDC, sender, receiver, amount);

        /// finalize deposit
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2USDCGateway.finalizeInboundTransfer(
            l1USDC, sender, receiver, amount, abi.encode(new bytes(0), new bytes(0x1))
        );

        /// check tokens have been minted to receiver
        assertEq(ERC20(l2USDC).balanceOf(receiver), amount, "Invalid receiver balance");
    }

    function test_finalizeInboundTransfer_ShouldHalt() public {
        address notl1USDC = makeAddr("notl1USDC");

        // check that withdrawal is triggered occurs when deposit is halted
        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(notl1USDC, address(l2USDCGateway), sender, 0, 0, amount);

        vm.deal(address(l2USDCGateway), 100 ether);

        /// finalize deposit
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2USDCGateway.finalizeInboundTransfer(
            notl1USDC, sender, receiver, amount, abi.encode(new bytes(0), new bytes(0))
        );
    }

    function test_initialize() public {
        L2USDCCustomGateway gateway = new L2USDCCustomGateway();
        L2USDCCustomGateway(gateway).initialize(l1Counterpart, router, l1USDC, l2USDC);

        assertEq(gateway.counterpartGateway(), l1Counterpart, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.l1USDC(), l1USDC, "Invalid l1USDC");
        assertEq(gateway.l2USDC(), l2USDC, "Invalid l2USDC");
    }

    function test_initialize_revert_InvalidL1USDC() public {
        L2USDCCustomGateway gateway = new L2USDCCustomGateway();
        vm.expectRevert(
            abi.encodeWithSelector(L2USDCCustomGateway.L2USDCCustomGateway_InvalidL1USDC.selector)
        );
        L2USDCCustomGateway(gateway).initialize(l1Counterpart, router, address(0), l2USDC);
    }

    function test_initialize_revert_InvalidL2USDC() public {
        L2USDCCustomGateway gateway = new L2USDCCustomGateway();
        vm.expectRevert(
            abi.encodeWithSelector(L2USDCCustomGateway.L2USDCCustomGateway_InvalidL2USDC.selector)
        );
        L2USDCCustomGateway(gateway).initialize(l1Counterpart, router, l1USDC, address(0));
    }

    function test_initialize_revert_AlreadyInit() public {
        L2USDCCustomGateway gateway = new L2USDCCustomGateway();
        L2USDCCustomGateway(gateway).initialize(l1Counterpart, router, l1USDC, l2USDC);
        vm.expectRevert("ALREADY_INIT");
        L2USDCCustomGateway(gateway).initialize(l1Counterpart, router, l1USDC, l2USDC);
    }

    function test_outboundTransfer() public override {
        // mint token to user
        deal(address(l2USDC), sender, 1 ether);

        // withdrawal params
        uint256 withdrawalAmount = 200_500;
        bytes memory data = new bytes(0);

        // events
        uint256 expectedId = 0;
        bytes memory expectedData =
            l2USDCGateway.getOutboundCalldata(l1USDC, sender, receiver, withdrawalAmount, data);
        vm.expectEmit(true, true, true, true);
        emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1USDC, sender, receiver, expectedId, 0, withdrawalAmount);

        // withdraw
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(sender);
        l2USDCGateway.outboundTransfer(l1USDC, receiver, withdrawalAmount, 0, 0, data);
    }

    function test_outboundTransfer_4Args() public override {
        // mint token to user
        deal(address(l2USDC), sender, 1 ether);

        // withdrawal params
        uint256 withdrawalAmount = 200_500;
        bytes memory data = new bytes(0);

        // events
        uint256 expectedId = 0;
        bytes memory expectedData =
            l2USDCGateway.getOutboundCalldata(l1USDC, sender, receiver, withdrawalAmount, data);
        vm.expectEmit(true, true, true, true);
        emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1USDC, sender, receiver, expectedId, 0, withdrawalAmount);

        // withdraw
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(sender);
        l2USDCGateway.outboundTransfer(l1USDC, receiver, withdrawalAmount, data);
    }

    function test_outboundTransfer_revert_NotExpectedL1Token() public override {
        // mock invalid L1 token ref
        address notl1USDC = makeAddr("notl1USDC");
        vm.mockCall(address(l2USDC), abi.encodeWithSignature("l1Address()"), abi.encode(notl1USDC));

        vm.expectRevert("NOT_EXPECTED_L1_TOKEN");
        l2USDCGateway.outboundTransfer(l1USDC, address(101), 200, 0, 0, new bytes(0));
    }

    function test_outboundTransfer_revert_WithdrawalsPaused() public {
        // pause withdrawals
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2USDCGateway.pauseWithdrawals();

        vm.expectRevert(
            abi.encodeWithSelector(
                L2USDCCustomGateway.L2USDCCustomGateway_WithdrawalsPaused.selector
            )
        );
        l2USDCGateway.outboundTransfer(l1USDC, receiver, 200, 0, 0, new bytes(0));
    }

    function test_pauseWithdrawals() public {
        assertEq(l2USDCGateway.withdrawalsPaused(), false, "Invalid initial state");

        // events
        vm.expectEmit(true, true, true, true);
        emit WithdrawalsPaused();

        // pause withdrawals
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2USDCGateway.pauseWithdrawals();

        // checks
        assertEq(l2USDCGateway.withdrawalsPaused(), true, "Invalid initial state");
    }

    function test_pauseWithdrawals_revert_WithdrawalsAlreadyPaused() public {
        vm.startPrank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2USDCGateway.pauseWithdrawals();

        vm.expectRevert(
            abi.encodeWithSelector(
                L2USDCCustomGateway.L2USDCCustomGateway_WithdrawalsAlreadyPaused.selector
            )
        );
        l2USDCGateway.pauseWithdrawals();
    }

    function test_pauseWithdrawals_revert_OnlyCounterpartGateway() public {
        vm.expectRevert("ONLY_COUNTERPART_GATEWAY");
        l2USDCGateway.pauseWithdrawals();
    }

    ////
    // Event declarations
    ////
    event WithdrawalsPaused();
}

contract L2USDC is L2GatewayToken {
    constructor(address l2USDCGateway, address l1USDC) {
        L2GatewayToken._initialize("L2 USDC", "USDC", 18, l2USDCGateway, l1USDC);
    }
}
