// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultScenarioCoreTest } from "./MasterVaultScenarioCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MathUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract MasterVaultScenario08Test is MasterVaultScenarioCoreTest {
    /// @dev Scenario: Profit claim, loss, then additional deposit before redemptions
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// Vault wins 100 USDC
    /// Beneficiary claims 100 USDC
    /// Vault loses 100 USDC (25% loss)
    /// User B deposits 300 USDC more
    /// User A redeems all shares
    /// User B redeems all shares
    /// Expected: User B gets better price on second deposit due to loss, both users share final state
    function test_scenario08_depositAfterLoss() public {
        vault.setPerformanceFee(true);

        // Setup: Mint tokens for users
        _mintTokens(userA, 100);
        _mintTokens(userB, 600);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB1 = _deposit(userB, 300);

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
        assertEq(vault.balanceOf(userB), 300 * DEAD_SHARES, "User B initial shares mismatch");
        user = vm.addr(1);

        // Step 3: Vault wins 100 USDC
        _simulateProfit(100);

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: Beneficiary claims profit
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        vm.stopPrank();

        // Step 5: Vault loses 100 USDC (25% loss)
        _simulateLoss(100);

        assertEq(vault.totalAssets(), 301, "Vault should have 301 USDC after loss");

        // Step 6: User B deposits 300 USDC more (at discounted share price due to loss)
        uint256 sharesB2 = _deposit(userB, 300);

        // Calculate expected shares for second deposit
        // After loss, totalAssets = 301, totalSupply = 401 * DEAD_SHARES
        // shares = 300 * 401 * DEAD_SHARES / 301 ≈ 399.67 * DEAD_SHARES
        uint256 expectedSharesB2 = (300 * 401 * DEAD_SHARES) / 301;
        assertEq(sharesB2, expectedSharesB2, "User B second deposit shares mismatch");

        uint256 totalSharesB = sharesB1 + sharesB2;
        assertEq(vault.balanceOf(userB), totalSharesB, "User B total shares mismatch");

        // Verify intermediate state 2
        user = userA;
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 601,
                masterVaultTotalSupply: (401 * DEAD_SHARES) + expectedSharesB2,
                masterVaultTokenBalance: 600,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        user = vm.addr(1);

        // Step 7: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 8: User B redeems all shares
        uint256 assetsReceivedB = _redeem(userB, totalSharesB);

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

        // Calculate expected redemption amounts based on share proportions
        uint256 totalSupply = (401 * DEAD_SHARES) + expectedSharesB2;
        uint256 expectedAssetsA = (601 * sharesA) / totalSupply;
        uint256 expectedAssetsB = (601 * totalSharesB) / totalSupply;

        // Verify user holdings
        assertEq(assetsReceivedA, expectedAssetsA, "User A redemption mismatch");
        assertEq(assetsReceivedB, expectedAssetsB, "User B redemption mismatch");

        // Verify exact final holdings
        assertEq(assetsReceivedA, 75, "User A should receive exactly 75 USDC");
        assertEq(assetsReceivedB, 525, "User B should receive exactly 525 USDC");

        // Verify losses/gains
        assertEq(100 - assetsReceivedA, 25, "User A should lose exactly 25 USDC");
        assertEq(600 - assetsReceivedB, 75, "User B should lose exactly 75 USDC");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should gain exactly 100 USDC");

        _checkHoldings(
            userAInitialBalance - 25,
            userBInitialBalance - 75,
            100
        );
    }

    /// @dev Scenario: Profit claim, loss, then additional deposit before redemptions, 100% allocation
    function test_scenario08_depositAfterLoss_100PercentAllocation() public {
        vault.setPerformanceFee(true);

        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        _mintTokens(userA, 100);
        _mintTokens(userB, 600);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB1 = _deposit(userB, 300);

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
        assertEq(vault.balanceOf(userB), 300 * DEAD_SHARES, "User B initial shares mismatch");
        user = vm.addr(1);

        // Step 3: Subvault wins 100 USDC
        _simulateProfit(100);

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: Beneficiary claims profit
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        vm.stopPrank();

        // Step 5: Subvault loses 100 USDC (25% loss)
        _simulateLoss(100);

        assertEq(vault.totalAssets(), 301, "Vault should have 301 USDC after loss");

        // Step 6: User B deposits 300 USDC more
        uint256 sharesB2 = _deposit(userB, 300);

        vm.warp(block.timestamp + 2);
        vault.rebalance(0);

        // Calculate expected shares for second deposit
        // After loss, totalAssets = 301, totalSupply = 401 * DEAD_SHARES
        // shares = 300 * 401 * DEAD_SHARES / 301 ≈ 399.67 * DEAD_SHARES
        uint256 expectedSharesB2 = (300 * 401 * DEAD_SHARES) / 301;
        assertEq(sharesB2, expectedSharesB2, "User B second deposit shares mismatch");

        uint256 totalSharesB = sharesB1 + sharesB2;
        assertEq(vault.balanceOf(userB), totalSharesB, "User B total shares mismatch");

        // Step 7: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 8: User B redeems all shares
        uint256 assetsReceivedB = _redeem(userB, totalSharesB);

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

        // Calculate expected redemption amounts based on share proportions
        uint256 totalSupply = (401 * DEAD_SHARES) + expectedSharesB2;
        uint256 expectedAssetsA = (601 * sharesA) / totalSupply;
        uint256 expectedAssetsB = (601 * totalSharesB) / totalSupply;

        // Verify redemption amounts
        assertEq(assetsReceivedA, expectedAssetsA, "User A redemption mismatch");
        assertEq(assetsReceivedB, expectedAssetsB, "User B redemption mismatch");

        // Verify exact final holdings
        assertEq(assetsReceivedA, 75, "User A should receive exactly 75 USDC");
        assertEq(assetsReceivedB, 525, "User B should receive exactly 525 USDC");

        // Verify losses/gains
        assertEq(100 - assetsReceivedA, 25, "User A should lose exactly 25 USDC");
        assertEq(600 - assetsReceivedB, 75, "User B should lose exactly 75 USDC");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should gain exactly 100 USDC");

        _checkHoldings(
            userAInitialBalance - 25,
            userBInitialBalance - 75,
            100
        );
    }
}
