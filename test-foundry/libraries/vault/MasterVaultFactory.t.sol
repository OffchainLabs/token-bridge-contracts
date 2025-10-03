// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {MasterVaultFactory} from "../../../contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {MasterVault} from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {TestERC20} from "../../../contracts/tokenbridge/test/TestERC20.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract MasterVaultFactoryTest is Test {
    MasterVaultFactory public factory;
    TestERC20 public token;

    address public owner = address(0x1);
    address public user = address(0x2);

    event VaultDeployed(address indexed token, address indexed vault);

    function setUp() public {
        token = new TestERC20();
        factory = new MasterVaultFactory();

        vm.prank(owner);
        factory.initialize(owner);
    }

    function test_initialize() public {
        assertEq(factory.owner(), owner, "Invalid owner");
    }

    function test_deployVault() public {
        address expectedVault = factory.calculateVaultAddress(address(token));

        vm.expectEmit(true, true, false, false);
        emit VaultDeployed(address(token), expectedVault);

        address deployedVault = factory.deployVault(address(token));

        assertEq(deployedVault, expectedVault, "Vault address mismatch");
        assertTrue(deployedVault.code.length > 0, "Vault not deployed");

        MasterVault vault = MasterVault(deployedVault);
        assertEq(address(vault.asset()), address(token), "Invalid vault asset");
        assertEq(vault.owner(), address(factory), "Invalid vault owner");
    }

    function test_deployVault_RevertZeroAddress() public {
        vm.expectRevert(MasterVaultFactory.ZeroAddress.selector);
        factory.deployVault(address(0));
    }

    function test_getVault_DeploysIfNotExists() public {
        address expectedVault = factory.calculateVaultAddress(address(token));
        address vault = factory.getVault(address(token));

        assertEq(vault, expectedVault, "Vault address mismatch");
        assertTrue(vault.code.length > 0, "Vault not deployed");
    }

    function test_getVault_ReturnsExistingVault() public {
        address vault1 = factory.getVault(address(token));
        address vault2 = factory.getVault(address(token));

        assertEq(vault1, vault2, "Should return same vault");
    }

    function test_calculateVaultAddress() public {
        address calculatedAddress = factory.calculateVaultAddress(address(token));
        address deployedVault = factory.deployVault(address(token));

        assertEq(calculatedAddress, deployedVault, "Address calculation incorrect");
    }

    function test_beaconOwnership() public {
        assertEq(factory.beacon().owner(), owner, "Beacon owner should be the factory owner");
    }

    function test_ownerCanUpgradeBeacon() public {
        MasterVault newImplementation = new MasterVault();

        UpgradeableBeacon beacon = factory.beacon();
        vm.prank(owner);
        beacon.upgradeTo(address(newImplementation));

        assertEq(factory.beacon().implementation(), address(newImplementation), "Beacon implementation should be updated");
    }

    function test_nonOwnerCannotUpgradeBeacon() public {
        MasterVault newImplementation = new MasterVault();

        UpgradeableBeacon beacon = factory.beacon();
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        beacon.upgradeTo(address(newImplementation));
    }

    function test_beaconUpgradeAffectsAllVaults() public {
        address vault1 = factory.deployVault(address(token));

        TestERC20 token2 = new TestERC20();
        address vault2 = factory.deployVault(address(token2));

        MasterVault newImplementation = new MasterVault();

        UpgradeableBeacon beacon = factory.beacon();
        vm.prank(owner);
        beacon.upgradeTo(address(newImplementation));

        assertEq(factory.beacon().implementation(), address(newImplementation), "Beacon should point to new implementation");

        MasterVault(vault1).owner();
        MasterVault(vault2).owner();
    }
}