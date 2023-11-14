// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L2ArbitrumGateway.t.sol";
import {L2CustomGateway} from "contracts/tokenbridge/arbitrum/gateway/L2CustomGateway.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";

contract L2CustomGatewayTest is L2ArbitrumGatewayTest {
    L2CustomGateway public l2CustomGateway;
    address public l2BeaconProxyFactory;

    function setUp() public virtual {
        l2CustomGateway = new L2CustomGateway();
        l2Gateway = L2ArbitrumGateway(address(l2CustomGateway));

        L2CustomGateway(l2CustomGateway).initialize(l1Counterpart, router);
    }

    function _registerToken() internal {
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = makeAddr("l1CustomToken");

        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = makeAddr("l2CustomToken");

        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2CustomGateway.registerTokenFromL1(l1Tokens, l2Tokens);
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
        /// register token
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = makeAddr("l1CustomToken");

        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = makeAddr("l2CustomToken");

        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2CustomGateway.registerTokenFromL1(l1Tokens, l2Tokens);

        // check now registered
        assertEq(
            l2CustomGateway.calculateL2TokenAddress(l1Tokens[0]), l2Tokens[0], "Invalid L2 token"
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
        // // create and init standard l2Token
        // bytes32 salt = keccak256(abi.encode(l1Token));
        // vm.startPrank(address(l2Gateway));
        // address l2Token = BeaconProxyFactory(l2BeaconProxyFactory).createProxy(salt);
        // StandardArbERC20(l2Token).bridgeInit(
        //     l1Token,
        //     abi.encode(
        //         abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        //     )
        // );
        // vm.stopPrank();

        // // mint token to user
        // deal(l2Token, sender, 100 ether);

        // // withdrawal params
        // bytes memory data = new bytes(0);

        // // events
        // uint256 expectedId = 0;
        // bytes memory expectedData =
        //     l2Gateway.getOutboundCalldata(l1Token, sender, receiver, amount, data);
        // vm.expectEmit(true, true, true, true);
        // emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        // vm.expectEmit(true, true, true, true);
        // emit WithdrawalInitiated(l1Token, sender, receiver, expectedId, 0, amount);

        // // withdraw
        // vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        // vm.prank(sender);
        // l2Gateway.outboundTransfer(l1Token, receiver, amount, 0, 0, data);
    }

    function test_outboundTransfer_4Args() public override {
        // // create and init standard l2Token
        // bytes32 salt = keccak256(abi.encode(l1Token));
        // vm.startPrank(address(l2Gateway));
        // address l2Token = BeaconProxyFactory(l2BeaconProxyFactory).createProxy(salt);
        // StandardArbERC20(l2Token).bridgeInit(
        //     l1Token,
        //     abi.encode(
        //         abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        //     )
        // );
        // vm.stopPrank();

        // // mint token to user
        // deal(l2Token, sender, 100 ether);

        // // withdrawal params
        // bytes memory data = new bytes(0);

        // // events
        // uint256 expectedId = 0;
        // bytes memory expectedData =
        //     l2Gateway.getOutboundCalldata(l1Token, sender, receiver, amount, data);
        // vm.expectEmit(true, true, true, true);
        // emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        // vm.expectEmit(true, true, true, true);
        // emit WithdrawalInitiated(l1Token, sender, receiver, expectedId, 0, amount);

        // // withdraw
        // vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        // vm.prank(sender);
        // l2Gateway.outboundTransfer(l1Token, receiver, amount, data);
    }

    function test_outboundTransfer_revert_NotExpectedL1Token() public override {
        // /// register l1Token
        // bytes32 salt = keccak256(abi.encode(l1Token));
        // vm.startPrank(address(l2Gateway));
        // address l2Token = BeaconProxyFactory(l2BeaconProxyFactory).createProxy(salt);
        // StandardArbERC20(l2Token).bridgeInit(
        //     l1Token,
        //     abi.encode(
        //         abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        //     )
        // );
        // vm.stopPrank();

        // // mock invalid L1 token ref
        // address notOriginalL1Token = makeAddr("notOriginalL1Token");
        // vm.mockCall(
        //     address(l2Token), abi.encodeWithSignature("l1Address()"), abi.encode(notOriginalL1Token)
        // );

        // vm.expectRevert("NOT_EXPECTED_L1_TOKEN");
        // l2Gateway.outboundTransfer(l1Token, address(101), 200, 0, 0, new bytes(0));
    }

    // function registerTokenFromL1(address[] calldata l1Address, address[] calldata l2Address)
    //     external
    //     onlyCounterpartGateway
    // {
    //     // we assume both arrays are the same length, safe since its encoded by the L1
    //     for (uint256 i = 0; i < l1Address.length; i++) {
    //         // here we don't check if l2Address is a contract and instead deal with that behaviour
    //         // in `handleNoContract` this way we keep the l1 and l2 address oracles in sync
    //         l1ToL2Token[l1Address[i]] = l2Address[i];
    //         emit TokenSet(l1Address[i], l2Address[i]);
    //     }
    // }

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
    // Event declarations
    ////
    event TokenSet(address indexed l1Address, address indexed l2Address);
}
