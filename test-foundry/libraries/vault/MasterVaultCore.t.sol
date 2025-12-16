// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import { MasterVaultFactory } from "../../../contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import { TestERC20 } from "../../../contracts/tokenbridge/test/TestERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {
    BeaconProxyFactory,
    ClonableBeaconProxy
} from "../../../contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract MasterVaultCoreTest is Test {
    MasterVaultFactory public factory;
    MasterVault public vault;
    TestERC20 public token;

    address public user = vm.addr(1);
    address public admin = vm.addr(2);
    string public name = "Master Test Token";
    string public symbol = "mTST";

    function getAssetsHoldingVault() internal view virtual returns (address) {
        return address(vault.subVault()) == address(0) ? address(vault) : address(vault.subVault());
    }

    function setUp() public virtual {
        factory = new MasterVaultFactory();
        factory.initialize(admin);
        token = new TestERC20();
        vault = MasterVault(factory.deployVault(address(token)));
    }
}
