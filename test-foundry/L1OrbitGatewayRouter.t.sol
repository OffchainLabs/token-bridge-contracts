// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { L1GatewayRouterTest } from "./L1GatewayRouter.t.sol";
import { ERC20InboxMock } from "contracts/tokenbridge/test/InboxMock.sol";
import { L1OrbitERC20Gateway } from "contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol";
import { L1OrbitGatewayRouter } from "contracts/tokenbridge/ethereum/gateway/L1OrbitGatewayRouter.sol";
import { L2GatewayRouter } from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import { L1GatewayRouter } from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import { L1CustomGateway } from "contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract L1OrbitGatewayRouterTest is L1GatewayRouterTest {
    L1OrbitGatewayRouter public l1OrbitRouter;
    uint256 public nativeTokenTotalFee;

    function setUp() public override {
        inbox = address(new ERC20InboxMock());

        defaultGateway = address(new L1OrbitERC20Gateway());

        router = new L1OrbitGatewayRouter();
        l1Router = L1GatewayRouter(address(router));
        l1OrbitRouter = L1OrbitGatewayRouter(address(router));
        l1OrbitRouter.initialize(owner, defaultGateway, address(0), counterpartGateway, inbox);

        maxSubmissionCost = 0;
        retryableCost = 0;
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

        vm.prank(owner);
        l1OrbitRouter.setGateways(
            tokens,
            gateways,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            nativeTokenTotalFee
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

        vm.prank(owner);
        l1OrbitRouter.setGateways(
            tokens,
            gateways,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            nativeTokenTotalFee
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
        vm.prank(owner);
        l1OrbitRouter.setDefaultGateway(
            address(defaultGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            nativeTokenTotalFee
        );

        // create token
        ERC20PresetMinterPauser token = new ERC20PresetMinterPauser("X", "Y");
        token.mint(user, 10000);
        vm.prank(user);
        token.approve(defaultGateway, 103);

        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(defaultGateway));

        /// deposit data
        address to = address(401);
        uint256 amount = 103;
        bytes memory userEncodedData = _buildUserEncodedData("");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit TransferRouted(address(token), user, to, address(defaultGateway));

        /// deposit it
        vm.prank(user);
        l1Router.outboundTransfer{ value: _getValue() }(
            address(token),
            to,
            amount,
            maxGas,
            gasPriceBid,
            userEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, amount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = token.balanceOf(address(defaultGateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore,
            amount,
            "Wrong defaultGateway balance"
        );
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
        vm.prank(owner);
        l1OrbitRouter.setDefaultGateway(
            address(defaultGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            nativeTokenTotalFee
        );

        // create token
        ERC20PresetMinterPauser token = new ERC20PresetMinterPauser("X", "Y");
        token.mint(user, 10000);
        vm.prank(user);
        token.approve(defaultGateway, 103);

        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(defaultGateway));

        /// deposit data
        address refundTo = address(400);
        address to = address(401);
        uint256 amount = 103;
        bytes memory userEncodedData = _buildUserEncodedData("");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit TransferRouted(address(token), user, to, address(defaultGateway));

        /// deposit it
        vm.prank(user);
        l1Router.outboundTransferCustomRefund{ value: _getValue() }(
            address(token),
            refundTo,
            to,
            amount,
            maxGas,
            gasPriceBid,
            userEncodedData
        );

        // check tokens are escrowed
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceBefore - userBalanceAfter, amount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = token.balanceOf(address(defaultGateway));
        assertEq(
            l1GatewayBalanceAfter - l1GatewayBalanceBefore,
            amount,
            "Wrong defaultGateway balance"
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
                L2GatewayRouter.setDefaultGateway.selector,
                newDefaultGatewayCounterpart
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

    function test_setDefaultGateway_AddressZero() public override {
        address newL1DefaultGateway = address(0);

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
            newL1DefaultGateway,
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

    function test_setDefaultGateway_revert_NotSupportedInOrbit() public {
        vm.prank(owner);
        vm.expectRevert("NOT_SUPPORTED_IN_ORBIT");
        l1OrbitRouter.setDefaultGateway{ value: retryableCost }(
            address(5),
            maxGas,
            gasPriceBid,
            maxSubmissionCost
        );
    }

    function test_setGateway() public override {
        // TODO after custom gateway changes
    }

    function test_setGateway_CustomCreditback() public override {
        // TODO after custom gateway changes
    }

    function test_setGateway_revert_NoUpdateToDifferentAddress() public override {
        // TODO after custom gateway changes
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
            makeAddr("gateway"),
            100000,
            3,
            200,
            makeAddr("creditback"),
            nativeTokenTotalFee
        );
    }

    function test_setGateway_revert_NotToContract() public override {
        // TODO after custom gateway changes
    }

    function test_setGateway_revert_TokenNotHandledByGateway() public override {
        // TODO after custom gateway changes
    }

    function test_setGateways() public override {
        // TODO after custom gateway changes
    }

    function test_setGateways_SetZeroAddr() public override {
        // TODO after custom gateway changes
    }

    function test_setGateways_revert_WrongLength() public override {
        // TODO after custom gateway changes
    }

    ////
    // Helper functions
    ////
    function _buildUserEncodedData(
        bytes memory callHookData
    ) internal view override returns (bytes memory) {
        bytes memory userEncodedData = abi.encode(
            maxSubmissionCost,
            callHookData,
            nativeTokenTotalFee
        );
        return userEncodedData;
    }

    function _getValue() internal pure override returns (uint256) {
        return 0;
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
