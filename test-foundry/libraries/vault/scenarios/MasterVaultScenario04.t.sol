// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MathUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

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
        vault.deposit(100, userA);
        vm.stopPrank();

        // Step 2: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        vault.deposit(300, userB);
        vm.stopPrank();

        // Verify intermediate state 1
        user = userA;
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 400,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 400,
                masterVaultSubVaultShareBalance: 0,
                masterVaultTotalPrincipal: 400,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        assertEq(vault.balanceOf(userB), 300 * DEAD_SHARES, "User B shares mismatch");

        // Step 3: Vault wins 100 USDC (25% profit)
        token.mint(100);
        token.transfer(address(vault), 100);

        assertEq(vault.totalAssets(), 500, "Vault should have 500 USDC after profit");
        assertEq(
            vault.totalProfit(MathUpgradeable.Rounding.Down),
            100,
            "Total profit should be 100 USDC"
        );

        // Step 4: Claim fees
        vault.distributePerformanceFee();

        assertEq(vault.totalAssets(), 400, "Vault should have 400 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");
        assertEq(vault.totalPrincipal(), 400, "Total principal should still be 400");

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

        // Verify intermediate state 2
        _checkState(
            State({
                userShares: 200 * DEAD_SHARES,
                masterVaultTotalAssets: 800,
                masterVaultTotalSupply: 801 * DEAD_SHARES,
                masterVaultTokenBalance: 800,
                masterVaultSubVaultShareBalance: 0,
                masterVaultTotalPrincipal: 800,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        assertEq(vault.balanceOf(userB), 600 * DEAD_SHARES, "User B total shares mismatch");

        // Step 7: User A redeems all 200 shares
        vm.prank(userA);
        uint256 assetsReceivedA = vault.redeem(200 * DEAD_SHARES, userA, userA);

        // Step 8: User B redeems all 600 shares
        vm.prank(userB);
        uint256 assetsReceivedB = vault.redeem(600 * DEAD_SHARES, userB, userB);

        // Verify final state
        _checkState(
            State({
                userShares: 0,
                masterVaultTotalAssets: 0,
                masterVaultTotalSupply: DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 0,
                masterVaultTotalPrincipal: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );

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

    /// @dev Scenario: 2 users deposit, subvault gains profit, fees claimed, then users deposit again, 100% allocation
    function test_scenario04_secondDepositAfterFeeClaim_100PercentAllocation() public {
        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        vm.prank(userA);
        token.mint(200);
        vm.prank(userB);
        token.mint(600);

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

        // Verify intermediate state 1
        user = userA;
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 400,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 400,
                masterVaultTotalPrincipal: 400,
                subVaultTotalAssets: 400,
                subVaultTotalSupply: 400,
                subVaultTokenBalance: 400
            })
        );

        // Step 3: Subvault wins 100 USDC (25% profit)
        token.mint(100);
        token.transfer(address(vault.subVault()), 100);

        assertEq(vault.totalAssets(), 500, "Vault should have 500 USDC after profit");
        assertEq(
            vault.totalProfit(MathUpgradeable.Rounding.Down),
            100,
            "Total profit should be 100 USDC"
        );

        // Step 4: Claim fees
        vault.distributePerformanceFee();

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

        // Verify intermediate state 2
        _checkState(
            State({
                userShares: 200 * DEAD_SHARES,
                masterVaultTotalAssets: 800,
                masterVaultTotalSupply: 801 * DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 640, // 400 * 320 / 400 + 320
                masterVaultTotalPrincipal: 800,
                subVaultTotalAssets: 800,
                subVaultTotalSupply: 640,
                subVaultTokenBalance: 800
            })
        );

        // Step 7: User A redeems all 200 shares
        vm.prank(userA);
        uint256 assetsReceivedA = vault.redeem(200 * DEAD_SHARES, userA, userA);

        // Step 8: User B redeems all 600 shares
        vm.prank(userB);
        uint256 assetsReceivedB = vault.redeem(600 * DEAD_SHARES, userB, userB);

        // Verify final state
        _checkState(
            State({
                userShares: 0,
                masterVaultTotalAssets: 0,
                masterVaultTotalSupply: DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 0,
                masterVaultTotalPrincipal: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );

        // Verify user balances
        assertEq(token.balanceOf(userA), userAInitialBalance, "User A should have no gain/loss");
        assertEq(token.balanceOf(userB), userBInitialBalance, "User B should have no gain/loss");

        // Verify assets received
        assertEq(assetsReceivedA, 200, "User A should receive 200 USDC");
        assertEq(assetsReceivedB, 600, "User B should receive 600 USDC");
    }
}
