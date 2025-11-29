// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario07Test is MasterVaultCoreTest {
    address public userA = address(0xA);
    address public userB = address(0xB);
    address public beneficiaryAddress = address(0x9999);

    function setUp() public override {
        super.setUp();
        // Enable performance fee for this scenario
        vault.setPerformanceFee(true);
        vault.setBeneficiary(beneficiaryAddress);
    }

    /// @dev Scenario: Profit, fee claim, loss, redemption, then new deposit and redemption
    /// Steps 1-7: Initial deposits, profit, fee claim, loss, full redemption
    /// Steps 8-9: User A deposits and redeems again
    /// Expected: Beneficiary keeps profits, users share initial loss, User A has no change on second round
    function test_scenario07_afterLossNewDeposit() public {
        // Setup: Mint tokens for users (200 for A: 100+100, 300 for B: 300)
        vm.prank(userA);
        token.mint(200);
        vm.prank(userB);
        token.mint(300);

        uint256 userAInitialBalance = token.balanceOf(userA);
        uint256 userBInitialBalance = token.balanceOf(userB);

        // Step 1: User A deposits 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        uint256 sharesA1 = vault.deposit(100, userA);
        vm.stopPrank();

        // Step 2: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        uint256 sharesB = vault.deposit(300, userB);
        vm.stopPrank();

        assertEq(vault.totalPrincipal(), 400, "Total principal should be 400");
        assertEq(vault.totalAssets(), 400, "Total assets should be 400");
        assertEq(sharesA1, 100, "User A should have 100 shares");
        assertEq(sharesB, 300, "User B should have 300 shares");

        // Step 3: Vault wins 100 USDC
        vm.prank(address(vault));
        token.mint(100);

        assertEq(vault.totalAssets(), 500, "Vault should have 500 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: Claim fees
        vault.withdrawPerformanceFees();

        assertEq(vault.totalAssets(), 400, "Vault should have 400 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        // Step 5: Vault loses 100 USDC (25% loss)
        vm.prank(address(vault));
        token.transfer(address(0xdead), 100);

        assertEq(vault.totalAssets(), 300, "Vault should have 300 USDC after loss");
        assertEq(vault.totalPrincipal(), 400, "Total principal should still be 400");

        // Step 6: User A redeems 100 shares
        vm.prank(userA);
        uint256 assetsReceivedA1 = vault.redeem(sharesA1, userA, userA);

        assertEq(assetsReceivedA1, 75, "User A should receive 75 USDC (25% loss)");

        // Step 7: User B redeems 300 shares
        vm.prank(userB);
        uint256 assetsReceivedB = vault.redeem(sharesB, userB, userB);

        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC (25% loss)");
        assertEq(vault.totalPrincipal(), 100, "Total principal should be 100");
        assertEq(vault.totalAssets(), 0, "Vault should be empty");
        assertEq(vault.totalSupply(), 0, "Total supply should be 0");

        // Step 8: User A deposits 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        uint256 sharesA2 = vault.deposit(100, userA);
        vm.stopPrank();

        assertEq(sharesA2, 100, "User A should receive 100 shares for second deposit");
        assertEq(vault.totalPrincipal(), 200, "Total principal should be 200");
        assertEq(vault.totalAssets(), 100, "Total assets should be 100");

        // Step 9: User A redeems 100 shares
        vm.prank(userA);
        uint256 assetsReceivedA2 = vault.redeem(sharesA2, userA, userA);

        assertEq(assetsReceivedA2, 100, "User A should receive 100 USDC for second redemption");

        // Verify final state
        assertEq(vault.totalPrincipal(), 100, "Total principal should be 100");
        assertEq(vault.totalAssets(), 0, "Vault assets should be 0");
        assertEq(vault.totalSupply(), 0, "Total supply should be 0");
        assertEq(vault.sharePrice(), 1e18, "Share price should be 1e18");

        // Verify user holdings change
        // User A: deposited 200 total (100+100), received back 175 (75+100), loss = 25
        // User B: deposited 300, received back 225, loss = 75
        assertEq(token.balanceOf(userA), userAInitialBalance - 25, "User A should lose 25 USDC");
        assertEq(token.balanceOf(userB), userBInitialBalance - 75, "User B should lose 75 USDC");

        // Verify beneficiary keeps all profits
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC (all profits)");
    }
}
