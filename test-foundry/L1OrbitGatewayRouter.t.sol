// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {L1GatewayRouterTest} from "./L1GatewayRouter.t.sol";
import {ERC20InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";
import {L1OrbitERC20Gateway} from "contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol";
import {L1OrbitGatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1OrbitGatewayRouter.sol";
import {L2GatewayRouter} from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import {L1GatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import {L1OrbitCustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1OrbitCustomGateway.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20PresetMinterPauser} from
    "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import "forge-std/console.sol";

contract L1OrbitGatewayRouterTest is L1GatewayRouterTest {
    L1OrbitGatewayRouter public l1OrbitRouter;
    ERC20 public nativeToken;
    uint256 public nativeTokenTotalFee;

    function setUp() public override {
        inbox = address(new ERC20InboxMock());
        nativeToken = ERC20(address(new ERC20PresetMinterPauser("X", "Y")));
        ERC20PresetMinterPauser(address(nativeToken)).mint(user, 1_000_000 ether);
        ERC20PresetMinterPauser(address(nativeToken)).mint(owner, 1_000_000 ether);
        ERC20InboxMock(inbox).setMockNativeToken(address(nativeToken));

        defaultGateway = address(new L1OrbitERC20Gateway());

        router = new L1OrbitGatewayRouter();
        l1Router = L1GatewayRouter(address(router));
        l1OrbitRouter = L1OrbitGatewayRouter(address(router));
        l1OrbitRouter.initialize(owner, defaultGateway, address(0), counterpartGateway, inbox);

        maxSubmissionCost = 0;
        nativeTokenTotalFee = gasPriceBid * maxGas;

        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_getGateway_CustomGateway() public override {
        address token = makeAddr("some token");

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        address[] memory gateways = new address[](1);
        gateways[0] = address(new L1OrbitERC20Gateway());

        vm.startPrank(owner);
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);
        l1OrbitRouter.setGateways(
            tokens, gateways, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        address gateway = router.getGateway(token);
        assertEq(gateway, gateways[0], "Invalid gateway");
    }

    function test_getGateway_DisabledGateway() public override {
        address token = makeAddr("some token");

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        address[] memory gateways = new address[](1);
        gateways[0] = address(1);

        vm.startPrank(owner);
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);
        l1OrbitRouter.setGateways(
            tokens, gateways, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        address gateway = router.getGateway(token);
        assertEq(gateway, address(0), "Invalid gateway");
    }

    function test_outboundTransfer() public override {
        // init default gateway
        L1OrbitERC20Gateway(defaultGateway).initialize(
            makeAddr("defaultGatewayCounterpart"),
            address(l1Router),
            inbox,
            0x0000000000000000000000000000000000000000000000000000000000000001,
            makeAddr("l2BeaconProxyFactory")
        );

        // set default gateway
        vm.startPrank(owner);
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);
        l1OrbitRouter.setDefaultGateway(
            address(defaultGateway), maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );
        vm.stopPrank();

        // create token
        ERC20PresetMinterPauser token = new ERC20PresetMinterPauser("X", "Y");
        token.mint(user, 10_000);

        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(defaultGateway));
        uint256 userNativeTokenBalanceBefore = nativeToken.balanceOf(user);

        /// deposit data
        uint256 amount = 103;
        address to = address(401);
        bytes memory userEncodedData = abi.encode(maxSubmissionCost, "", nativeTokenTotalFee);

        /// approve tokens
        vm.prank(user);
        token.approve(address(defaultGateway), amount);

        // approve fees
        vm.prank(user);
        nativeToken.approve(address(defaultGateway), nativeTokenTotalFee);

        // expect event
        vm.expectEmit(true, true, true, true);
        emit TransferRouted(address(token), user, to, address(defaultGateway));

        /// deposit it
        vm.prank(user);
        l1Router.outboundTransfer(address(token), to, amount, maxGas, gasPriceBid, userEncodedData);

        // check tokens are escrowed
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, amount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = token.balanceOf(address(defaultGateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore, amount, "Wrong defaultGateway balance"
        );

        uint256 userNativeTokenBalanceAfter = nativeToken.balanceOf(user);
        assertEq(
            userNativeTokenBalanceBefore - userNativeTokenBalanceAfter,
            nativeTokenTotalFee,
            "Wrong user native token balance"
        );
    }

    function test_outboundTransfer_revert_NotAllowedToBridgeFeeToken() public {
        // init default gateway
        L1OrbitERC20Gateway(defaultGateway).initialize(
            makeAddr("defaultGatewayCounterpart"),
            address(l1Router),
            inbox,
            0x0000000000000000000000000000000000000000000000000000000000000001,
            makeAddr("l2BeaconProxyFactory")
        );

        // set default gateway
        vm.startPrank(owner);
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);
        l1OrbitRouter.setDefaultGateway(
            address(defaultGateway), maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );
        vm.stopPrank();

        /// deposit it
        vm.prank(user);
        vm.expectRevert("NOT_ALLOWED_TO_BRIDGE_FEE_TOKEN");
        l1Router.outboundTransfer(address(nativeToken), user, 100, maxGas, gasPriceBid, "");
    }

    function test_outboundTransferCustomRefund() public override {
        // init default gateway
        L1OrbitERC20Gateway(defaultGateway).initialize(
            makeAddr("defaultGatewayCounterpart"),
            address(l1Router),
            inbox,
            0x0000000000000000000000000000000000000000000000000000000000000001,
            makeAddr("l2BeaconProxyFactory")
        );

        // set default gateway
        vm.startPrank(owner);
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);
        l1OrbitRouter.setDefaultGateway(
            address(defaultGateway), maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );
        vm.stopPrank();

        // create token
        ERC20PresetMinterPauser token = new ERC20PresetMinterPauser("X", "Y");
        token.mint(user, 10_000);

        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(defaultGateway));
        uint256 userNativeTokenBalanceBefore = nativeToken.balanceOf(user);

        /// deposit data
        address refundTo = address(400);
        address to = address(401);
        uint256 amount = 103;
        bytes memory userEncodedData = abi.encode(maxSubmissionCost, "", nativeTokenTotalFee);

        // approve fees
        vm.prank(user);
        nativeToken.approve(defaultGateway, nativeTokenTotalFee);

        // approve tokens
        vm.prank(user);
        token.approve(defaultGateway, amount);

        // expect event
        vm.expectEmit(true, true, true, true);
        emit TransferRouted(address(token), user, to, address(defaultGateway));

        /// deposit it
        vm.prank(user);
        l1Router.outboundTransferCustomRefund(
            address(token), refundTo, to, amount, maxGas, gasPriceBid, userEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, amount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = token.balanceOf(address(defaultGateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore, amount, "Wrong defaultGateway balance"
        );

        uint256 userNativeTokenBalanceAfter = nativeToken.balanceOf(user);
        assertEq(
            userNativeTokenBalanceBefore - userNativeTokenBalanceAfter,
            nativeTokenTotalFee,
            "Wrong user native token balance"
        );
    }

    function test_outboundTransferCustomRefund_revert_NotAllowedToBridgeFeeToken() public {
        // init default gateway
        L1OrbitERC20Gateway(defaultGateway).initialize(
            makeAddr("defaultGatewayCounterpart"),
            address(l1Router),
            inbox,
            0x0000000000000000000000000000000000000000000000000000000000000001,
            makeAddr("l2BeaconProxyFactory")
        );

        // set default gateway
        vm.startPrank(owner);
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);
        l1OrbitRouter.setDefaultGateway(
            address(defaultGateway), maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );
        vm.stopPrank();

        /// deposit it
        vm.prank(user);
        vm.expectRevert("NOT_ALLOWED_TO_BRIDGE_FEE_TOKEN");
        l1Router.outboundTransferCustomRefund(
            address(nativeToken), user, user, 100, maxGas, gasPriceBid, ""
        );
    }

    function test_setDefaultGateway() public override {
        L1OrbitERC20Gateway newL1DefaultGateway = new L1OrbitERC20Gateway();
        address newDefaultGatewayCounterpart = makeAddr("newDefaultGatewayCounterpart");
        newL1DefaultGateway.initialize(
            newDefaultGatewayCounterpart,
            address(l1OrbitRouter),
            inbox,
            0x0000000000000000000000000000000000000000000000000000000000000001,
            makeAddr("l2BeaconProxyFactory")
        );

        // approve fees
        vm.prank(owner);
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);

        // event checkers
        vm.expectEmit(true, true, true, true);
        emit DefaultGatewayUpdated(address(newL1DefaultGateway));

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(owner, owner);

        vm.expectEmit(true, true, true, true);
        emit ERC20InboxRetryableTicket(
            address(l1OrbitRouter),
            counterpartGateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(
                L2GatewayRouter.setDefaultGateway.selector, newDefaultGatewayCounterpart
            )
        );

        // set it
        vm.prank(owner);
        uint256 seqNum = l1OrbitRouter.setDefaultGateway(
            address(newL1DefaultGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            nativeTokenTotalFee
        );

        /// checks
        assertEq(
            l1OrbitRouter.defaultGateway(),
            address(newL1DefaultGateway),
            "Invalid newL1DefaultGateway"
        );

        assertEq(seqNum, 0, "Invalid seqNum");
    }

    function test_setDefaultGateway_InboxPrefunded() public {
        L1OrbitERC20Gateway newL1DefaultGateway = new L1OrbitERC20Gateway();
        address newDefaultGatewayCounterpart = makeAddr("newDefaultGatewayCounterpart");
        newL1DefaultGateway.initialize(
            newDefaultGatewayCounterpart,
            address(l1OrbitRouter),
            inbox,
            0x0000000000000000000000000000000000000000000000000000000000000001,
            makeAddr("l2BeaconProxyFactory")
        );

        // prefund inbox
        vm.prank(owner);
        nativeToken.transfer(address(inbox), nativeTokenTotalFee * 2);

        // snapshot balance
        uint256 ownerNativeTokenBalance = nativeToken.balanceOf(owner);

        // event checkers
        vm.expectEmit(true, true, true, true);
        emit DefaultGatewayUpdated(address(newL1DefaultGateway));

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(owner, owner);

        vm.expectEmit(true, true, true, true);
        emit ERC20InboxRetryableTicket(
            address(l1OrbitRouter),
            counterpartGateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(
                L2GatewayRouter.setDefaultGateway.selector, newDefaultGatewayCounterpart
            )
        );

        // set it
        vm.prank(owner);
        uint256 seqNum = l1OrbitRouter.setDefaultGateway(
            address(newL1DefaultGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            nativeTokenTotalFee
        );

        /// checks
        assertEq(
            l1OrbitRouter.defaultGateway(),
            address(newL1DefaultGateway),
            "Invalid newL1DefaultGateway"
        );

        assertEq(seqNum, 0, "Invalid seqNum");

        uint256 ownerNativeTokenBalanceAfter = nativeToken.balanceOf(owner);
        assertEq(
            ownerNativeTokenBalance,
            ownerNativeTokenBalanceAfter,
            "Wrong owner native token balance"
        );
    }

    function test_setDefaultGateway_InboxPartiallyPrefunded() public {
        L1OrbitERC20Gateway newL1DefaultGateway = new L1OrbitERC20Gateway();
        address newDefaultGatewayCounterpart = makeAddr("newDefaultGatewayCounterpart");
        newL1DefaultGateway.initialize(
            newDefaultGatewayCounterpart,
            address(l1OrbitRouter),
            inbox,
            0x0000000000000000000000000000000000000000000000000000000000000001,
            makeAddr("l2BeaconProxyFactory")
        );

        // prefund inbox
        uint256 prefundAmount = nativeTokenTotalFee / 2 + 1;
        vm.prank(owner);
        nativeToken.transfer(address(inbox), prefundAmount);

        // snapshot balance
        uint256 ownerNativeTokenBalance = nativeToken.balanceOf(owner);

        // approve fees
        vm.prank(owner);
        nativeToken.approve(address(l1OrbitRouter), prefundAmount);

        // event checkers
        vm.expectEmit(true, true, true, true);
        emit DefaultGatewayUpdated(address(newL1DefaultGateway));

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(owner, owner);

        vm.expectEmit(true, true, true, true);
        emit ERC20InboxRetryableTicket(
            address(l1OrbitRouter),
            counterpartGateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(
                L2GatewayRouter.setDefaultGateway.selector, newDefaultGatewayCounterpart
            )
        );

        // set it
        vm.prank(owner);
        uint256 seqNum = l1OrbitRouter.setDefaultGateway(
            address(newL1DefaultGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            nativeTokenTotalFee
        );

        /// checks
        assertEq(
            l1OrbitRouter.defaultGateway(),
            address(newL1DefaultGateway),
            "Invalid newL1DefaultGateway"
        );

        assertEq(seqNum, 0, "Invalid seqNum");

        uint256 ownerNativeTokenBalanceAfter = nativeToken.balanceOf(owner);
        assertEq(
            ownerNativeTokenBalance - ownerNativeTokenBalanceAfter,
            nativeTokenTotalFee - prefundAmount,
            "Wrong owner native token balance"
        );
    }

    function test_setDefaultGateway_AddressZero() public override {
        address newL1DefaultGateway = address(0);

        // approve fees
        vm.prank(owner);
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);

        // event checkers
        vm.expectEmit(true, true, true, true);
        emit DefaultGatewayUpdated(address(newL1DefaultGateway));

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(owner, owner);

        vm.expectEmit(true, true, true, true);
        emit ERC20InboxRetryableTicket(
            address(l1OrbitRouter),
            counterpartGateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(L2GatewayRouter.setDefaultGateway.selector, address(0))
        );

        // set it
        vm.prank(owner);
        uint256 seqNum = l1OrbitRouter.setDefaultGateway(
            newL1DefaultGateway, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        /// checks
        assertEq(
            l1OrbitRouter.defaultGateway(),
            address(newL1DefaultGateway),
            "Invalid newL1DefaultGateway"
        );

        assertEq(seqNum, 0, "Invalid seqNum");
    }

    function test_setDefaultGateway_revert_NotSupportedInOrbit() public {
        vm.prank(owner);
        vm.expectRevert("NOT_SUPPORTED_IN_ORBIT");
        l1OrbitRouter.setDefaultGateway{value: retryableCost}(
            address(5), maxGas, gasPriceBid, maxSubmissionCost
        );
    }

    function test_setGateway() public override {
        // create gateway
        L1OrbitCustomGateway customGateway = new L1OrbitCustomGateway();
        address l2Counterpart = makeAddr("l2Counterpart");
        customGateway.initialize(l2Counterpart, address(l1Router), address(inbox), owner);

        // create token
        ERC20 customToken = new ERC20("X", "Y");
        vm.deal(address(customToken), 100 ether);

        // approve fees
        ERC20PresetMinterPauser(address(nativeToken)).mint(
            address(customToken), nativeTokenTotalFee
        );
        vm.prank(address(customToken));
        nativeToken.approve(address(customGateway), nativeTokenTotalFee);

        // register token to gateway
        vm.mockCall(
            address(customToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(customToken));
        customGateway.registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        ERC20PresetMinterPauser(address(nativeToken)).mint(
            address(customToken), nativeTokenTotalFee
        );

        // snapshot state before
        uint256 senderNativeTokenBalanceBefore = nativeToken.balanceOf(address(customToken));

        // approve fees
        vm.prank(address(customToken));
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);

        // expect events
        vm.expectEmit(true, true, true, true);
        emit GatewaySet(address(customToken), address(customGateway));

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(address(customToken), address(customToken));

        vm.expectEmit(true, true, true, true);
        address[] memory _tokenArr = new address[](1);
        _tokenArr[0] = address(customToken);
        address[] memory _gatewayArr = new address[](1);
        _gatewayArr[0] = l2Counterpart;
        emit ERC20InboxRetryableTicket(
            address(l1OrbitRouter),
            counterpartGateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(L2GatewayRouter.setGateway.selector, _tokenArr, _gatewayArr)
        );

        // set gateway
        vm.prank(address(customToken));
        uint256 seqNum = l1OrbitRouter.setGateway(
            address(customGateway), maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        ///// checks

        assertEq(
            l1OrbitRouter.l1TokenToGateway(address(customToken)),
            address(customGateway),
            "Gateway not set"
        );

        uint256 senderNativeTokenBalanceAfter = nativeToken.balanceOf(address(customToken));
        assertEq(
            senderNativeTokenBalanceBefore - senderNativeTokenBalanceAfter,
            nativeTokenTotalFee,
            "Wrong sender native token balance"
        );

        assertEq(seqNum, 1, "Invalid seqNum");
    }

    function test_setGateway_CustomCreditback() public override {
        // create gateway
        L1OrbitCustomGateway customGateway = new L1OrbitCustomGateway();
        address l2Counterpart = makeAddr("l2Counterpart");
        customGateway.initialize(l2Counterpart, address(l1Router), address(inbox), owner);

        // create token
        ERC20 customToken = new ERC20("X", "Y");
        vm.deal(address(customToken), 100 ether);

        // register token to gateway
        ERC20PresetMinterPauser(address(nativeToken)).mint(
            address(customToken), nativeTokenTotalFee
        );
        vm.prank(address(customToken));
        nativeToken.approve(address(customGateway), nativeTokenTotalFee);

        vm.mockCall(
            address(customToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );
        vm.prank(address(customToken));
        customGateway.registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        // approve fees
        ERC20PresetMinterPauser(address(nativeToken)).mint(
            address(customToken), nativeTokenTotalFee
        );
        vm.prank(address(customToken));
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);

        // expect events
        vm.expectEmit(true, true, true, true);
        emit GatewaySet(address(customToken), address(customGateway));

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(creditBackAddress, creditBackAddress);

        vm.expectEmit(true, true, true, true);
        address[] memory _tokenArr = new address[](1);
        _tokenArr[0] = address(customToken);
        address[] memory _gatewayArr = new address[](1);
        _gatewayArr[0] = l2Counterpart;
        emit ERC20InboxRetryableTicket(
            address(l1OrbitRouter),
            counterpartGateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(L2GatewayRouter.setGateway.selector, _tokenArr, _gatewayArr)
        );

        // set gateway
        vm.prank(address(customToken));
        uint256 seqNum = l1OrbitRouter.setGateway(
            address(customGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        ///// checks

        assertEq(
            l1OrbitRouter.l1TokenToGateway(address(customToken)),
            address(customGateway),
            "Gateway not set"
        );

        assertEq(seqNum, 1, "Invalid seqNum");
    }

    function test_setGateway_revert_NoUpdateToDifferentAddress() public override {
        // create gateway
        address initialGateway = address(new L1OrbitCustomGateway());
        address l2Counterpart = makeAddr("l2Counterpart");
        L1OrbitCustomGateway(initialGateway).initialize(
            l2Counterpart, address(l1Router), address(inbox), owner
        );

        // create token
        address token = address(new ERC20("X", "Y"));
        vm.deal(address(token), 100 ether);

        // register token to gateway
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);
        vm.prank(token);
        nativeToken.approve(address(initialGateway), nativeTokenTotalFee);

        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(token);
        L1OrbitCustomGateway(initialGateway).registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        // initially set gateway for token
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);
        vm.prank(address(token));
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);

        vm.prank(address(token));
        l1OrbitRouter.setGateway(
            initialGateway,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );
        assertEq(l1OrbitRouter.l1TokenToGateway(token), initialGateway, "Initial gateway not set");

        //// now try setting different gateway
        address newGateway = address(new L1OrbitCustomGateway());

        vm.prank(token);
        vm.expectRevert("NO_UPDATE_TO_DIFFERENT_ADDR");
        l1OrbitRouter.setGateway(
            newGateway,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );
    }

    function test_setGateway_revert_NotArbEnabled() public override {
        address nonArbEnabledToken = address(new ERC20("X", "Y"));
        vm.deal(nonArbEnabledToken, 100 ether);
        vm.mockCall(
            nonArbEnabledToken,
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb2))
        );

        vm.prank(nonArbEnabledToken);
        vm.expectRevert("NOT_ARB_ENABLED");
        l1OrbitRouter.setGateway(
            makeAddr("gateway"), 100_000, 3, 200, makeAddr("creditback"), nativeTokenTotalFee
        );
    }

    function test_setGateway_revert_NotToContract() public override {
        address token = address(new ERC20("X", "Y"));
        vm.deal(token, 100 ether);
        vm.mockCall(token, abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1)));

        address gatewayNotContract = makeAddr("not contract");

        vm.prank(token);
        vm.expectRevert("NOT_TO_CONTRACT");
        l1OrbitRouter.setGateway(
            gatewayNotContract,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );
    }

    function test_setGateway_revert_NotSupportedInOrbit() public {
        vm.expectRevert("NOT_SUPPORTED_IN_ORBIT");
        l1OrbitRouter.setGateway(address(102), maxGas, gasPriceBid, maxSubmissionCost);
    }

    function test_setGateway_revert_CustomCreaditbackNotSupportedInOrbit() public {
        vm.expectRevert("NOT_SUPPORTED_IN_ORBIT");
        l1OrbitRouter.setGateway(
            address(103), maxGas, gasPriceBid, maxSubmissionCost, creditBackAddress
        );
    }

    function test_setGateway_revert_TokenNotHandledByGateway() public override {
        // create gateway
        L1OrbitCustomGateway gateway = new L1OrbitCustomGateway();

        // create token
        address token = address(new ERC20("X", "Y"));
        vm.deal(token, 100 ether);
        vm.mockCall(token, abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1)));

        vm.prank(token);
        vm.expectRevert("TOKEN_NOT_HANDLED_BY_GATEWAY");
        l1OrbitRouter.setGateway(
            address(gateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );
    }

    function test_setGateways() public override {
        // create tokens and gateways
        address[] memory tokens = new address[](2);
        tokens[0] = address(new ERC20("1", "1"));
        tokens[1] = address(new ERC20("2", "2"));
        address[] memory gateways = new address[](2);
        gateways[0] = address(new L1OrbitCustomGateway());
        gateways[1] = address(new L1OrbitCustomGateway());

        address l2Counterpart = makeAddr("l2Counterpart");

        /// init all
        for (uint256 i = 0; i < 2; i++) {
            L1OrbitCustomGateway(gateways[i]).initialize(
                l2Counterpart, address(l1Router), address(inbox), owner
            );

            vm.mockCall(
                tokens[i], abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
            );

            // register tokens to gateways
            ERC20PresetMinterPauser(address(nativeToken)).mint(tokens[i], nativeTokenTotalFee);
            vm.prank(tokens[i]);
            nativeToken.approve(address(gateways[i]), nativeTokenTotalFee);

            vm.deal(tokens[i], 100 ether);
            vm.prank(tokens[i]);
            L1OrbitCustomGateway(gateways[i]).registerTokenToL2(
                makeAddr("tokenL2Address"),
                maxGas,
                gasPriceBid,
                maxSubmissionCost,
                creditBackAddress,
                nativeTokenTotalFee
            );
        }

        // approve fees
        vm.prank(owner);
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);

        // expect events
        vm.expectEmit(true, true, true, true);
        emit GatewaySet(tokens[0], gateways[0]);
        vm.expectEmit(true, true, true, true);
        emit GatewaySet(tokens[1], gateways[1]);

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(owner, owner);

        vm.expectEmit(true, true, true, true);
        address[] memory _gatewayArr = new address[](2);
        _gatewayArr[0] = l2Counterpart;
        _gatewayArr[1] = l2Counterpart;
        emit ERC20InboxRetryableTicket(
            address(l1OrbitRouter),
            counterpartGateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(L2GatewayRouter.setGateway.selector, tokens, _gatewayArr)
        );

        /// set gateways
        vm.prank(owner);
        uint256 seqNum = l1OrbitRouter.setGateways(
            tokens, gateways, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        ///// checks

        assertEq(l1Router.l1TokenToGateway(tokens[0]), gateways[0], "Gateway[0] not set");
        assertEq(l1Router.l1TokenToGateway(tokens[1]), gateways[1], "Gateway[1] not set");
        assertEq(seqNum, 2, "Invalid seqNum");
    }

    function test_setGateways_SetZeroAddr() public override {
        // create gateway
        address initialGateway = address(new L1OrbitCustomGateway());
        address l2Counterpart = makeAddr("l2Counterpart");
        L1OrbitCustomGateway(initialGateway).initialize(
            l2Counterpart, address(l1Router), address(inbox), owner
        );

        // create token
        address token = address(new ERC20("X", "Y"));
        vm.deal(address(token), 100 ether);

        // register token to gateway
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);
        vm.prank(address(token));
        nativeToken.approve(initialGateway, nativeTokenTotalFee);

        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(token);
        L1OrbitCustomGateway(initialGateway).registerTokenToL2(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );

        // initially set gateway for token
        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);
        vm.prank(address(token));
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);

        vm.prank(address(token));
        l1OrbitRouter.setGateway(
            initialGateway,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress,
            nativeTokenTotalFee
        );
        assertEq(l1OrbitRouter.l1TokenToGateway(token), initialGateway, "Initial gateway not set");

        //// now set to zero addr
        address newGateway = address(0);

        // approve fees
        vm.prank(owner);
        nativeToken.approve(address(l1OrbitRouter), nativeTokenTotalFee);

        // expect events
        vm.expectEmit(true, true, true, true);
        emit GatewaySet(token, newGateway);

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(owner, owner);

        vm.expectEmit(true, true, true, true);
        address[] memory _tokenArr = new address[](1);
        _tokenArr[0] = token;
        address[] memory _gatewayArr = new address[](1);
        _gatewayArr[0] = newGateway;
        emit ERC20InboxRetryableTicket(
            address(l1OrbitRouter),
            counterpartGateway,
            0,
            maxGas,
            gasPriceBid,
            nativeTokenTotalFee,
            abi.encodeWithSelector(L2GatewayRouter.setGateway.selector, _tokenArr, _gatewayArr)
        );

        /// set gateways
        vm.prank(owner);
        uint256 seqNum = l1OrbitRouter.setGateways(
            _tokenArr, _gatewayArr, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );

        ///// checks

        assertEq(l1OrbitRouter.l1TokenToGateway(token), address(0), "Custom gateway not cleared");
        assertEq(seqNum, 2, "Invalid seqNum");
    }

    function test_setGateways_revert_WrongLength() public override {
        address[] memory tokens = new address[](2);
        tokens[0] = address(new ERC20("1", "1"));
        tokens[1] = address(new ERC20("2", "2"));
        address[] memory gateways = new address[](1);
        gateways[0] = address(new L1OrbitCustomGateway());

        /// set gateways
        vm.prank(owner);
        vm.expectRevert("WRONG_LENGTH");
        l1OrbitRouter.setGateways(
            tokens, gateways, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
        );
    }

    function test_setGateways_revert_NotSupportedInOrbit() public {
        vm.prank(owner);
        vm.expectRevert("NOT_SUPPORTED_IN_ORBIT");
        l1OrbitRouter.setGateways(
            new address[](2), new address[](2), maxGas, gasPriceBid, maxSubmissionCost
        );
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
