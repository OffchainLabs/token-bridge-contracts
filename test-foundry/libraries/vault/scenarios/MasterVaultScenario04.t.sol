// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario04Test is MasterVaultCoreTest {
    address public userA = address(0xA);
    address public userB = address(0xB);
    address public beneficiaryAddress = address(0x9999);

    function setUp() public override {
        super.setUp();
        // Enable performance fee for this scenario
        vault.setPerformanceFee(true);
        vault.setBeneficiary(beneficiaryAddress);
    }

    /// @dev Scenario: 2 users deposit, vault gains profit, fees claimed, then users deposit again
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// Vault gains 100 USDC profit
    /// Beneficiary claims fees (100 USDC)
    /// User A deposits another 100 USDC, User B deposits another 300 USDC
    /// User A redeems all 200 shares, User B redeems all 600 shares
    /// Expected: Beneficiary keeps profits, users get all deposits back
    function test_scenario04_secondDepositAfterFeeClaim() public {
        // Setup: Mint tokens for users (800 total: 200 for A, 600 for B)
        vm.prank(userA);
        token.mint(200);
        vm.prank(userB);
        token.mint(600);

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
        uint256 sharesB1 = vault.deposit(300, userB);
        vm.stopPrank();

        assertEq(vault.totalPrincipal(), 400, "Total principal should be 400");
        assertEq(vault.totalAssets(), 400, "Total assets should be 400");
        assertEq(sharesA1, 100, "User A should have 100 shares");
        assertEq(sharesB1, 300, "User B should have 300 shares");

        // Step 3: Vault wins 100 USDC (25% profit)
        vm.prank(address(vault));
        token.mint(100);

        assertEq(vault.totalAssets(), 500, "Vault should have 500 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: Claim fees
        vault.withdrawPerformanceFees();

        assertEq(vault.totalAssets(), 400, "Vault should have 400 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");
        assertEq(vault.totalPrincipal(), 400, "Total principal should still be 400");

        // Step 5: User A deposits another 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        uint256 sharesA2 = vault.deposit(100, userA);
        vm.stopPrank();

        // Step 6: User B deposits another 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        uint256 sharesB2 = vault.deposit(300, userB);
        vm.stopPrank();

        assertEq(vault.totalPrincipal(), 800, "Total principal should be 800");
        assertEq(vault.totalAssets(), 800, "Total assets should be 800");
        assertEq(sharesA2, 100, "User A second deposit should give 100 shares");
        assertEq(sharesB2, 300, "User B second deposit should give 300 shares");

        uint256 totalSharesA = sharesA1 + sharesA2;
        uint256 totalSharesB = sharesB1 + sharesB2;
        assertEq(totalSharesA, 200, "User A should have 200 total shares");
        assertEq(totalSharesB, 600, "User B should have 600 total shares");

        // Step 7: User A redeems 200 shares
        vm.prank(userA);
        uint256 assetsReceivedA = vault.redeem(totalSharesA, userA, userA);

        // Step 8: User B redeems 600 shares
        vm.prank(userB);
        uint256 assetsReceivedB = vault.redeem(totalSharesB, userB, userB);

        // Verify final state
        assertEq(vault.totalPrincipal(), 0, "Total principal should be 0");
        assertEq(vault.totalAssets(), 0, "Vault assets should be 0");
        assertEq(vault.totalSupply(), 0, "Total supply should be 0");
        assertEq(vault.sharePrice(), 1e18, "Share price should be 1e18");

        // Verify user holdings change (no change - they get all deposits back)
        assertEq(token.balanceOf(userA), userAInitialBalance, "User A should have no gain/loss");
        assertEq(token.balanceOf(userB), userBInitialBalance, "User B should have no gain/loss");

        // Verify assets received
        assertEq(assetsReceivedA, 200, "User A should receive 200 USDC (all deposits)");
        assertEq(assetsReceivedB, 600, "User B should receive 600 USDC (all deposits)");

        // Verify beneficiary still has all profits
        assertEq(
            token.balanceOf(beneficiaryAddress),
            100,
            "Beneficiary should have 100 USDC (all profits)"
        );
    }
}
