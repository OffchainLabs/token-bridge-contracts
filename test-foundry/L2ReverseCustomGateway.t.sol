// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L2CustomGateway.t.sol";
import {L2ReverseCustomGateway} from
    "contracts/tokenbridge/arbitrum/gateway/L2ReverseCustomGateway.sol";
import {ReverseTestCustomTokenL1} from "contracts/tokenbridge/test/TestCustomTokenL1.sol";
import {ReverseTestArbCustomToken} from "contracts/tokenbridge/test/TestArbCustomToken.sol";

contract L2ReverseCustomGatewayTest is L2CustomGatewayTest {
    L2ReverseCustomGateway public l2ReverseCustomGateway;

    ReverseTestArbCustomToken public l2MintedToken;

    function setUp() public override {
        l2ReverseCustomGateway = new L2ReverseCustomGateway();
        l2Gateway = L2ArbitrumGateway(address(l2ReverseCustomGateway));
        l2CustomGateway = L2CustomGateway(address(l2ReverseCustomGateway));

        L2ReverseCustomGateway(l2ReverseCustomGateway).initialize(l1Counterpart, router);

        l2MintedToken =
            new ReverseTestArbCustomToken(address(l2ReverseCustomGateway), makeAddr("l1Token"));
    }

    /* solhint-disable func-name-mixedcase */
    function test_calculateL2TokenAddress_Registered() public override {
        address l1CustomToken = _registerToken();
        assertEq(
            l2CustomGateway.calculateL2TokenAddress(l1CustomToken),
            address(l2MintedToken),
            "Invalid L2 token"
        );
    }

    function test_finalizeInboundTransfer() public override {
        // fund gateway with tokens being withdrawn
        vm.prank(address(l2ReverseCustomGateway));
        l2MintedToken.mint();

        /// deposit params
        bytes memory gatewayData = new bytes(0);
        bytes memory callHookData = new bytes(0);

        // register custom token
        address l1CustomToken = _registerToken();

        vm.mockCall(
            address(l2MintedToken),
            abi.encodeWithSignature("l1Address()"),
            abi.encode(l1CustomToken)
        );

        /// events
        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(l1CustomToken, sender, receiver, amount);

        /// finalize deposit
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2CustomGateway.finalizeInboundTransfer(
            l1CustomToken, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        );

        /// check tokens have been released to receiver;
        assertEq(
            ERC20(address(l2MintedToken)).balanceOf(receiver), amount, "Invalid receiver balance"
        );
    }

    function test_finalizeInboundTransfer_WithCallHook() public override {
        // fund gateway with tokens being withdrawn
        vm.prank(address(l2ReverseCustomGateway));
        l2MintedToken.mint();

        /// deposit params
        bytes memory gatewayData = abi.encode(
            abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        );
        bytes memory callHookData = new bytes(0x1);

        // register custom token
        address l1CustomToken = _registerToken();

        vm.mockCall(
            address(l2MintedToken),
            abi.encodeWithSignature("l1Address()"),
            abi.encode(l1CustomToken)
        );

        /// events
        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(l1CustomToken, sender, receiver, amount);

        /// finalize deposit
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2CustomGateway.finalizeInboundTransfer(
            l1CustomToken, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        );

        /// check tokens have been released to receiver;
        assertEq(
            ERC20(address(l2MintedToken)).balanceOf(receiver), amount, "Invalid receiver balance"
        );
    }

    ////
    // Internal helper functions
    ////
    function _registerToken() internal override returns (address) {
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(
            new ReverseTestCustomTokenL1(address(l1Counterpart), makeAddr("counterpartGateway"))
        );

        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = address(l2MintedToken);

        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2ReverseCustomGateway.registerTokenFromL1(l1Tokens, l2Tokens);

        return l1Tokens[0];
    }
}
