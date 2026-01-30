// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultScenarioCoreTest } from "./MasterVaultScenarioCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MathUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract MasterVaultScenario05Test is MasterVaultScenarioCoreTest {
    /// @dev Scenario: Profit, fee claim, more deposits, redemptions, then loss and final redemptions
    /// Expected: Beneficiary keeps profits, users share final loss
    function test_scenario05_profitThenLoss() public {
        vault.setPerformanceFee(true);

        // Setup: Mint tokens for users (200 for A: 100+100, 600 for B: 300+300)
        _mintTokens(userA, 200);
        _mintTokens(userB, 600);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA1 = _deposit(userA, 100);

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
        user = vm.addr(1);

        // Step 3: Vault wins 100 USDC
        _simulateProfit(100);

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: Claim fees
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        vm.stopPrank();

        // Step 5: User A deposits another 100 USDC
        _deposit(userA, 100);

        // Step 6: User B deposits another 300 USDC
        _deposit(userB, 300);

        // Verify intermediate state 2
        user = userA;
        _checkState(
            State({
                userShares: 200 * DEAD_SHARES,
                masterVaultTotalAssets: 801,
                masterVaultTotalSupply: 801 * DEAD_SHARES,
                masterVaultTokenBalance: 800,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        user = vm.addr(1);

        // Step 7: User A redeems 200 shares
        _redeem(userA, 200 * DEAD_SHARES);

        // Step 8: User B redeems 600 shares
        _redeem(userB, 600 * DEAD_SHARES);

        // Verify intermediate state 3 (empty vault)
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

        // Step 9: User A deposits 100 USDC
        _deposit(userA, 100);

        // Step 10: User B deposits 300 USDC
        _deposit(userB, 300);

        // Verify intermediate state 4
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

        // Step 11: Vault loses 100 USDC (25% loss)
        _simulateLoss(100);

        assertEq(vault.totalAssets(), 301, "Vault should have 301 USDC after loss");

        // Step 12: User A redeems 100 shares
        uint256 assetsReceivedA = _redeem(userA, 100 * DEAD_SHARES);

        // Step 13: User B redeems 300 shares
        uint256 assetsReceivedB = _redeem(userB, 300 * DEAD_SHARES);

        // Verify final state
        _checkHoldings(userAInitialBalance - 25, userBInitialBalance - 75, 100);

        // Verify assets received
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC");
    }

    /// @dev Scenario: Profit, fee claim, more deposits, redemptions, then loss and final redemptions, 100% allocation
    function test_scenario05_profitThenLoss_100PercentAllocation() public {
        vault.setPerformanceFee(true);

        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        _mintTokens(userA, 200);
        _mintTokens(userB, 600);

        // Step 1: User A deposits 100 USDC
        _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        _deposit(userB, 300);

        vault.rebalance();

        // Step 3: Subvault wins 100 USDC
        _simulateProfit(100);

        // Step 4: Claim fees
        _distributePerformanceFee();

        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        vm.stopPrank();

        // Step 5: User A deposits another 100 USDC
        _deposit(userA, 100);

        // Step 6: User B deposits another 300 USDC
        _deposit(userB, 300);

        vm.warp(block.timestamp + 2);
        vault.rebalance();

        // Step 7: User A redeems 200 shares
        _redeem(userA, 200 * DEAD_SHARES);

        // Step 8: User B redeems 600 shares
        _redeem(userB, 600 * DEAD_SHARES);

        // Step 9: User A deposits 100 USDC
        _deposit(userA, 100);

        // Step 10: User B deposits 300 USDC
        _deposit(userB, 300);

        vm.warp(block.timestamp + 2);
        vault.rebalance();

        // Step 11: Subvault loses 100 USDC (25% loss)
        _simulateLoss(100);

        // Step 12: User A redeems 100 shares
        uint256 assetsReceivedA = _redeem(userA, 100 * DEAD_SHARES);

        // Step 13: User B redeems 300 shares
        uint256 assetsReceivedB = _redeem(userB, 300 * DEAD_SHARES);

        // Verify final state
        _checkHoldings(userAInitialBalance - 25, userBInitialBalance - 75, 100);
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC");
    }
}
