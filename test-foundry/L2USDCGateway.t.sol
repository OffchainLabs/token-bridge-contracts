// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L2ArbitrumGateway.t.sol";

import {L2USDCGateway} from "contracts/tokenbridge/arbitrum/gateway/L2USDCGateway.sol";
import {L1USDCGateway} from "contracts/tokenbridge/ethereum/gateway/L1USDCGateway.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";
import {L2GatewayToken, IArbToken} from "contracts/tokenbridge/libraries/L2GatewayToken.sol";
import {IFiatTokenArbitrumOrbitV2_2} from
    "contracts/tokenbridge/test/IFiatTokenArbitrumOrbitV2_2.sol";
import {TestUtil} from "./util/TestUtil.sol";

contract L2USDCGatewayTest is L2ArbitrumGatewayTest {
    L2USDCGateway public l2USDCGateway;
    address public l1USDC = makeAddr("l1USDC");
    address public l2USDC;
    address public user = makeAddr("usdc_user");
    address public owner = makeAddr("l2gw-owner");
    address masterMinter = makeAddr("newMasterMinter");

    function setUp() public virtual {
        l2USDCGateway = new L2USDCGateway();
        l2Gateway = L2ArbitrumGateway(address(l2USDCGateway));

        address bridgedUsdcLogic = TestUtil.deployBridgedUsdcToken();
        l2USDC = TestUtil.deployProxy(bridgedUsdcLogic);
        IFiatTokenArbitrumOrbitV2_2(l2USDC).initialize(
            "USDC token",
            "USDC.e",
            "USD",
            uint8(6),
            masterMinter,
            makeAddr("newPauser"),
            makeAddr("newBlacklister"),
            owner
        );
        IFiatTokenArbitrumOrbitV2_2(l2USDC).initializeV2("USDC");
        IFiatTokenArbitrumOrbitV2_2(l2USDC).initializeV2_1(makeAddr("lostAndFound"));
        IFiatTokenArbitrumOrbitV2_2(l2USDC).initializeV2_2(new address[](0), "USDC.e");
        IFiatTokenArbitrumOrbitV2_2(l2USDC).initializeArbitrumOrbit(address(l2USDCGateway), l1USDC);

        vm.startPrank(masterMinter);
        IFiatTokenArbitrumOrbitV2_2(l2USDC).configureMinter(
            address(l2USDCGateway), type(uint256).max
        );
        vm.stopPrank();

        l2USDCGateway.initialize(l1Counterpart, router, l1USDC, l2USDC, owner);
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
        L2USDCGateway gateway = new L2USDCGateway();
        L2USDCGateway(gateway).initialize(l1Counterpart, router, l1USDC, l2USDC, owner);

        assertEq(gateway.counterpartGateway(), l1Counterpart, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.l1USDC(), l1USDC, "Invalid l1USDC");
        assertEq(gateway.l2USDC(), l2USDC, "Invalid l2USDC");
        assertEq(gateway.owner(), owner, "Invalid owner");
    }

    function test_initialize_revert_InvalidL1USDC() public {
        L2USDCGateway gateway = new L2USDCGateway();
        vm.expectRevert(abi.encodeWithSelector(L2USDCGateway.L2USDCGateway_InvalidL1USDC.selector));
        L2USDCGateway(gateway).initialize(l1Counterpart, router, address(0), l2USDC, owner);
    }

    function test_initialize_revert_InvalidL2USDC() public {
        L2USDCGateway gateway = new L2USDCGateway();
        vm.expectRevert(abi.encodeWithSelector(L2USDCGateway.L2USDCGateway_InvalidL2USDC.selector));
        L2USDCGateway(gateway).initialize(l1Counterpart, router, l1USDC, address(0), owner);
    }

    function test_initialize_revert_AlreadyInit() public {
        L2USDCGateway gateway = new L2USDCGateway();
        L2USDCGateway(gateway).initialize(l1Counterpart, router, l1USDC, l2USDC, owner);
        vm.expectRevert("ALREADY_INIT");
        L2USDCGateway(gateway).initialize(l1Counterpart, router, l1USDC, l2USDC, owner);
    }

    function test_initialize_revert_InvalidOwner() public {
        L2USDCGateway gateway = new L2USDCGateway();
        vm.expectRevert(abi.encodeWithSelector(L2USDCGateway.L2USDCGateway_InvalidOwner.selector));
        gateway.initialize(l1Counterpart, router, l1USDC, l2USDC, address(0));
    }

    function test_outboundTransfer() public override {
        // mint token to user
        deal(address(l2USDC), sender, 1 ether);

        // withdrawal params
        uint256 withdrawalAmount = 200_500;
        bytes memory data = new bytes(0);

        // mint some tokens so withdrawal can be successful
        vm.prank(address(l2USDCGateway));
        IArbToken(l2USDC).bridgeMint(sender, withdrawalAmount * 2);

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

        // mint some tokens so withdrawal can be successful
        vm.prank(address(l2USDCGateway));
        IArbToken(l2USDC).bridgeMint(sender, withdrawalAmount);

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
        vm.prank(owner);
        l2USDCGateway.pauseWithdrawals();

        vm.expectRevert(
            abi.encodeWithSelector(L2USDCGateway.L2USDCGateway_WithdrawalsPaused.selector)
        );
        l2USDCGateway.outboundTransfer(l1USDC, receiver, 200, 0, 0, new bytes(0));
    }

    function test_pauseWithdrawals() public {
        assertEq(l2USDCGateway.withdrawalsPaused(), false, "Invalid initial state");

        // events
        vm.expectEmit(true, true, true, true);
        emit WithdrawalsPaused();

        // pause withdrawals
        vm.prank(owner);
        l2USDCGateway.pauseWithdrawals();

        // checks
        assertEq(l2USDCGateway.withdrawalsPaused(), true, "Invalid initial state");
    }

    function test_pauseWithdrawals_revert_WithdrawalsAlreadyPaused() public {
        vm.startPrank(owner);
        l2USDCGateway.pauseWithdrawals();

        vm.expectRevert(
            abi.encodeWithSelector(L2USDCGateway.L2USDCGateway_WithdrawalsAlreadyPaused.selector)
        );
        l2USDCGateway.pauseWithdrawals();
    }

    function test_pauseWithdrawals_revert_NotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(L2USDCGateway.L2USDCGateway_NotOwner.selector));
        l2USDCGateway.pauseWithdrawals();
    }

    function test_setOwner() public {
        address newOwner = makeAddr("new-owner");
        vm.prank(owner);
        l2USDCGateway.setOwner(newOwner);

        assertEq(l2USDCGateway.owner(), newOwner, "Invalid owner");
    }

    function test_setOwner_revert_InvalidOwner() public {
        vm.expectRevert(abi.encodeWithSelector(L2USDCGateway.L2USDCGateway_InvalidOwner.selector));
        vm.prank(owner);
        l2USDCGateway.setOwner(address(0));
    }

    function test_setOwner_revert_NotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(L2USDCGateway.L2USDCGateway_NotOwner.selector));
        l2USDCGateway.setOwner(owner);
    }

    ////
    // Event declarations
    ////
    event WithdrawalsPaused();
}
