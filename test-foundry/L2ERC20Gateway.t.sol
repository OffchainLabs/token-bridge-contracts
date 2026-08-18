// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L2ArbitrumGateway.t.sol";
import {L2ERC20Gateway} from "contracts/tokenbridge/arbitrum/gateway/L2ERC20Gateway.sol";
import {StandardArbERC20} from "contracts/tokenbridge/arbitrum/StandardArbERC20.sol";
import {
    BeaconProxyFactory,
    ClonableBeaconProxy
} from "contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";

contract L2ERC20GatewayTest is L2ArbitrumGatewayTest {
    L2ERC20Gateway public l2StandardGateway;
    address public l2BeaconProxyFactory;

    address public l1Token = makeAddr("l1Token");

    function setUp() public virtual {
        l2StandardGateway = new L2ERC20Gateway();
        l2Gateway = L2ArbitrumGateway(address(l2StandardGateway));

        // create beacon
        StandardArbERC20 standardArbERC20 = new StandardArbERC20();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(standardArbERC20));
        l2BeaconProxyFactory = address(new BeaconProxyFactory());
        BeaconProxyFactory(l2BeaconProxyFactory).initialize(address(beacon));

        L2ERC20Gateway(l2StandardGateway).initialize(l1Counterpart, router, l2BeaconProxyFactory);
    }

    /* solhint-disable func-name-mixedcase */
    function test_calculateL2TokenAddress() public {
        assertEq(
            l2StandardGateway.getUserSalt(l1Token),
            keccak256(abi.encode(l1Token)),
            "Invalid user salt"
        );
    }

    function test_cloneableProxyHash() public {
        assertEq(
            l2StandardGateway.cloneableProxyHash(),
            keccak256(type(ClonableBeaconProxy).creationCode),
            "Invalid proxy hash"
        );
    }

    function test_finalizeInboundTransfer() public override {
        /// deposit params
        bytes memory gatewayData = abi.encode(
            abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        );
        bytes memory callHookData = new bytes(0);

        /// events
        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(l1Token, sender, receiver, amount);

        /// finalize deposit
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2StandardGateway.finalizeInboundTransfer(
            l1Token, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        );

        /// check tokens have been minted to receiver
        address expectedL2Address = l2StandardGateway.calculateL2TokenAddress(l1Token);
        assertEq(
            StandardArbERC20(expectedL2Address).balanceOf(receiver),
            amount,
            "Invalid receiver balance"
        );
    }

    function test_finalizeInboundTransfer_WithCallHook() public override {
        /// deposit params
        bytes memory gatewayData = abi.encode(
            abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        );
        bytes memory callHookData = new bytes(0x1);

        /// events
        vm.expectEmit(true, true, true, true);
        emit DepositFinalized(l1Token, sender, receiver, amount);

        /// finalize deposit
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2StandardGateway.finalizeInboundTransfer(
            l1Token, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        );

        /// check tokens have been minted to receiver
        address expectedL2Address = l2StandardGateway.calculateL2TokenAddress(l1Token);
        assertEq(
            StandardArbERC20(expectedL2Address).balanceOf(receiver),
            amount,
            "Invalid receiver balance"
        );
    }

    function test_finalizeInboundTransfer_ShouldHalt() public {
        /// deposit params
        bytes memory gatewayData = abi.encode(
            abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
        );
        bytes memory callHookData = new bytes(0);

        // mock incorrect address calculation
        address notL2Token = makeAddr("notL2Token");
        vm.mockCall(
            address(l2BeaconProxyFactory),
            abi.encodeWithSignature(
                "calculateExpectedAddress(address,bytes32)",
                address(l2StandardGateway),
                l2StandardGateway.getUserSalt(l1Token)
            ),
            abi.encode(notL2Token)
        );

        // check that withdrawal is triggered occurs when deposit is halted
        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1Token, address(l2StandardGateway), sender, 0, 0, amount);

        /// finalize deposit
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(l1Counterpart));
        l2StandardGateway.finalizeInboundTransfer(
            l1Token, sender, receiver, amount, abi.encode(gatewayData, callHookData)
        );

        /// check L2 token hasn't been creted
        assertEq(address(notL2Token).code.length, 0, "L2 token isn't supposed to be created");
    }

    function test_getUserSalt() public {
        assertEq(
            l2StandardGateway.getUserSalt(l1Token),
            keccak256(abi.encode(l1Token)),
            "Invalid user salt"
        );
    }

    function test_initialize() public {
        L2ERC20Gateway gateway = new L2ERC20Gateway();
        L2ERC20Gateway(gateway).initialize(l1Counterpart, router, l2BeaconProxyFactory);

        assertEq(gateway.counterpartGateway(), l1Counterpart, "Invalid counterpartGateway");
        assertEq(gateway.router(), router, "Invalid router");
        assertEq(gateway.beaconProxyFactory(), l2BeaconProxyFactory, "Invalid beacon");
    }

    function test_initialize_revert_InvalidBeacon() public {
        L2ERC20Gateway gateway = new L2ERC20Gateway();
        vm.expectRevert("INVALID_BEACON");
        L2ERC20Gateway(gateway).initialize(l1Counterpart, router, address(0));
    }

    function test_initialize_revert_BadRouter() public {
        L2ERC20Gateway gateway = new L2ERC20Gateway();
        vm.expectRevert("BAD_ROUTER");
        L2ERC20Gateway(gateway).initialize(l1Counterpart, address(0), l2BeaconProxyFactory);
    }

    function test_initialize_revert_InvalidCounterpart() public {
        L2ERC20Gateway gateway = new L2ERC20Gateway();
        vm.expectRevert("INVALID_COUNTERPART");
        L2ERC20Gateway(gateway).initialize(address(0), router, l2BeaconProxyFactory);
    }

    function test_initialize_revert_AlreadyInit() public {
        L2ERC20Gateway gateway = new L2ERC20Gateway();
        L2ERC20Gateway(gateway).initialize(l1Counterpart, router, l2BeaconProxyFactory);
        vm.expectRevert("ALREADY_INIT");
        L2ERC20Gateway(gateway).initialize(l1Counterpart, router, l2BeaconProxyFactory);
    }

    function test_outboundTransfer() public override {
        // create and init standard l2Token
        bytes32 salt = keccak256(abi.encode(l1Token));
        vm.startPrank(address(l2Gateway));
        address l2Token = BeaconProxyFactory(l2BeaconProxyFactory).createProxy(salt);
        StandardArbERC20(l2Token).bridgeInit(
            l1Token,
            abi.encode(
                abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
            )
        );
        vm.stopPrank();

        // mint token to user
        deal(l2Token, sender, 100 ether);

        // withdrawal params
        bytes memory data = new bytes(0);

        // events
        uint256 expectedId = 0;
        bytes memory expectedData =
            l2Gateway.getOutboundCalldata(l1Token, sender, receiver, amount, data);
        vm.expectEmit(true, true, true, true);
        emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1Token, sender, receiver, expectedId, 0, amount);

        // withdraw
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(sender);
        l2Gateway.outboundTransfer(l1Token, receiver, amount, 0, 0, data);
    }

    function test_outboundTransfer_4Args() public override {
        // create and init standard l2Token
        bytes32 salt = keccak256(abi.encode(l1Token));
        vm.startPrank(address(l2Gateway));
        address l2Token = BeaconProxyFactory(l2BeaconProxyFactory).createProxy(salt);
        StandardArbERC20(l2Token).bridgeInit(
            l1Token,
            abi.encode(
                abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
            )
        );
        vm.stopPrank();

        // mint token to user
        deal(l2Token, sender, 100 ether);

        // withdrawal params
        bytes memory data = new bytes(0);

        // events
        uint256 expectedId = 0;
        bytes memory expectedData =
            l2Gateway.getOutboundCalldata(l1Token, sender, receiver, amount, data);
        vm.expectEmit(true, true, true, true);
        emit TxToL1(sender, l1Counterpart, expectedId, expectedData);

        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(l1Token, sender, receiver, expectedId, 0, amount);

        // withdraw
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSysMock).code);
        vm.prank(sender);
        l2Gateway.outboundTransfer(l1Token, receiver, amount, data);
    }

    function test_outboundTransfer_revert_NotExpectedL1Token() public override {
        /// register l1Token
        bytes32 salt = keccak256(abi.encode(l1Token));
        vm.startPrank(address(l2Gateway));
        address l2Token = BeaconProxyFactory(l2BeaconProxyFactory).createProxy(salt);
        StandardArbERC20(l2Token).bridgeInit(
            l1Token,
            abi.encode(
                abi.encode(bytes("Name")), abi.encode(bytes("Symbol")), abi.encode(uint256(18))
            )
        );
        vm.stopPrank();

        // mock invalid L1 token ref
        address notOriginalL1Token = makeAddr("notOriginalL1Token");
        vm.mockCall(
            address(l2Token), abi.encodeWithSignature("l1Address()"), abi.encode(notOriginalL1Token)
        );

        vm.expectRevert("NOT_EXPECTED_L1_TOKEN");
        l2Gateway.outboundTransfer(l1Token, address(101), 200, 0, 0, new bytes(0));
    }
}
