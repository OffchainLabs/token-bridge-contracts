// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultScenarioCoreTest } from "./MasterVaultScenarioCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario10Test is MasterVaultScenarioCoreTest {
    address public userC = address(0xC);
    uint256 public userCInitialBalance;

    /// @dev Scenario: Deposit during unrealized profit (before claim)
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// Vault wins 100 USDC (profit exists but not claimed yet)
    /// User C deposits 100 USDC
    /// Beneficiary claims profit
    /// All users redeem
    /// Expected: New depositor pays fair price for unrealized profits, all get back what they deposited
    function test_scenario10_depositDuringUnrealizedProfit() public {
        vault.setPerformanceFee(true);

        // Setup: Mint tokens for users
        _mintTokens(userA, 100);
        _mintTokens(userB, 300);
        vm.prank(userC);
        token.mint(100);
        userCInitialBalance = token.balanceOf(userC);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB = _deposit(userB, 300);

        // Verify intermediate state 1
        user = userA;
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 401,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 400,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        user = vm.addr(1);

        // Step 3: Vault wins 100 USDC (profit not claimed yet)
        _simulateProfit(100);

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: User C deposits 100 USDC during unrealized profit
        // With perf fees on, C should get shares based on principal (401), not total assets (501)
        // This protects C from paying for unrealized profits
        uint256 sharesC = _deposit(userC, 100);

        // C should get 100 * DEAD_SHARES because they deposit at principal value
        assertEq(sharesC, 100 * DEAD_SHARES, "User C should get 100 shares at principal price");

        // After C's deposit
        assertEq(vault.totalAssets(), 601, "Vault should have 601 USDC total");
        assertEq(vault.totalSupply(), 501 * DEAD_SHARES, "Total supply should be 501 shares");
        assertEq(vault.totalProfit(), 100, "Profit should still be 100 USDC");

        // Step 5: Beneficiary claims profit
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");
        assertEq(vault.totalProfit(), 0, "Profit should be 0 after claim");

        vm.stopPrank();

        // Step 6: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 7: User B redeems all shares
        uint256 assetsReceivedB = _redeem(userB, sharesB);

        // Step 8: User C redeems all shares
        vm.prank(userC);
        vault.transfer(user, sharesC);

        vm.startPrank(user);
        uint256 assetsReceivedC = vault.redeem(sharesC);
        token.transfer(userC, assetsReceivedC);
        vm.stopPrank();

        // Verify final state
        _checkState(
            State({
                userShares: 0,
                masterVaultTotalAssets: 1,
                masterVaultTotalSupply: DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );

        // All users should get back what they deposited (no loss for anyone)
        assertEq(assetsReceivedA, 100, "User A should receive 100 USDC");
        assertEq(assetsReceivedB, 300, "User B should receive 300 USDC");
        assertEq(assetsReceivedC, 100, "User C should receive 100 USDC");

        // Verify final holdings
        assertEq(token.balanceOf(userA), userAInitialBalance, "User A balance should be unchanged");
        assertEq(token.balanceOf(userB), userBInitialBalance, "User B balance should be unchanged");
        assertEq(token.balanceOf(userC), userCInitialBalance, "User C balance should be unchanged");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");
    }

    /// @dev Scenario: Deposit during unrealized profit (before claim), 100% allocation
    function test_scenario10_depositDuringUnrealizedProfit_100PercentAllocation() public {
        vault.setPerformanceFee(true);

        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        _mintTokens(userA, 100);
        _mintTokens(userB, 300);
        vm.prank(userC);
        token.mint(100);
        userCInitialBalance = token.balanceOf(userC);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB = _deposit(userB, 300);

        vault.rebalance(0);

        // Verify intermediate state 1
        user = userA;
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 401,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 400,
                subVaultTotalAssets: 400,
                subVaultTotalSupply: 400,
                subVaultTokenBalance: 400
            })
        );
        user = vm.addr(1);

        // Step 3: Subvault wins 100 USDC (profit not claimed yet)
        _simulateProfit(100);

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: User C deposits 100 USDC during unrealized profit
        uint256 sharesC = _deposit(userC, 100);

        vm.warp(block.timestamp + 2);
        vault.rebalance(0);

        // C should get 100 * DEAD_SHARES because they deposit at principal value
        assertEq(sharesC, 100 * DEAD_SHARES, "User C should get 100 shares at principal price");

        // After C's deposit and rebalance
        assertEq(vault.totalAssets(), 601, "Vault should have 601 USDC total");
        assertEq(vault.totalSupply(), 501 * DEAD_SHARES, "Total supply should be 501 shares");

        // Step 5: Beneficiary claims profit
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        vm.stopPrank();

        // Step 6: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 7: User B redeems all shares
        uint256 assetsReceivedB = _redeem(userB, sharesB);

        // Step 8: User C redeems all shares
        vm.prank(userC);
        vault.transfer(user, sharesC);

        vm.startPrank(user);
        uint256 assetsReceivedC = vault.redeem(sharesC);
        token.transfer(userC, assetsReceivedC);
        vm.stopPrank();

        // Verify final state
        _checkState(
            State({
                userShares: 0,
                masterVaultTotalAssets: 1,
                masterVaultTotalSupply: DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );

        // All users should get back what they deposited
        assertEq(assetsReceivedA, 100, "User A should receive 100 USDC");
        assertEq(assetsReceivedB, 300, "User B should receive 300 USDC");
        assertEq(assetsReceivedC, 100, "User C should receive 100 USDC");

        // Verify final holdings
        assertEq(token.balanceOf(userA), userAInitialBalance, "User A balance should be unchanged");
        assertEq(token.balanceOf(userB), userBInitialBalance, "User B balance should be unchanged");
        assertEq(token.balanceOf(userC), userCInitialBalance, "User C balance should be unchanged");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");
    }
}
