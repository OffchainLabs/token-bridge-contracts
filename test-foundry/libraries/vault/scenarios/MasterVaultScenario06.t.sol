// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultScenarioCoreTest } from "./MasterVaultScenarioCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MathUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract MasterVaultScenario06Test is MasterVaultScenarioCoreTest {
    /// @dev Scenario: Profit, fee claim, then loss before redemption
    /// Expected: Beneficiary keeps profits, users share loss of principal
    function test_scenario06_profitThenLossBeforeRedemption() public {
        // Setup: Mint tokens for users (100 for A, 300 for B)
        _mintTokens(userA, 100);
        _mintTokens(userB, 300);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB = _deposit(userB, 300);

        // Verify intermediate state
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
        assertEq(vault.totalPrincipal(), 400, "Total principal should still be 400");

        // Step 5: Vault loses 100 USDC (25% loss)
        _simulateLoss(100);

        assertEq(vault.totalAssets(), 300, "Vault should have 300 USDC after loss");
        assertEq(vault.totalPrincipal(), 400, "Total principal should still be 400");

        // Step 6: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 7: User B redeems all shares
        uint256 assetsReceivedB = _redeem(userB, sharesB);

        // Verify final state
        _checkHoldings(userAInitialBalance - 25, userBInitialBalance - 75, 100);

        // Verify assets received
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC");
    }

    /// @dev Scenario: Profit, fee claim, then loss before redemption, 100% allocation
    function test_scenario06_profitThenLossBeforeRedemption_100PercentAllocation() public {
        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        _mintTokens(userA, 100);
        _mintTokens(userB, 300);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB = _deposit(userB, 300);

        // Step 3: Subvault wins 100 USDC (25% profit)
        _simulateProfit(100);

        // Step 4: Claim fees
        _distributePerformanceFee();

        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        // Step 5: Subvault loses 100 USDC (25% loss)
        _simulateLoss(100);

        // Step 6: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 7: User B redeems all shares
        uint256 assetsReceivedB = _redeem(userB, sharesB);

        // Verify final state
        _checkHoldings(userAInitialBalance - 25, userBInitialBalance - 75, 100);
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC");
    }
}
