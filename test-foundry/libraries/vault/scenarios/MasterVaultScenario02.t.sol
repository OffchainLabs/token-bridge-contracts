// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario02Test is MasterVaultCoreTest {
    address public userA = address(0xA);
    address public userB = address(0xB);
    address public beneficiaryAddress = address(0x9999);

    function setUp() public override {
        super.setUp();
        // Enable performance fee for this scenario
        vault.setPerformanceFee(true);
        vault.setBeneficiary(beneficiaryAddress);
    }

    /// @dev Scenario: 2 users deposit, vault loses 100 USDC, users socialize losses
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// Vault loses 100 USDC (25% loss)
    /// User A redeems 100 shares, User B redeems 300 shares
    /// Expected: Users socialize the loss proportionally (25% each)
    function test_scenario02_socializeLosses() public {
        // Setup: Mint tokens for users
        vm.prank(userA);
        token.mint(100);
        vm.prank(userB);
        token.mint(300);

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
        uint256 sharesB = vault.deposit(300, userB);
        vm.stopPrank();

        // Verify intermediate state
        assertEq(vault.totalPrincipal(), 400, "Total principal should be 400");
        assertEq(vault.totalAssets(), 400, "Total assets should be 400");
        assertEq(sharesA, 100, "User A should have 100 shares");
        assertEq(sharesB, 300, "User B should have 300 shares");

        // Step 3: Vault loses 100 USDC (25% loss)
        vm.prank(address(vault));
        token.transfer(address(0xdead), 100);

        assertEq(vault.totalAssets(), 300, "Vault should have 300 USDC after loss");
        assertEq(vault.totalPrincipal(), 400, "Total principal should remain 400");

        // Step 4: User A redeems 100 shares
        vm.prank(userA);
        uint256 assetsReceivedA = vault.redeem(sharesA, userA, userA);

        // Step 5: User B redeems 300 shares
        vm.prank(userB);
        uint256 assetsReceivedB = vault.redeem(sharesB, userB, userB);

        // Verify final state
        assertEq(vault.totalPrincipal(), 100, "Total principal should be 100");
        assertEq(vault.totalAssets(), 0, "Vault assets should be 0");
        assertEq(vault.totalSupply(), 0, "Total supply should be 0");
        assertEq(vault.sharePrice(), 1e18, "Share price should be 1e18");

        // Verify user holdings change
        assertEq(
            token.balanceOf(userA),
            userAInitialBalance - 25,
            "User A should lose 25 USDC (25% of 100)"
        );
        assertEq(
            token.balanceOf(userB),
            userBInitialBalance - 75,
            "User B should lose 75 USDC (25% of 300)"
        );

        // Verify assets received
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC (100 - 25)");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC (300 - 75)");

        // Verify beneficiary received nothing
        assertEq(
            token.balanceOf(beneficiaryAddress),
            0,
            "Beneficiary should have 0 (nothing claimed)"
        );
    }
}
