// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario08Test is MasterVaultCoreTest {
    address public userA = address(0xA);
    address public userB = address(0xB);
    address public beneficiaryAddress = address(0x9999);

    function setUp() public override {
        super.setUp();
        // Enable performance fee for this scenario
        vault.setPerformanceFee(true);
        vault.setBeneficiary(beneficiaryAddress);
    }

    /// @dev Scenario: Profit, fee claim, loss, then User B deposits more before redemptions
    /// Steps 1-5: Initial deposits, profit, fee claim, loss
    /// Step 6: User B deposits more after the loss
    /// Steps 7-8: Both users redeem
    /// Expected: Beneficiary keeps profits, original users share loss, User B's new deposit is fine
    function test_scenario08_depositAfterLoss() public {
        // Setup: Mint tokens for users (100 for A, 600 for B: 300+300)
        vm.prank(userA);
        token.mint(100);
        vm.prank(userB);
        token.mint(600);

        uint256 userAInitialBalance = token.balanceOf(userA);
        uint256 userBInitialBalance = token.balanceOf(userB);

        // Step 1: User A deposits 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        uint256 sharesA = vault.deposit(100, userA);
        vm.stopPrank();

        // Step 2: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        uint256 sharesB1 = vault.deposit(300, userB);
        vm.stopPrank();

        assertEq(vault.totalPrincipal(), 400, "Total principal should be 400");
        assertEq(vault.totalAssets(), 400, "Total assets should be 400");
        assertEq(sharesA, 100, "User A should have 100 shares");
        assertEq(sharesB1, 300, "User B should have 300 shares initially");

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

        // At this point, sharePrice is 300/400 = 0.75e18 due to the loss
        // When User B deposits 300 USDC at sharePrice 0.75e18, they should get 300/0.75 = 400 shares

        // Step 6: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        uint256 sharesB2 = vault.deposit(300, userB);
        vm.stopPrank();

        assertEq(
            sharesB2,
            400,
            "User B should receive 400 shares for 300 USDC deposit at 0.75e18 sharePrice"
        );
        assertEq(vault.totalPrincipal(), 700, "Total principal should be 700");
        assertEq(vault.totalAssets(), 600, "Total assets should be 600");

        uint256 totalSharesB = sharesB1 + sharesB2;
        assertEq(totalSharesB, 700, "User B should have 700 total shares (300 + 400)");

        // Step 7: User A redeems 100 shares
        vm.prank(userA);
        uint256 assetsReceivedA = vault.redeem(sharesA, userA, userA);

        // Step 8: User B redeems 700 shares
        vm.prank(userB);
        uint256 assetsReceivedB = vault.redeem(totalSharesB, userB, userB);

        // Verify final state
        assertEq(vault.totalPrincipal(), 100, "Total principal should be 100");
        assertEq(vault.totalAssets(), 0, "Vault assets should be 0");
        assertEq(vault.totalSupply(), 0, "Total supply should be 0");
        assertEq(vault.sharePrice(), 1e18, "Share price should be 1e18");

        // Verify user holdings change
        // User A: deposited 100, received back 75, loss = 25
        // User B: deposited 600 (300+300), received back 525 (225+300), loss = 75
        assertEq(token.balanceOf(userA), userAInitialBalance - 25, "User A should lose 25 USDC");
        assertEq(token.balanceOf(userB), userBInitialBalance - 75, "User B should lose 75 USDC");

        // Verify assets received
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC");
        assertEq(
            assetsReceivedB,
            525,
            "User B should receive 525 USDC (225 from first 300 shares + 300 from 400 shares)"
        );

        // Verify beneficiary keeps all profits
        assertEq(
            token.balanceOf(beneficiaryAddress),
            100,
            "Beneficiary should have 100 USDC (all profits)"
        );
    }
}
