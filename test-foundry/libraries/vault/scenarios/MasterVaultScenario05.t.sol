// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario05Test is MasterVaultCoreTest {
    address public userA = address(0xA);
    address public userB = address(0xB);
    address public beneficiaryAddress = address(0x9999);

    function setUp() public override {
        super.setUp();
        // Enable performance fee for this scenario
        vault.setPerformanceFee(true);
        vault.setBeneficiary(beneficiaryAddress);
    }

    /// @dev Scenario: Complex scenario with profits, fees, second deposit, full redemption, third deposit, and losses
    /// Steps 1-4: Initial deposits, profit, fee claim
    /// Steps 5-8: Second deposits and full redemption
    /// Steps 9-13: Third deposits, losses, and final redemption
    /// Expected: Beneficiary keeps profits, users share losses proportionally
    function test_scenario05_profitThenLoss() public {
        // Setup: Mint tokens for users (300 total each: 100+100+100 for A, 300+300+300 for B)
        vm.prank(userA);
        token.mint(300);
        vm.prank(userB);
        token.mint(900);

        uint256 userAInitialBalance = token.balanceOf(userA);
        uint256 userBInitialBalance = token.balanceOf(userB);

        // Step 1: User A deposits 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        vault.deposit(100, userA);
        vm.stopPrank();

        // Step 2: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        vault.deposit(300, userB);
        vm.stopPrank();

        assertEq(vault.totalPrincipal(), 400, "Total principal should be 400 after first deposits");
        assertEq(vault.totalAssets(), 400, "Total assets should be 400 after first deposits");

        // Step 3: Vault wins 100 USDC
        vm.prank(address(vault));
        token.mint(100);

        assertEq(vault.totalAssets(), 500, "Vault should have 500 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: Claim fees
        vault.withdrawPerformanceFees();

        assertEq(vault.totalAssets(), 400, "Vault should have 400 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        // Step 5: User A deposits another 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        vault.deposit(100, userA);
        vm.stopPrank();

        // Step 6: User B deposits another 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        vault.deposit(300, userB);
        vm.stopPrank();

        assertEq(
            vault.totalPrincipal(),
            800,
            "Total principal should be 800 after second deposits"
        );
        assertEq(vault.totalAssets(), 800, "Total assets should be 800 after second deposits");

        // Step 7: User A redeems 200 shares
        vm.prank(userA);
        vault.redeem(200, userA, userA);

        // Step 8: User B redeems 600 shares
        vm.prank(userB);
        vault.redeem(600, userB, userB);

        assertEq(vault.totalPrincipal(), 0, "Total principal should be 0 after second redemptions");
        assertEq(vault.totalAssets(), 0, "Vault should be empty after second redemptions");
        assertEq(vault.totalSupply(), 0, "Total supply should be 0 after second redemptions");

        // Step 9: User A deposits 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        vault.deposit(100, userA);
        vm.stopPrank();

        // Step 10: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        vault.deposit(300, userB);
        vm.stopPrank();

        assertEq(vault.totalPrincipal(), 400, "Total principal should be 400 after third deposits");
        assertEq(vault.totalAssets(), 400, "Total assets should be 400 after third deposits");

        // Step 11: Vault loses 100 USDC (25% loss)
        vm.prank(address(vault));
        token.transfer(address(0xdead), 100);

        assertEq(vault.totalAssets(), 300, "Vault should have 300 USDC after loss");
        assertEq(vault.totalPrincipal(), 400, "Total principal should still be 400");

        // Step 12: User A redeems 100 shares
        vm.prank(userA);
        uint256 assetsReceivedA = vault.redeem(100, userA, userA);

        // Step 13: User B redeems 300 shares
        vm.prank(userB);
        uint256 assetsReceivedB = vault.redeem(300, userB, userB);

        // Verify final state
        assertEq(vault.totalPrincipal(), 100, "Total principal should be 100");
        assertEq(vault.totalAssets(), 0, "Vault assets should be 0");
        assertEq(vault.totalSupply(), 0, "Total supply should be 0");
        assertEq(vault.sharePrice(), 1e18, "Share price should be 1e18");

        // Verify user holdings change
        // User A: deposited 300 total, received back 200 (from step 7) + 75 (from step 12) = 275, loss = 25
        // User B: deposited 900 total, received back 600 (from step 8) + 225 (from step 13) = 825, loss = 75
        assertEq(token.balanceOf(userA), userAInitialBalance - 25, "User A should lose 25 USDC");
        assertEq(token.balanceOf(userB), userBInitialBalance - 75, "User B should lose 75 USDC");

        // Verify assets received in final redemption
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC in final redemption");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC in final redemption");

        // Verify beneficiary still has profits
        assertEq(
            token.balanceOf(beneficiaryAddress),
            100,
            "Beneficiary should have 100 USDC (all profits)"
        );
    }
}
