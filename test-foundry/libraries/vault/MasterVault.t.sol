// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import { TestERC20 } from "../../../contracts/tokenbridge/test/TestERC20.sol";
import { MockSubVault } from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxyFactory, ClonableBeaconProxy } from "../../../contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";

contract MasterVaultTest is Test {
    MasterVault public vault;
    TestERC20 public token;
    UpgradeableBeacon public beacon;
    BeaconProxyFactory public beaconProxyFactory;

    event SubvaultChanged(address indexed oldSubvault, address indexed newSubvault);

    address public user = address(0x1);
    string public name = "Master Test Token";
    string public symbol = "mTST";

    function setUp() public {
        token = new TestERC20();

        MasterVault implementation = new MasterVault();
        beacon = new UpgradeableBeacon(address(implementation));

        beaconProxyFactory = new BeaconProxyFactory();
        beaconProxyFactory.initialize(address(beacon));

        bytes32 salt = keccak256("test");
        address proxyAddress = beaconProxyFactory.createProxy(salt);
        vault = MasterVault(proxyAddress);

        vault.vaultInit(IERC20(address(token)), name, symbol, address(this));
    }

    function test_initialize() public {
        assertEq(address(vault.asset()), address(token), "Invalid asset");
        assertEq(vault.name(), name, "Invalid name");
        assertEq(vault.symbol(), symbol, "Invalid symbol");
        assertEq(vault.decimals(), token.decimals(), "Invalid decimals");
        assertEq(vault.totalSupply(), 0, "Invalid initial supply");
        assertEq(vault.totalAssets(), 0, "Invalid initial assets");
        assertEq(address(vault.subVault()), address(0), "SubVault should be zero initially");
    }

    function test_WithoutSubvault_deposit() public {
        assertEq(address(vault.subVault()), address(0), "SubVault should be zero initially");

        // user deposit 500 tokens to vault
        // by this test expec:
        //- user to receive 500 shares
        //- total shares supply to increase by 500
        //- total assets to increase by 500

        uint256 minShares = 0;

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);

        token.approve(address(vault), depositAmount);

        uint256 sharesBefore = vault.balanceOf(user);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();

        uint256 shares = vault.deposit(depositAmount, user, minShares);

        assertEq(vault.balanceOf(user), sharesBefore + shares, "Invalid user balance");
        assertEq(vault.totalSupply(), totalSupplyBefore + shares, "Invalid total supply");
        assertEq(vault.totalAssets(), totalAssetsBefore + depositAmount, "Invalid total assets");
        assertEq(token.balanceOf(user), 0, "User tokens should be transferred");

        vm.stopPrank();
    }

    function test_deposit_RevertTooFewSharesReceived() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        uint256 minShares = depositAmount * 2; // Unrealistic requirement

        token.approve(address(vault), depositAmount);

        vm.expectRevert(MasterVault.TooFewSharesReceived.selector);
        vault.deposit(depositAmount, user, minShares);

        vm.stopPrank();
    }

    function test_setSubvault() public {
        MockSubVault subVault = new MockSubVault(
            IERC20(address(token)),
            "Sub Vault Token",
            "svTST"
        );

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);
        vm.stopPrank();

        assertEq(address(vault.subVault()), address(0), "SubVault should be zero initially");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should equal deposit");

        uint256 minSubVaultExchRateWad = 1e18;

        vm.expectEmit(true, true, false, false);
        emit SubvaultChanged(address(0), address(subVault));

        vault.setSubVault(subVault, minSubVaultExchRateWad);

        assertEq(address(vault.subVault()), address(subVault), "SubVault should be set");
        assertEq(vault.subVaultExchRateWad(), 1e18, "Exchange rate should be 1:1 initially");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should remain the same");
        assertEq(subVault.balanceOf(address(vault)), depositAmount, "SubVault should have received assets");
    }

    function test_switchSubvault() public {
        MockSubVault oldSubVault = new MockSubVault(
            IERC20(address(token)),
            "Old Sub Vault",
            "osvTST"
        );

        MockSubVault newSubVault = new MockSubVault(
            IERC20(address(token)),
            "New Sub Vault",
            "nsvTST"
        );

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);
        vm.stopPrank();

        vault.setSubVault(oldSubVault, 1e18);

        assertEq(address(vault.subVault()), address(oldSubVault), "Old subvault should be set");
        assertEq(oldSubVault.balanceOf(address(vault)), depositAmount, "Old subvault should have assets");
        assertEq(newSubVault.balanceOf(address(vault)), 0, "New subvault should have no assets initially");

        uint256 minAssetExchRateWad = 1e18;
        uint256 minNewSubVaultExchRateWad = 1e18;

        vm.expectEmit(true, true, false, false);
        emit SubvaultChanged(address(oldSubVault), address(0));
        vm.expectEmit(true, true, false, false);
        emit SubvaultChanged(address(0), address(newSubVault));

        vault.switchSubVault(newSubVault, minAssetExchRateWad, minNewSubVaultExchRateWad);

        assertEq(address(vault.subVault()), address(newSubVault), "New subvault should be set");
        assertEq(vault.subVaultExchRateWad(), 1e18, "Exchange rate should remain 1:1");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should remain the same");
        assertEq(oldSubVault.balanceOf(address(vault)), 0, "Old subvault should have no assets");
        assertEq(newSubVault.balanceOf(address(vault)), depositAmount, "New subvault should have received assets");
    }

    function test_revokeSubvault() public {
        MockSubVault subVault = new MockSubVault(
            IERC20(address(token)),
            "Sub Vault Token",
            "svTST"
        );

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);
        vm.stopPrank();

        vault.setSubVault(subVault, 1e18);

        assertEq(address(vault.subVault()), address(subVault), "SubVault should be set");
        assertEq(subVault.balanceOf(address(vault)), depositAmount, "SubVault should have assets");
        assertEq(vault.subVaultExchRateWad(), 1e18, "Exchange rate should be 1:1");

        uint256 minAssetExchRateWad = 1e18;

        vm.expectEmit(true, true, false, false);
        emit SubvaultChanged(address(subVault), address(0));

        vault.revokeSubVault(minAssetExchRateWad);

        assertEq(address(vault.subVault()), address(0), "SubVault should be revoked");
        assertEq(vault.subVaultExchRateWad(), 1e18, "Exchange rate should reset to 1:1");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should remain the same");
        assertEq(subVault.balanceOf(address(vault)), 0, "SubVault should have no assets");
        assertEq(token.balanceOf(address(vault)), depositAmount, "MasterVault should have assets directly");
    }

    function test_WithoutSubvault_withdraw() public {
        uint256 maxSharesBurned = type(uint256).max;

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);

        uint256 withdrawAmount = depositAmount / 2;
        uint256 userSharesBefore = vault.balanceOf(user);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();

        uint256 shares = vault.withdraw(withdrawAmount, user, user, maxSharesBurned);

        assertEq(vault.balanceOf(user), userSharesBefore - shares, "User shares should decrease");
        assertEq(vault.totalSupply(), totalSupplyBefore - shares, "Total supply should decrease");
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount, "Total assets should decrease");
        assertEq(token.balanceOf(user), withdrawAmount, "User should receive withdrawn assets");
        assertEq(token.balanceOf(address(vault)), depositAmount - withdrawAmount, "Vault should have remaining assets");

        vm.stopPrank();
    }

    function test_WithSubvault_withdraw() public {
        MockSubVault subVault = new MockSubVault(
            IERC20(address(token)),
            "Sub Vault Token",
            "svTST"
        );

        vm.startPrank(user);
        token.mint();
        uint256 firstDepositAmount = token.balanceOf(user);
        token.approve(address(vault), firstDepositAmount);
        vault.deposit(firstDepositAmount, user, 0);
        vm.stopPrank();

        vault.setSubVault(subVault, 1e18);

        uint256 withdrawAmount = firstDepositAmount / 2;
        uint256 maxSharesBurned = type(uint256).max;

        vm.startPrank(user);
        uint256 userSharesBefore = vault.balanceOf(user);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 subVaultSharesBefore = subVault.balanceOf(address(vault));

        uint256 shares = vault.withdraw(withdrawAmount, user, user, maxSharesBurned);

        assertEq(vault.balanceOf(user), userSharesBefore - shares, "User shares should decrease");
        assertEq(vault.totalSupply(), totalSupplyBefore - shares, "Total supply should decrease");
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount, "Total assets should decrease");
        assertEq(token.balanceOf(user), withdrawAmount, "User should receive withdrawn assets");
        assertLt(subVault.balanceOf(address(vault)), subVaultSharesBefore, "SubVault shares should decrease");

        token.mint();
        uint256 secondDepositAmount = token.balanceOf(user) - withdrawAmount;
        token.approve(address(vault), secondDepositAmount);
        vault.deposit(secondDepositAmount, user, 0);

        vault.balanceOf(user);
        uint256 finalTotalAssets = vault.totalAssets();
        subVault.balanceOf(address(vault));

        vault.withdraw(finalTotalAssets, user, user, type(uint256).max);

        assertEq(vault.balanceOf(user), 0, "User should have no shares left");
        assertEq(vault.totalSupply(), 0, "Total supply should be zero");
        assertEq(vault.totalAssets(), 0, "Total assets should be zero");
        assertEq(token.balanceOf(user), firstDepositAmount + secondDepositAmount, "User should have all original tokens");
        assertEq(subVault.balanceOf(address(vault)), 0, "SubVault should have no shares left");

        vm.stopPrank();
    }

    function test_beaconUpgrade() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);
        vm.stopPrank();

        address oldImplementation = beacon.implementation();
        assertEq(oldImplementation, address(beacon.implementation()), "Should have initial implementation");

        MasterVault newImplementation = new MasterVault();
        beacon.upgradeTo(address(newImplementation));

        assertEq(beacon.implementation(), address(newImplementation), "Beacon should point to new implementation");
        assertTrue(beacon.implementation() != oldImplementation, "Implementation should have changed");

        assertEq(vault.name(), name, "Name should remain after upgrade");
    }

}
