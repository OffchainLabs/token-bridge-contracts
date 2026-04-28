// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {L1YbbERC20Gateway} from "contracts/tokenbridge/ethereum/gateway/L1YbbERC20Gateway.sol";
import {
    L1OrbitYbbERC20Gateway
} from "contracts/tokenbridge/ethereum/gateway/L1OrbitYbbERC20Gateway.sol";
import {L1YbbCustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1YbbCustomGateway.sol";
import {
    L1OrbitYbbCustomGateway
} from "contracts/tokenbridge/ethereum/gateway/L1OrbitYbbCustomGateway.sol";
import {MasterVault} from "contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MasterVaultFactory} from "contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {ClonableBeaconProxy} from "contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";
import {InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";

contract YbbDoubleInitTest is Test {
    address l2Counterpart = makeAddr("l2Counterpart");
    address router = makeAddr("router");
    address inbox;
    address owner = makeAddr("owner");
    address factory;
    bytes32 proxyHash = keccak256(type(ClonableBeaconProxy).creationCode);
    address l2BeaconProxyFactory = makeAddr("l2BeaconProxyFactory");

    function setUp() public {
        inbox = address(new InboxMock());
        MasterVaultFactory f = new MasterVaultFactory();
        factory = address(f);
    }

    // --- L1YbbERC20Gateway ---

    function test_L1YbbERC20Gateway_revertsOnDoubleInit() public {
        L1YbbERC20Gateway gw = new L1YbbERC20Gateway();
        gw.initialize(l2Counterpart, router, inbox, proxyHash, l2BeaconProxyFactory, factory, owner);
        vm.expectRevert("ALREADY_INIT");
        gw.initialize(l2Counterpart, router, inbox, proxyHash, l2BeaconProxyFactory, factory, owner);
    }

    // --- L1OrbitYbbERC20Gateway ---

    function test_L1OrbitYbbERC20Gateway_revertsOnDoubleInit() public {
        L1OrbitYbbERC20Gateway gw = new L1OrbitYbbERC20Gateway();
        gw.initialize(l2Counterpart, router, inbox, proxyHash, l2BeaconProxyFactory, factory, owner);
        vm.expectRevert("ALREADY_INIT");
        gw.initialize(l2Counterpart, router, inbox, proxyHash, l2BeaconProxyFactory, factory, owner);
    }

    // --- L1YbbCustomGateway ---

    function test_L1YbbCustomGateway_revertsOnDoubleInit() public {
        L1YbbCustomGateway gw = new L1YbbCustomGateway();
        gw.initialize(l2Counterpart, router, inbox, owner, factory);
        vm.expectRevert("ALREADY_INIT");
        gw.initialize(l2Counterpart, router, inbox, owner, factory);
    }

    // --- L1OrbitYbbCustomGateway ---

    function test_L1OrbitYbbCustomGateway_revertsOnDoubleInit() public {
        L1OrbitYbbCustomGateway gw = new L1OrbitYbbCustomGateway();
        gw.initialize(l2Counterpart, router, inbox, owner, factory);
        vm.expectRevert("ALREADY_INIT");
        gw.initialize(l2Counterpart, router, inbox, owner, factory);
    }
}
