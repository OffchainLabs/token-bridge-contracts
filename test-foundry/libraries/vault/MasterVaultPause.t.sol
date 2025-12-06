// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "./MasterVaultCore.t.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxyFactory } from "../../../contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";

contract MasterVaultDeploymentPauseTest is MasterVaultCoreTest {
    function test_initialize() public {
        assertEq(address(vault.asset()), address(token), "Invalid asset");
        assertEq(vault.name(), name, "Invalid name");
        assertEq(vault.symbol(), symbol, "Invalid symbol");
        assertEq(vault.decimals(), token.decimals(), "Invalid decimals");
        assertEq(vault.totalSupply(), 0, "Invalid initial supply");
        assertEq(vault.totalAssets(), 0, "Invalid initial assets");

        assertTrue(
            vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(this)),
            "Should have DEFAULT_ADMIN_ROLE"
        );
        assertTrue(
            vault.hasRole(vault.VAULT_MANAGER_ROLE(), address(this)),
            "Should have VAULT_MANAGER_ROLE"
        );
        assertTrue(
            vault.hasRole(vault.FEE_MANAGER_ROLE(), address(this)),
            "Should have FEE_MANAGER_ROLE"
        );
    }

    function test_beaconUpgrade() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        address oldImplementation = beacon.implementation();
        assertEq(
            oldImplementation,
            address(beacon.implementation()),
            "Should have initial implementation"
        );

        MasterVault newImplementation = new MasterVault();
        beacon.upgradeTo(address(newImplementation));

        assertEq(
            beacon.implementation(),
            address(newImplementation),
            "Beacon should point to new implementation"
        );
        assertTrue(
            beacon.implementation() != oldImplementation,
            "Implementation should have changed"
        );

        assertEq(vault.name(), name, "Name should remain after upgrade");
    }

    function test_initialize_pausedByDefault() public {
        // Deploy a fresh vault to test initial paused state
        MasterVault implementation = new MasterVault();
        UpgradeableBeacon testBeacon = new UpgradeableBeacon(address(implementation));
        BeaconProxyFactory testFactory = new BeaconProxyFactory();
        testFactory.initialize(address(testBeacon));

        bytes32 salt = keccak256("test_paused");
        address proxyAddress = testFactory.createProxy(salt);
        MasterVault testVault = MasterVault(proxyAddress);

        testVault.initialize(IERC20(address(token)), "Test", "TST", address(this));

        assertTrue(testVault.paused(), "Vault should be paused immediately after initialization");
    }

    function test_initialize_pauserRole() public {
        assertTrue(vault.hasRole(vault.PAUSER_ROLE(), address(this)), "Should have PAUSER_ROLE");
        assertFalse(vault.paused(), "Should not be paused after unpause in setUp");
    }

    function test_pause() public {
        assertFalse(vault.paused(), "Should not be paused after unpause in setUp");

        vault.pause();

        assertTrue(vault.paused(), "Should be paused");
    }

    function test_unpause() public {
        vault.pause();
        assertTrue(vault.paused(), "Should be paused");

        vault.unpause();

        assertFalse(vault.paused(), "Should not be paused");
    }

    function test_pause_revert_NotPauser() public {
        vm.prank(user);
        vm.expectRevert();
        vault.pause();
    }

    function test_unpause_revert_NotPauser() public {
        vault.pause();

        vm.prank(user);
        vm.expectRevert();
        vault.unpause();
    }

    function test_multiplePausers() public {
        address pauser1 = address(0x3333);
        address pauser2 = address(0x4444);

        vault.grantRole(vault.PAUSER_ROLE(), pauser1);
        vault.grantRole(vault.PAUSER_ROLE(), pauser2);

        assertTrue(vault.hasRole(vault.PAUSER_ROLE(), pauser1), "Pauser1 should have PAUSER_ROLE");
        assertTrue(vault.hasRole(vault.PAUSER_ROLE(), pauser2), "Pauser2 should have PAUSER_ROLE");

        vm.prank(pauser1);
        vault.pause();
        assertTrue(vault.paused(), "Should be paused by pauser1");

        vm.prank(pauser2);
        vault.unpause();
        assertFalse(vault.paused(), "Should be unpaused by pauser2");
    }
}
