// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import { TestERC20 } from "../../../contracts/tokenbridge/test/TestERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {
    BeaconProxyFactory,
    ClonableBeaconProxy
} from "../../../contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract MasterVaultCoreTest is Test {
    MasterVault public vault;
    TestERC20 public token;
    UpgradeableBeacon public beacon;
    BeaconProxyFactory public beaconProxyFactory;

    address public user = address(0x1);
    string public name = "Master Test Token";
    string public symbol = "mTST";

    function getAssetsHoldingVault() internal view virtual returns (address) {
        return address(vault.subVault()) == address(0) ? address(vault) : address(vault.subVault());
    }

    function setUp() public virtual {
        token = new TestERC20();

        MasterVault implementation = new MasterVault();
        beacon = new UpgradeableBeacon(address(implementation));

        beaconProxyFactory = new BeaconProxyFactory();
        beaconProxyFactory.initialize(address(beacon));

        bytes32 salt = keccak256("test");
        address proxyAddress = beaconProxyFactory.createProxy(salt);
        vault = MasterVault(proxyAddress);

        vault.initialize(IERC20(address(token)), name, symbol, address(this));
        vault.unpause();
    }
}
