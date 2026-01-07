// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultScenarioCoreTest } from "./MasterVaultScenarioCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MathUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract MasterVaultScenario07Test is MasterVaultScenarioCoreTest {
    /// @dev Scenario: Profit, fee claim, loss, redemption, then new deposit and redemption
    /// Expected: Beneficiary keeps profits, users share initial loss, User A has no change on second round
    function test_scenario07_afterLossNewDeposit() public {
        // Setup: Mint tokens for users (200 for A: 100+100, 300 for B: 300)
        _mintTokens(userA, 200);
        _mintTokens(userB, 300);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA1 = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB = _deposit(userB, 300);

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

        // Step 5: Vault loses 100 USDC (25% loss)
        _simulateLoss(100);

        assertEq(vault.totalAssets(), 300, "Vault should have 300 USDC after loss");
        assertEq(vault.totalPrincipal(), 400, "Total principal should still be 400");

        // Step 6: User A redeems 100 shares
        uint256 assetsReceivedA1 = _redeem(userA, sharesA1);

        assertEq(assetsReceivedA1, 75, "User A should receive 75 USDC (25% loss)");

        // Step 7: User B redeems 300 shares
        uint256 assetsReceivedB = _redeem(userB, sharesB);

        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC (25% loss)");

        // Verify intermediate state 2 (after loss redemptions)
        _checkState(
            State({
                userShares: 0,
                masterVaultTotalAssets: 0,
                masterVaultTotalSupply: DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 0,
                masterVaultTotalPrincipal: 100, // 400 - 300 (assets withdrawn)
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );

        // Step 8: User A deposits 100 USDC
        uint256 sharesA2 = _deposit(userA, 100);

        assertEq(
            sharesA2,
            100 * DEAD_SHARES,
            "User A should receive 100 shares for second deposit"
        );
        assertEq(vault.totalPrincipal(), 200, "Total principal should be 200");
        assertEq(vault.totalAssets(), 100, "Total assets should be 100");

        // Step 9: User A redeems 100 shares
        uint256 assetsReceivedA2 = _redeem(userA, sharesA2);

        assertEq(assetsReceivedA2, 100, "User A should receive 100 USDC for second redemption");

        // Verify final state
        _checkState(
            State({
                userShares: 0,
                masterVaultTotalAssets: 0,
                masterVaultTotalSupply: DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 0,
                masterVaultTotalPrincipal: 100, // remains 100 from previous loss
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );

        // Verify user holdings change
        _checkHoldings(userAInitialBalance - 25, userBInitialBalance - 75, 100);
    }

    /// @dev Scenario: Profit, fee claim, loss, redemption, then new deposit and redemption, 100% allocation
    function test_scenario07_afterLossNewDeposit_100PercentAllocation() public {
        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        _mintTokens(userA, 200);
        _mintTokens(userB, 300);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA1 = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB = _deposit(userB, 300);

        // Step 3: Subvault wins 100 USDC
        _simulateProfit(100);

        // Step 4: Claim fees
        _distributePerformanceFee();

        // Step 5: Subvault loses 100 USDC
        _simulateLoss(100);

        // Step 6: User A redeems 100 shares
        uint256 assetsReceivedA1 = _redeem(userA, sharesA1);
        assertEq(assetsReceivedA1, 75, "User A should receive 75 USDC");

        // Step 7: User B redeems 300 shares
        uint256 assetsReceivedB = _redeem(userB, sharesB);
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC");

        // Step 8: User A deposits 100 USDC
        uint256 sharesA2 = _deposit(userA, 100);

        // Step 9: User A redeems 100 shares
        uint256 assetsReceivedA2 = _redeem(userA, sharesA2);
        assertEq(assetsReceivedA2, 100, "User A should receive 100 USDC");

        // Verify final state
        _checkHoldings(userAInitialBalance - 25, userBInitialBalance - 75, 100);
    }
}
