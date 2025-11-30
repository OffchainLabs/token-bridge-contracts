// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "./MasterVaultCore.t.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import { TestERC20 } from "../../../contracts/tokenbridge/test/TestERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxyFactory } from "../../../contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";

contract MasterVaultSubVaultManagementTest is MasterVaultCoreTest {
    MasterVault public subVault;

    function setUp() public override {
        super.setUp();

        // Create a subVault (another MasterVault instance) with the same asset
        MasterVault subVaultImplementation = new MasterVault();
        UpgradeableBeacon subVaultBeacon = new UpgradeableBeacon(address(subVaultImplementation));

        BeaconProxyFactory subVaultProxyFactory = new BeaconProxyFactory();
        subVaultProxyFactory.initialize(address(subVaultBeacon));

        bytes32 salt = keccak256("subvault");
        address subVaultProxyAddress = subVaultProxyFactory.createProxy(salt);
        subVault = MasterVault(subVaultProxyAddress);

        subVault.initialize(IERC20(address(token)), "Sub Vault Token", "sST", address(this));
        subVault.unpause();
    }

    function test_setSubVault() public {
        // Setup: User deposits into main vault first
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 100;
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        assertEq(address(vault.subVault()), address(0), "SubVault should be zero address initially");
        assertEq(token.balanceOf(address(vault)), depositAmount, "Main vault should hold tokens");

        // Set subVault with minSubVaultExchRateWad = 1e18 (1:1 ratio)
        vm.expectEmit(true, true, true, true);
        emit SubvaultChanged(address(0), address(subVault));
        vault.setSubVault(IERC4626(address(subVault)), 1e18);

        assertEq(address(vault.subVault()), address(subVault), "SubVault should be set");
        assertEq(token.balanceOf(address(vault)), 0, "Main vault should have no tokens");
        assertEq(token.balanceOf(address(subVault)), depositAmount, "SubVault should hold the tokens");
        assertEq(subVault.balanceOf(address(vault)), depositAmount, "Main vault should have subVault shares");
    }

    function test_setSubVault_revert_SubVaultAlreadySet() public {
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), 100);
        vault.deposit(100, user);
        vm.stopPrank();

        vault.setSubVault(IERC4626(address(subVault)), 1e18);

        // Try to set subVault again
        MasterVault anotherSubVault = new MasterVault();

        vm.expectRevert(MasterVault.SubVaultAlreadySet.selector);
        vault.setSubVault(IERC4626(address(anotherSubVault)), 1e18);
    }

    function test_setSubVault_revert_SubVaultAssetMismatch() public {
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), 100);
        vault.deposit(100, user);
        vm.stopPrank();

        // Create a subVault with different asset
        TestERC20 differentToken = new TestERC20();
        MasterVault differentAssetVault = new MasterVault();

        vm.expectRevert(MasterVault.SubVaultAssetMismatch.selector);
        vault.setSubVault(IERC4626(address(differentAssetVault)), 1e18);
    }

    function test_setSubVault_revert_NewSubVaultExchangeRateTooLow() public {
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), 100);
        vault.deposit(100, user);
        vm.stopPrank();

        // Try to set with unreasonably high minSubVaultExchRateWad (2e18 means expecting 2 subVault shares per 1 main vault share)
        vm.expectRevert(MasterVault.NewSubVaultExchangeRateTooLow.selector);
        vault.setSubVault(IERC4626(address(subVault)), 2e18);
    }

    function test_revokeSubVault() public {
        // Setup: Set subVault first
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 100;
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        vault.setSubVault(IERC4626(address(subVault)), 1e18);

        assertEq(address(vault.subVault()), address(subVault), "SubVault should be set");
        assertEq(token.balanceOf(address(vault)), 0, "Main vault should have no tokens");
        assertEq(token.balanceOf(address(subVault)), depositAmount, "SubVault should hold tokens");

        // Revoke subVault with minAssetExchRateWad = 1e18 (expecting 1:1 ratio)
        vm.expectEmit(true, true, true, true);
        emit SubvaultChanged(address(subVault), address(0));
        vault.revokeSubVault(1e18);

        assertEq(address(vault.subVault()), address(0), "SubVault should be zero address");
        assertEq(token.balanceOf(address(vault)), depositAmount, "Main vault should have tokens back");
        assertEq(token.balanceOf(address(subVault)), 0, "SubVault should have no tokens");
        assertEq(subVault.balanceOf(address(vault)), 0, "Main vault should have no subVault shares");
    }

    function test_revokeSubVault_revert_NoExistingSubVault() public {
        vm.expectRevert(MasterVault.NoExistingSubVault.selector);
        vault.revokeSubVault(1e18);
    }

    function test_revokeSubVault_revert_SubVaultExchangeRateTooLow() public {
        // Setup: Set subVault first
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), 100);
        vault.deposit(100, user);
        vm.stopPrank();

        vault.setSubVault(IERC4626(address(subVault)), 1e18);

        // Try to revoke with unreasonably high minAssetExchRateWad
        vm.expectRevert(MasterVault.SubVaultExchangeRateTooLow.selector);
        vault.revokeSubVault(2e18);
    }

    function test_setSubVault_revert_NotVaultManager() public {
        vm.prank(user);
        vm.expectRevert();
        vault.setSubVault(IERC4626(address(subVault)), 1e18);
    }

    function test_revokeSubVault_revert_NotVaultManager() public {
        // Setup: Set subVault first
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), 100);
        vault.deposit(100, user);
        vm.stopPrank();

        vault.setSubVault(IERC4626(address(subVault)), 1e18);

        // Try to revoke as non-vault-manager
        vm.prank(user);
        vm.expectRevert();
        vault.revokeSubVault(1e18);
    }

    event SubvaultChanged(address indexed oldSubVault, address indexed newSubVault);
}
