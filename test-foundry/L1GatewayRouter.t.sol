// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { GatewayRouterTest } from "./GatewayRouter.t.sol";
import { L1GatewayRouter } from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import { L2GatewayRouter } from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import { L1ERC20Gateway } from "contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol";
import { L1CustomGateway } from "contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol";
import { InboxMock } from "contracts/tokenbridge/test/InboxMock.sol";
import { IERC165 } from "contracts/tokenbridge/libraries/IERC165.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract L1GatewayRouterTest is GatewayRouterTest {
    L1GatewayRouter public l1Router;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public counterpartGateway = makeAddr("counterpartGateway");
    address public inbox;

    function setUp() public virtual {
        inbox = address(new InboxMock());
        defaultGateway = address(new L1ERC20Gateway());

        router = new L1GatewayRouter();
        l1Router = L1GatewayRouter(address(router));
        l1Router.initialize(owner, defaultGateway, address(0), counterpartGateway, inbox);

        maxSubmissionCost = 50000;
        retryableCost = maxSubmissionCost + maxGas * gasPriceBid;

        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public {
        L1GatewayRouter router = new L1GatewayRouter();

        router.initialize(owner, defaultGateway, address(0), counterpartGateway, inbox);

        assertEq(router.router(), address(0), "Invalid router");
        assertEq(router.counterpartGateway(), counterpartGateway, "Invalid counterpartGateway");
        assertEq(router.defaultGateway(), defaultGateway, "Invalid defaultGateway");
        assertEq(router.owner(), owner, "Invalid owner");
        assertEq(router.whitelist(), address(0), "Invalid whitelist");
        assertEq(router.inbox(), inbox, "Invalid inbox");
    }

    function test_initialize_revert_AlreadyInit() public {
        L1GatewayRouter router = new L1GatewayRouter();
        router.initialize(owner, defaultGateway, address(0), counterpartGateway, inbox);
        vm.expectRevert("ALREADY_INIT");
        router.initialize(owner, defaultGateway, address(0), counterpartGateway, inbox);
    }

    function test_initialize_revert_InvalidCounterPart() public {
        L1GatewayRouter router = new L1GatewayRouter();
        address invalidCounterpart = address(0);
        vm.expectRevert("INVALID_COUNTERPART");
        router.initialize(owner, defaultGateway, address(0), invalidCounterpart, inbox);
    }

    function test_postUpgradeInit_revert_NotFromAdmin() public {
        vm.expectRevert("NOT_FROM_ADMIN");
        l1Router.postUpgradeInit();
    }

    function test_getGateway_DisabledGateway() public virtual {
        address token = makeAddr("some token");

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        address[] memory gateways = new address[](1);
        gateways[0] = address(1);

        vm.prank(owner);
        l1Router.setGateways{ value: retryableCost }(
            tokens,
            gateways,
            maxGas,
            gasPriceBid,
            maxSubmissionCost
        );

        address gateway = router.getGateway(token);
        assertEq(gateway, address(0), "Invalid gateway");
    }

    function test_getGateway_CustomGateway() public virtual {
        address token = makeAddr("some token");

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        address[] memory gateways = new address[](1);
        gateways[0] = address(new L1ERC20Gateway());

        vm.prank(owner);
        l1Router.setGateways{ value: retryableCost }(
            tokens,
            gateways,
            maxGas,
            gasPriceBid,
            maxSubmissionCost
        );

        address gateway = router.getGateway(token);
        assertEq(gateway, gateways[0], "Invalid gateway");
    }

    function test_setDefaultGateway() public virtual {
        L1ERC20Gateway newL1DefaultGateway = new L1ERC20Gateway();
        address newDefaultGatewayCounterpart = makeAddr("newDefaultGatewayCounterpart");
        newL1DefaultGateway.initialize(
            newDefaultGatewayCounterpart,
            address(l1Router),
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
        emit InboxRetryableTicket(
            address(l1Router),
            counterpartGateway,
            0,
            maxGas,
            abi.encodeWithSelector(
                L2GatewayRouter.setDefaultGateway.selector,
                newDefaultGatewayCounterpart
            )
        );

        // set it
        vm.prank(owner);
        uint256 seqNum = l1Router.setDefaultGateway{ value: retryableCost }(
            address(newL1DefaultGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost
        );

        /// checks
        assertEq(
            l1Router.defaultGateway(),
            address(newL1DefaultGateway),
            "Invalid newL1DefaultGateway"
        );

        assertEq(seqNum, 0, "Invalid seqNum");
    }

    function test_setDefaultGateway_AddressZero() public virtual {
        address newL1DefaultGateway = address(0);

        // event checkers
        vm.expectEmit(true, true, true, true);
        emit DefaultGatewayUpdated(address(newL1DefaultGateway));

        vm.expectEmit(true, true, true, true);
        emit TicketData(maxSubmissionCost);

        vm.expectEmit(true, true, true, true);
        emit RefundAddresses(owner, owner);

        vm.expectEmit(true, true, true, true);
        emit InboxRetryableTicket(
            address(l1Router),
            counterpartGateway,
            0,
            maxGas,
            abi.encodeWithSelector(L2GatewayRouter.setDefaultGateway.selector, address(0))
        );

        // set it
        vm.prank(owner);
        uint256 seqNum = l1Router.setDefaultGateway{ value: retryableCost }(
            newL1DefaultGateway,
            maxGas,
            gasPriceBid,
            maxSubmissionCost
        );

        /// checks
        assertEq(
            l1Router.defaultGateway(),
            address(newL1DefaultGateway),
            "Invalid newL1DefaultGateway"
        );

        assertEq(seqNum, 0, "Invalid seqNum");
    }

    function test_setGateway() public virtual {
        // create gateway
        L1CustomGateway customGateway = new L1CustomGateway();
        address l2Counterpart = makeAddr("l2Counterpart");
        customGateway.initialize(l2Counterpart, address(l1Router), address(inbox), owner);

        // create token
        ERC20 customToken = new ERC20("X", "Y");
        vm.deal(address(customToken), 100 ether);
        vm.mockCall(
            address(customToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );

        // register token to gateway
        vm.prank(address(customToken));
        customGateway.registerTokenToL2{ value: retryableCost }(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            makeAddr("creditBackAddress")
        );

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
        emit InboxRetryableTicket(
            address(l1Router),
            counterpartGateway,
            0,
            maxGas,
            abi.encodeWithSelector(L2GatewayRouter.setGateway.selector, _tokenArr, _gatewayArr)
        );

        // set gateway
        vm.prank(address(customToken));
        uint256 seqNum = l1Router.setGateway{ value: retryableCost }(
            address(customGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost
        );

        ///// checks

        assertEq(
            l1Router.l1TokenToGateway(address(customToken)),
            address(customGateway),
            "Gateway not set"
        );

        assertEq(seqNum, 1, "Invalid seqNum");
    }

    function test_setGateway_CustomCreditback() public virtual {
        // create gateway
        L1CustomGateway customGateway = new L1CustomGateway();
        address l2Counterpart = makeAddr("l2Counterpart");
        customGateway.initialize(l2Counterpart, address(l1Router), address(inbox), owner);

        // create token
        ERC20 customToken = new ERC20("X", "Y");
        vm.deal(address(customToken), 100 ether);
        vm.mockCall(
            address(customToken),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );

        // register token to gateway
        vm.prank(address(customToken));
        customGateway.registerTokenToL2{ value: retryableCost }(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress
        );

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
        emit InboxRetryableTicket(
            address(l1Router),
            counterpartGateway,
            0,
            maxGas,
            abi.encodeWithSelector(L2GatewayRouter.setGateway.selector, _tokenArr, _gatewayArr)
        );

        // set gateway
        vm.prank(address(customToken));
        uint256 seqNum = l1Router.setGateway{ value: retryableCost }(
            address(customGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress
        );

        ///// checks

        assertEq(
            l1Router.l1TokenToGateway(address(customToken)),
            address(customGateway),
            "Gateway not set"
        );

        assertEq(seqNum, 1, "Invalid seqNum");
    }

    function test_setGateway_revert_NotArbEnabled() public virtual {
        address nonArbEnabledToken = address(new ERC20("X", "Y"));
        vm.deal(nonArbEnabledToken, 100 ether);
        vm.mockCall(
            nonArbEnabledToken,
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb2))
        );

        vm.prank(nonArbEnabledToken);
        vm.expectRevert("NOT_ARB_ENABLED");
        l1Router.setGateway{ value: 400000 }(
            makeAddr("gateway"),
            100000,
            3,
            200,
            makeAddr("creditback")
        );
    }

    function test_setGateway_revert_NotToContract() public virtual {
        address token = address(new ERC20("X", "Y"));
        vm.deal(token, 100 ether);
        vm.mockCall(token, abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1)));

        address gatewayNotContract = makeAddr("not contract");

        vm.prank(token);
        vm.expectRevert("NOT_TO_CONTRACT");
        l1Router.setGateway{ value: retryableCost }(
            gatewayNotContract,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress
        );
    }

    function test_setGateway_revert_NoUpdateToDifferentAddress() public virtual {
        // create gateway
        address initialGateway = address(new L1CustomGateway());
        address l2Counterpart = makeAddr("l2Counterpart");
        L1CustomGateway(initialGateway).initialize(
            l2Counterpart,
            address(l1Router),
            address(inbox),
            owner
        );

        // create token
        address token = address(new ERC20("X", "Y"));
        vm.deal(address(token), 100 ether);
        vm.mockCall(
            address(token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );

        // register token to gateway
        vm.prank(token);
        L1CustomGateway(initialGateway).registerTokenToL2{ value: retryableCost }(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress
        );

        // initially set gateway for token
        vm.prank(address(token));
        l1Router.setGateway{ value: retryableCost }(
            initialGateway,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress
        );
        assertEq(l1Router.l1TokenToGateway(token), initialGateway, "Initial gateway not set");

        //// now try setting different gateway
        address newGateway = address(new L1CustomGateway());

        vm.prank(token);
        vm.expectRevert("NO_UPDATE_TO_DIFFERENT_ADDR");
        l1Router.setGateway{ value: retryableCost }(
            newGateway,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress
        );
    }

    function test_setGateway_revert_TokenNotHandledByGateway() public virtual {
        // create gateway
        L1CustomGateway gateway = new L1CustomGateway();

        // create token
        address token = address(new ERC20("X", "Y"));
        vm.deal(token, 100 ether);
        vm.mockCall(token, abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1)));

        vm.prank(token);
        vm.expectRevert("TOKEN_NOT_HANDLED_BY_GATEWAY");
        l1Router.setGateway{ value: retryableCost }(
            address(gateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress
        );
    }

    function test_setGateways() public virtual {
        // create tokens and gateways
        address[] memory tokens = new address[](2);
        tokens[0] = address(new ERC20("1", "1"));
        tokens[1] = address(new ERC20("2", "2"));
        address[] memory gateways = new address[](2);
        gateways[0] = address(new L1CustomGateway());
        gateways[1] = address(new L1CustomGateway());

        address l2Counterpart = makeAddr("l2Counterpart");

        /// init all
        for (uint256 i = 0; i < 2; i++) {
            L1CustomGateway(gateways[i]).initialize(
                l2Counterpart,
                address(l1Router),
                address(inbox),
                owner
            );

            vm.mockCall(
                tokens[i],
                abi.encodeWithSignature("isArbitrumEnabled()"),
                abi.encode(uint8(0xb1))
            );

            // register tokens to gateways
            vm.deal(tokens[i], 100 ether);
            vm.prank(tokens[i]);
            L1CustomGateway(gateways[i]).registerTokenToL2{ value: retryableCost }(
                makeAddr("tokenL2Address"),
                maxGas,
                gasPriceBid,
                maxSubmissionCost,
                makeAddr("creditBackAddress")
            );
        }

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
        emit InboxRetryableTicket(
            address(l1Router),
            counterpartGateway,
            0,
            maxGas,
            abi.encodeWithSelector(L2GatewayRouter.setGateway.selector, tokens, _gatewayArr)
        );

        /// set gateways
        vm.prank(owner);
        uint256 seqNum = l1Router.setGateways{ value: retryableCost }(
            tokens,
            gateways,
            maxGas,
            gasPriceBid,
            maxSubmissionCost
        );

        ///// checks

        assertEq(l1Router.l1TokenToGateway(tokens[0]), gateways[0], "Gateway[0] not set");
        assertEq(l1Router.l1TokenToGateway(tokens[1]), gateways[1], "Gateway[1] not set");
        assertEq(seqNum, 2, "Invalid seqNum");
    }

    function test_setGateways_revert_WrongLength() public virtual {
        address[] memory tokens = new address[](2);
        tokens[0] = address(new ERC20("1", "1"));
        tokens[1] = address(new ERC20("2", "2"));
        address[] memory gateways = new address[](1);
        gateways[0] = address(new L1CustomGateway());

        /// set gateways
        vm.prank(owner);
        vm.expectRevert("WRONG_LENGTH");
        l1Router.setGateways{ value: retryableCost }(
            tokens,
            gateways,
            maxGas,
            gasPriceBid,
            maxSubmissionCost
        );
    }

    function test_setGateways_SetZeroAddr() public virtual {
        // create gateway
        address initialGateway = address(new L1CustomGateway());
        address l2Counterpart = makeAddr("l2Counterpart");
        L1CustomGateway(initialGateway).initialize(
            l2Counterpart,
            address(l1Router),
            address(inbox),
            owner
        );

        // create token
        address token = address(new ERC20("X", "Y"));
        vm.deal(address(token), 100 ether);
        vm.mockCall(
            address(token),
            abi.encodeWithSignature("isArbitrumEnabled()"),
            abi.encode(uint8(0xb1))
        );

        // register token to gateway
        vm.prank(token);
        L1CustomGateway(initialGateway).registerTokenToL2{ value: retryableCost }(
            makeAddr("tokenL2Address"),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress
        );

        // initially set gateway for token
        vm.prank(address(token));
        l1Router.setGateway{ value: retryableCost }(
            initialGateway,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            creditBackAddress
        );
        assertEq(l1Router.l1TokenToGateway(token), initialGateway, "Initial gateway not set");

        //// now set to zero addr
        address newGateway = address(0);

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
        emit InboxRetryableTicket(
            address(l1Router),
            counterpartGateway,
            0,
            maxGas,
            abi.encodeWithSelector(L2GatewayRouter.setGateway.selector, _tokenArr, _gatewayArr)
        );

        /// set gateways
        vm.prank(owner);
        uint256 seqNum = l1Router.setGateways{ value: retryableCost }(
            _tokenArr,
            _gatewayArr,
            maxGas,
            gasPriceBid,
            maxSubmissionCost
        );

        ///// checks

        assertEq(l1Router.l1TokenToGateway(token), address(0), "Custom gateway not cleared");
        assertEq(seqNum, 2, "Invalid seqNum");
    }

    function test_setGateways_revert_notOwner() public {
        vm.expectRevert("ONLY_OWNER");
        l1Router.setGateways{ value: 1000 }(new address[](1), new address[](1), 100, 8, 10);
    }

    function test_setOwner(address newOwner) public {
        vm.assume(newOwner != address(0));

        vm.prank(owner);
        l1Router.setOwner(newOwner);

        assertEq(l1Router.owner(), newOwner, "Invalid owner");
    }

    function test_setOwner_revert_InvalidOwner() public {
        address invalidOwner = address(0);

        vm.prank(owner);
        vm.expectRevert("INVALID_OWNER");
        l1Router.setOwner(invalidOwner);
    }

    function test_setOwner_revert_OnlyOwner() public {
        address nonOwner = address(250);

        vm.prank(nonOwner);
        vm.expectRevert("ONLY_OWNER");
        l1Router.setOwner(address(300));
    }

    function test_supportsInterface() public {
        bytes4 iface = type(IERC165).interfaceId;
        assertEq(l1Router.supportsInterface(iface), true, "Interface should be supported");

        iface = L1GatewayRouter.outboundTransferCustomRefund.selector;
        assertEq(l1Router.supportsInterface(iface), true, "Interface should be supported");

        iface = bytes4(0);
        assertEq(l1Router.supportsInterface(iface), false, "Interface shouldn't be supported");

        iface = L1GatewayRouter.setGateways.selector;
        assertEq(l1Router.supportsInterface(iface), false, "Interface shouldn't be supported");
    }

    function test_outboundTransfer() public virtual {
        // init default gateway
        L1ERC20Gateway(defaultGateway).initialize(
            makeAddr("defaultGatewayCounterpart"),
            address(l1Router),
            inbox,
            0x0000000000000000000000000000000000000000000000000000000000000001,
            makeAddr("l2BeaconProxyFactory")
        );

        // set default gateway
        vm.prank(owner);
        l1Router.setDefaultGateway{ value: retryableCost }(
            address(defaultGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost
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
        bytes memory userEncodedData = abi.encode(maxSubmissionCost, "");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit TransferRouted(address(token), user, to, address(defaultGateway));

        /// deposit it
        vm.prank(user);
        l1Router.outboundTransfer{ value: retryableCost }(
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

    function test_outboundTransferCustomRefund() public virtual {
        // init default gateway
        L1ERC20Gateway(defaultGateway).initialize(
            makeAddr("defaultGatewayCounterpart"),
            address(l1Router),
            inbox,
            0x0000000000000000000000000000000000000000000000000000000000000001,
            makeAddr("l2BeaconProxyFactory")
        );

        // set default gateway
        vm.prank(owner);
        l1Router.setDefaultGateway{ value: retryableCost }(
            address(defaultGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost
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
        bytes memory userEncodedData = abi.encode(maxSubmissionCost, "");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit TransferRouted(address(token), user, to, address(defaultGateway));

        /// deposit it
        vm.prank(user);
        l1Router.outboundTransferCustomRefund{ value: retryableCost }(
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

    ////
    // Event declarations
    ////
    event TransferRouted(
        address indexed token,
        address indexed _userFrom,
        address indexed _userTo,
        address gateway
    );
    event GatewaySet(address indexed l1Token, address indexed gateway);
    event DefaultGatewayUpdated(address newDefaultGateway);

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
