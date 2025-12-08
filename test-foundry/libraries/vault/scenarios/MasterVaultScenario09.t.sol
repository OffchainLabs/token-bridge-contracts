// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario09Test is MasterVaultCoreTest {
    address public userA = address(0xA);
    address public userB = address(0xB);
    address public beneficiaryAddress = address(0x9999);

    function setUp() public override {
        super.setUp();
        // Enable performance fee for this scenario
        vault.setPerformanceFee(true);
        vault.setBeneficiary(beneficiaryAddress);
    }

    /// @dev Scenario 9: First depositor attack protection when performance fee is enabled
    /// User A deposits 1 USDC, vault gains 1M USDC (attacker donation), User B deposits 100 USDC
    /// User A redeems 1 share, User B redeems all shares
    /// Expected: Performance fee mechanism prevents User A from extracting profit, both users break even
    function test_scenario09_performanceFeeProtection() public {
        // Setup: Mint tokens for users
        vm.prank(userA);
        token.mint(1);
        vm.prank(userB);
        token.mint(100);

        uint256 userAInitialBalance = token.balanceOf(userA);
        uint256 userBInitialBalance = token.balanceOf(userB);

        // Step 1: User A deposits 1 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 1);
        uint256 sharesA = vault.deposit(1, userA);
        vm.stopPrank();

        assertEq(sharesA, 1, "User A should receive 1 share");
        assertEq(vault.totalSupply(), 1, "Total supply should be 1");
        assertEq(vault.totalAssets(), 1, "Total assets should be 1");
        assertEq(vault.totalPrincipal(), int256(1), "Total principal should be 1");

        // Step 2: Vault wins 1,000,000 USDC (attacker donation attack)
        vm.prank(address(vault));
        token.mint(1_000_000);

        assertEq(vault.totalAssets(), 1_000_001, "Vault should have 1,000,001 USDC after profit");
        assertEq(vault.totalPrincipal(), int256(1), "Total principal should still be 1");
        assertEq(vault.totalProfit(), 1_000_000, "Total profit should be 1,000,000 USDC");
        // With perf fee enabled, share price is capped at 1e18
        assertEq(vault.sharePrice(), 1e18, "Share price should be capped at 1e18 with perf fee");

        // Step 3: User B deposits 100 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 100);
        uint256 sharesB = vault.deposit(100, userB);
        vm.stopPrank();

        // User B gets fair shares because share price is capped
        assertEq(sharesB, 100, "User B should receive 100 shares");
        assertEq(vault.totalSupply(), 101, "Total supply should be 101");
        assertEq(vault.totalAssets(), 1_000_101, "Total assets should be 1,000,101");
        assertEq(vault.totalPrincipal(), int256(101), "Total principal should be 101");

        // Step 4: User A redeems 1 share
        vm.prank(userA);
        uint256 assetsReceivedA = vault.redeem(sharesA, userA, userA);

        // User A gets back their principal, no profit due to perf fee protection
        // effectiveAssets = min(1_000_101, 101) = 101
        // assetsReceived = (1 * 101) / 101 = 1
        assertEq(assetsReceivedA, 1, "User A should receive 1 USDC (their principal only)");
        assertEq(vault.totalSupply(), 100, "Total supply should be 100");
        assertEq(vault.totalAssets(), 1_000_100, "Total assets should be 1,000,100");
        assertEq(vault.totalPrincipal(), int256(100), "Total principal should be 100");

        // Step 5: User B redeems 100 shares
        vm.prank(userB);
        uint256 assetsReceivedB = vault.redeem(sharesB, userB, userB);

        // User B gets back their principal
        // effectiveAssets = min(1_000_100, 100) = 100
        // assetsReceived = (100 * 100) / 100 = 100
        assertEq(assetsReceivedB, 100, "User B should receive 100 USDC (their principal only)");

        // Verify final state
        assertEq(vault.totalPrincipal(), int256(0), "Total principal should be 0");
        assertEq(
            vault.totalAssets(),
            1_000_000,
            "Vault assets should be 1,000,000 (the donated profit)"
        );
        assertEq(vault.totalSupply(), 0, "Total supply should be 0");
        assertEq(vault.sharePrice(), 1e18, "Share price should be 1e18");

        // Verify user holdings change
        // User A: deposited 1, received back 1, change = 0
        // User B: deposited 100, received back 100, change = 0
        assertEq(
            token.balanceOf(userA),
            userAInitialBalance,
            "User A should break even (0 change)"
        );
        assertEq(
            token.balanceOf(userB),
            userBInitialBalance,
            "User B should break even (0 change)"
        );

        // Verify beneficiary has not claimed fees yet
        assertEq(
            token.balanceOf(beneficiaryAddress),
            0,
            "Beneficiary should have 0 USDC (fees not claimed yet)"
        );

        // Verify the 1M USDC remains in vault as profit
        assertEq(vault.totalProfit(), 1_000_000, "Total profit should be 1,000,000 USDC");
    }
}
