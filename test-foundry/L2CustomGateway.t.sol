// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L2ArbitrumGateway.t.sol";
import {L2CustomGateway, ERC20} from "contracts/tokenbridge/arbitrum/gateway/L2CustomGateway.sol";
import {L2GatewayToken} from "contracts/tokenbridge/libraries/L2GatewayToken.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";

contract L2CustomGatewayTest is L2ArbitrumGatewayTest {
    L2CustomGateway public l2CustomGateway;
    address public l2BeaconProxyFactory;

    address public l1CustomToken = makeAddr("l1CustomToken");

    function setUp() public virtual {
        l2CustomGateway = new L2CustomGateway();
        l2Gateway = L2ArbitrumGateway(address(l2CustomGateway));

        L2CustomGateway(l2CustomGateway).initialize(l1Counterpart, router);
    }

    /* solhint-disable func-name-mixedcase */
    function test_calculateL2TokenAddress_NonRegistered() public {
        address nonRegisteredL1Token = makeAddr("nonRegisteredL1Token");

        assertEq(
            l2CustomGateway.calculateL2TokenAddress(nonRegisteredL1Token),
            address(0),
            "Invalid L2 token"
        );
    }

    function test_calculateL2TokenAddress_Registered() public {
        address l2CustomToken = _registerToken();
        assertEq(
            l2CustomGateway.calculateL2TokenAddress(l1CustomToken),
            l2CustomToken,
            "Invalid L2 token"
        );
    }

    function test_finalizeInboundTransfer() public override {
        // /// deposit params
        // bytes memory gatewayData = abi.encode(
        //     abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        // );
        // bytes memory callHookData = new bytes(0);

        // /// events
        // vm.expectEmit(true, true, true, true);
        // emit DepositFinalized(l1Token, sender, receiver, amount);

        // /// finalize deposit
        // vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        // l2CustomGateway.finalizeInboundTransfer(
        //     l1Token, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        // );

        // /// check tokens have been minted to receiver
        // address expectedL2Address = l2CustomGateway.calculateL2TokenAddress(l1Token);
        // assertEq(
        //     StandardArbERC20(expectedL2Address).balanceOf(receiver),
        //     amount,
        //     "Invalid receiver balance"
        // );
    }

    function test_finalizeInboundTransfer_WithCallHook() public override {
        // /// deposit params
        // bytes memory gatewayData = abi.encode(
        //     abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        // );
        // bytes memory callHookData = new bytes(0x1234ab);

        // /// events
        // vm.expectEmit(true, true, true, true);
        // emit DepositFinalized(l1Token, sender, receiver, amount);

        // /// finalize deposit
        // vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        // l2CustomGateway.finalizeInboundTransfer(
        //     l1Token, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        // );

        // /// check tokens have been minted to receiver
        // address expectedL2Address = l2CustomGateway.calculateL2TokenAddress(l1Token);
        // assertEq(
        //     StandardArbERC20(expectedL2Address).balanceOf(receiver),
        //     amount,
        //     "Invalid receiver balance"
        // );
    }

    function test_finalizeInboundTransfer_ShouldHalt() public override {
        // /// deposit params
        // bytes memory gatewayData = abi.encode(
        //     abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        // );
        // bytes memory callHookData = new bytes(0);

        // // mock incorrect address calculation
        // address notL2Token = makeAddr("notL2Token");
        // vm.mockCall(
        //     address(l2BeaconProxyFactory),
        //     abi.encodeWithSignature(
        //         "calculateExpectedAddress(address,bytes32)",
        //         address(l2CustomGateway),
        //         l2CustomGateway.getUserSalt(l1Token)
        //     ),
        //     abi.encode(notL2Token)
        // );

        // // check that withdrawal is triggered occurs when deposit is halted
        // vm.expectEmit(true, true, true, true);
        // emit WithdrawalInitiated(l1Token, address(l2CustomGateway), sender, 0, 0, amount);

        // /// finalize deposit
        // vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        // vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        // l2CustomGateway.finalizeInboundTransfer(
        //     l1Token, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        // );

        // /// check L2 token hasn't been creted
        // assertEq(address(notL2Token).code.length, 0, "L2 token isn't supposed to be created");
    }

    function test_initialize() public {
        L2CustomGateway gateway = new L2CustomGateway();
        L2CustomGateway(gateway).initialize(l1Counterpart, router);

        assertEq(gateway.counterpartGateway(), l1Counterpart, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
    }

    function test_initialize_revert_BadRouter() public {
        L2CustomGateway gateway = new L2CustomGateway();
        vm.expectRevert("BAD_ROUTER");
        L2CustomGateway(gateway).initialize(l1Counterpart, address(0));
    }

    function test_initialize_revert_InvalidCounterpart() public {
        L2CustomGateway gateway = new L2CustomGateway();
        vm.expectRevert("INVALID_COUNTERPART");
        L2CustomGateway(gateway).initialize(address(0), router);
    }

    function test_initialize_revert_AlreadyInit() public {
        L2CustomGateway gateway = new L2CustomGateway();
        L2CustomGateway(gateway).initialize(l1Counterpart, router);
        vm.expectRevert("ALREADY_INIT");
        L2CustomGateway(gateway).initialize(l1Counterpart, router);
    }

    function test_outboundTransfer() public override {
        // create and init custom l2Token
        address l2CustomToken = _registerToken();

        // mint token to user
        deal(l2CustomToken, sender, 100 ether);

        // withdrawal params
        bytes memory data = new bytes(0);

        // events
        uint256 expectedId = 0;
        bytes memory expectedData =
            l2CustomGateway.getOutboundCalldata(l1CustomToken, sender, receiver, amount, data);
        vm.expectEmit(true, true, true, true);
        emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1CustomToken, sender, receiver, expectedId, 0, amount);

        // withdraw
        vm.mockCall(
            address(l2CustomToken),
            abi.encodeWithSignature("l1Address()"),
            abi.encode(l1CustomToken)
        );
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(sender);
        l2CustomGateway.outboundTransfer(l1CustomToken, receiver, amount, 0, 0, data);
    }

    function test_outboundTransfer_4Args() public override {
        // create and init custom l2Token
        address l2CustomToken = _registerToken();

        // mint token to user
        deal(l2CustomToken, sender, 100 ether);

        // withdrawal params
        bytes memory data = new bytes(0);

        // events
        uint256 expectedId = 0;
        bytes memory expectedData =
            l2CustomGateway.getOutboundCalldata(l1CustomToken, sender, receiver, amount, data);
        vm.expectEmit(true, true, true, true);
        emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1CustomToken, sender, receiver, expectedId, 0, amount);

        // withdraw
        vm.mockCall(
            address(l2CustomToken),
            abi.encodeWithSignature("l1Address()"),
            abi.encode(l1CustomToken)
        );
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(sender);
        l2CustomGateway.outboundTransfer(l1CustomToken, receiver, amount, data);
    }

    function test_outboundTransfer_revert_NotExpectedL1Token() public override {
        // create and init custom l2Token
        address l2CustomToken = _registerToken();

        // mock invalid L1 token ref
        address notOriginalL1Token = makeAddr("notOriginalL1Token");
        vm.mockCall(
            address(l2CustomToken),
            abi.encodeWithSignature("l1Address()"),
            abi.encode(notOriginalL1Token)
        );

        vm.expectRevert("NOT_EXPECTED_L1_TOKEN");
        l2Gateway.outboundTransfer(l1CustomToken, address(101), 200, 0, 0, new bytes(0));
    }

    function test_registerTokenFromL1() public {
        address[] memory l1Tokens = new address[](2);
        l1Tokens[0] = makeAddr("l1Token0");
        l1Tokens[1] = makeAddr("l1Token1");

        address[] memory l2Tokens = new address[](2);
        l2Tokens[0] = makeAddr("l2Token0");
        l2Tokens[1] = makeAddr("l2Token1");

        // expect events
        vm.expectEmit(true, true, true, true);
        emit TokenSet(l1Tokens[0], l2Tokens[0]);
        emit TokenSet(l1Tokens[1], l2Tokens[1]);

        // register
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2CustomGateway.registerTokenFromL1(l1Tokens, l2Tokens);

        // checks
        assertEq(l2CustomGateway.l1ToL2Token(l1Tokens[0]), l2Tokens[0], "Invalid registeration 0");
        assertEq(l2CustomGateway.l1ToL2Token(l1Tokens[1]), l2Tokens[1], "Invalid registeration 1");
    }

    function test_registerTokenFromL1_revert_OnlyCounterpartGateway() public {
        vm.expectRevert("ONLY_COUNTERPART_GATEWAY");
        l2CustomGateway.registerTokenFromL1(new address[](0), new address[](0));
    }

    ////
    // Internal helper functions
    ////
    function _registerToken() internal returns (address) {
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = l1CustomToken;

        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = address(new L2CustomToken(address(l2CustomGateway), address(l1CustomToken)));

        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2CustomGateway.registerTokenFromL1(l1Tokens, l2Tokens);

        return l2Tokens[0];
    }

    ////
    // Event declarations
    ////
    event TokenSet(address indexed l1Address, address indexed l2Address);
}

contract L2CustomToken is L2GatewayToken {
    constructor(address _l2CustomGateway, address _l1CustomToken) {
        L2GatewayToken._initialize("L2 token", "L2", 18, _l2CustomGateway, _l1CustomToken);
    }
}