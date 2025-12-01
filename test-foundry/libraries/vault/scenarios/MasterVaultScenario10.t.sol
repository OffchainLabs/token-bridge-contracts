// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario10Test is MasterVaultCoreTest {
    address public userA = address(0xA);
    address public userB = address(0xB);

    function setUp() public override {
        super.setUp();
        // Performance fee is disabled by default - this makes the vault vulnerable
    }

    /// @dev Scenario 10: First depositor attack when performance fee is DISABLED
    /// This test demonstrates the vulnerability that exists when perf fees are off
    /// User A deposits 1 USDC, attacker donates 1M USDC, User B deposits 100 USDC but gets 0 shares
    /// User A redeems and steals User B's funds
    /// This is why the vault is paused by default on deployment
    function test_scenario10_firstDepositorAttackVulnerability() public {
        // Setup: Mint tokens for users
        vm.prank(userA);
        token.mint(1);
        vm.prank(userB);
        token.mint(100);

        uint256 userAInitialBalance = token.balanceOf(userA);
        uint256 userBInitialBalance = token.balanceOf(userB);

        // Step 1: User A (attacker) deposits 1 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 1);
        uint256 sharesA = vault.deposit(1, userA);
        vm.stopPrank();

        assertEq(sharesA, 1, "User A should receive 1 share");
        assertEq(vault.totalSupply(), 1, "Total supply should be 1");
        assertEq(vault.totalAssets(), 1, "Total assets should be 1");
        assertEq(vault.totalPrincipal(), int256(1), "Total principal should be 1");
        assertEq(vault.sharePrice(), 1e18, "Share price should be 1e18");

        // Step 2: Attacker (or MEV bot) donates 1,000,000 USDC to inflate share price
        vm.prank(address(vault));
        token.mint(1_000_000);

        assertEq(vault.totalAssets(), 1_000_001, "Vault should have 1,000,001 USDC after donation");
        assertEq(vault.totalPrincipal(), int256(1), "Total principal should still be 1");
        assertEq(vault.totalProfit(), 1_000_000, "Total profit should be 1,000,000 USDC");
        // Without perf fee protection, share price inflates massively
        assertEq(vault.sharePrice(), 1_000_001 * 1e18, "Share price should be 1,000,001 * 1e18");

        // Step 3: User B (victim) deposits 100 USDC but receives 0 shares due to rounding
        vm.startPrank(userB);
        token.approve(address(vault), 100);
        uint256 sharesB = vault.deposit(100, userB);
        vm.stopPrank();

        // User B gets 0 shares: 100 / 1,000,001 rounds down to 0
        assertEq(sharesB, 0, "User B should receive 0 shares due to rounding (100 / 1,000,001 = 0)");
        assertEq(vault.totalSupply(), 1, "Total supply should still be 1 (only attacker has shares)");
        assertEq(vault.totalAssets(), 1_000_101, "Total assets should be 1,000,101");
        assertEq(vault.totalPrincipal(), int256(101), "Total principal should be 101");

        // Step 4: User A (attacker) redeems 1 share and steals all funds
        vm.prank(userA);
        uint256 assetsReceivedA = vault.redeem(sharesA, userA, userA);

        // User A owns all shares, so gets all assets
        assertEq(assetsReceivedA, 1_000_101, "User A should receive all 1,000,101 USDC");

        // Verify final state
        assertEq(vault.totalPrincipal(), int256(-1_000_000), "Total principal should be -1,000,000");
        assertEq(vault.totalAssets(), 0, "Vault assets should be 0");
        assertEq(vault.totalSupply(), 0, "Total supply should be 0");
        assertEq(vault.sharePrice(), 1e18, "Share price should be 1e18");

        // Verify user holdings change - User A profits, User B loses
        // User A: deposited 1, received back 1,000,101, profit = 1,000,100
        // User B: deposited 100, received back 0, loss = 100
        assertEq(token.balanceOf(userA), userAInitialBalance + 1_000_100, "User A should gain 1,000,100 USDC");
        assertEq(token.balanceOf(userB), userBInitialBalance - 100, "User B should lose 100 USDC");

        // Verify no beneficiary involved
        assertEq(token.balanceOf(address(0x9999)), 0, "Beneficiary should have 0 USDC");
    }

    /// @dev This test proves why the vault MUST be paused by default on deployment
    /// The pause mechanism gives the owner time to:
    /// 1. Enable performance fees (recommended)
    /// 2. Make an initial deposit to set a fair share price
    /// 3. Configure other security settings
    /// Before allowing public deposits
}
