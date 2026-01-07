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

        // Step 3: Vault wins 100 USDC
        _simulateProfit(100);

        assertEq(vault.totalAssets(), 500, "Vault should have 500 USDC after profit");
        assertEq(
            vault.totalProfit(MathUpgradeable.Rounding.Down),
            100,
            "Total profit should be 100 USDC"
        );

        // Step 4: Claim fees
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 400, "Vault should have 400 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        // Step 5: User A deposits another 100 USDC
        _deposit(userA, 100);

        // Step 6: User B deposits another 300 USDC
        _deposit(userB, 300);

        // Verify intermediate state 2
        user = userA;
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

        // Step 7: User A redeems 200 shares
        _redeem(userA, 200 * DEAD_SHARES);

        // Step 8: User B redeems 600 shares
        _redeem(userB, 600 * DEAD_SHARES);

        // Verify intermediate state 3 (empty vault)
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

        // Step 9: User A deposits 100 USDC
        _deposit(userA, 100);

        // Step 10: User B deposits 300 USDC
        _deposit(userB, 300);

        // Verify intermediate state 4
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

        // Step 11: Vault loses 100 USDC (25% loss)
        _simulateLoss(100);

        assertEq(vault.totalAssets(), 300, "Vault should have 300 USDC after loss");
        assertEq(vault.totalPrincipal(), 400, "Total principal should still be 400");

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
        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        _mintTokens(userA, 200);
        _mintTokens(userB, 600);

        // Step 1: User A deposits 100 USDC
        _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        _deposit(userB, 300);

        // Step 3: Subvault wins 100 USDC
        _simulateProfit(100);

        // Step 4: Claim fees
        _distributePerformanceFee();

        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        // Step 5: User A deposits another 100 USDC
        _deposit(userA, 100);

        // Step 6: User B deposits another 300 USDC
        _deposit(userB, 300);

        // Step 7: User A redeems 200 shares
        _redeem(userA, 200 * DEAD_SHARES);

        // Step 8: User B redeems 600 shares
        _redeem(userB, 600 * DEAD_SHARES);

        // Step 9: User A deposits 100 USDC
        _deposit(userA, 100);

        // Step 10: User B deposits 300 USDC
        _deposit(userB, 300);

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
