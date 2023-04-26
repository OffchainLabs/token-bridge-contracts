// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { GatewayRouterTest } from "./GatewayRouter.t.sol";
import { L1GatewayRouter } from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import { L2GatewayRouter } from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import { L1ERC20Gateway } from "contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol";
import { L1CustomGateway } from "contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol";
import { InboxMock } from "contracts/tokenbridge/test/InboxMock.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract L1GatewayRouterTest is GatewayRouterTest {
    L1GatewayRouter public l1Router;

    address public owner = makeAddr("owner");
    address public defaultGateway = makeAddr("defaultGateway");
    address public counterpartGateway = makeAddr("counterpartGateway");
    address public inbox;

    function setUp() public {
        inbox = address(new InboxMock());

        l1Router = new L1GatewayRouter();
        l1Router.initialize(owner, defaultGateway, address(0), counterpartGateway, inbox);

        vm.deal(owner, 100 ether);
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

    function test_setDefaultGateway() public {
        L1ERC20Gateway newL1DefaultGateway = new L1ERC20Gateway();
        address newDefaultGatewayCounterpart = makeAddr("newDefaultGatewayCounterpart");
        newL1DefaultGateway.initialize(
            newDefaultGatewayCounterpart,
            address(l1Router),
            inbox,
            0x0000000000000000000000000000000000000000000000000000000000000001,
            makeAddr("l2BeaconProxyFactory")
        );

        // retryable params
        uint256 maxSubmissionCost = 50000;
        uint256 maxGas = 1000000000;
        uint256 gasPriceBid = 3;
        uint256 retryableCost = maxSubmissionCost + maxGas * gasPriceBid;

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

    function test_setGateway() public {
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
        customGateway.registerTokenToL2{ value: 4000040000 }(
            makeAddr("tokenL2Address"),
            1000000000,
            3,
            40000,
            makeAddr("creditBackAddress")
        );

        // set gateway params
        uint256 maxSubmissionCost = 40000;
        uint256 maxGas = 1000000000;
        uint256 gasPrice = 3;
        uint256 value = maxSubmissionCost + maxGas * gasPrice;
        address creditBackAddress = makeAddr("creditBackAddress");

        // expect events
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
        uint256 seqNum = l1Router.setGateway{ value: value }(
            address(customGateway),
            maxGas,
            gasPrice,
            maxSubmissionCost,
            creditBackAddress
        );

        ///// checks

        assertEq(
            l1Router.l1TokenToGateway(address(customToken)),
            address(customGateway),
            "Gateway not set"
        );

        assertEq(seqNum, 0, "Invalid seqNum");
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

    ////
    // Event declarations
    ////
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
