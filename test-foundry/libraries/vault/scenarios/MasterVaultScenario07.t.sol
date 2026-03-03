// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultScenarioCoreTest} from "./MasterVaultScenarioCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract MasterVaultScenario07Test is MasterVaultScenarioCoreTest {
    /// @dev Scenario: Profit claim, loss, full redemptions, then new deposit and redemption
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// Vault wins 100 USDC (25% profit)
    /// Beneficiary claims 100 USDC
    /// Vault loses 100 USDC (25% loss)
    /// User A redeems all shares, User B redeems all shares
    /// User A deposits 100 USDC again
    /// User A redeems all shares again
    /// Expected: Vault works correctly after full cycle
    function test_scenario07_profitLossThenNewDeposit() public {
        // Setup: Mint tokens for users (200 for A: 100+100)
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
                masterVaultTotalAssets: 401,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 400,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        assertEq(vault.balanceOf(userB), 300 * DEAD_SHARES, "User B shares mismatch");
        user = vm.addr(1);

        // Step 3: Vault wins 100 USDC (25% profit)
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

        // Step 6: User A redeems all shares
        uint256 assetsReceivedA1 = _redeem(userA, sharesA1);

        // Step 7: User B redeems all shares
        uint256 assetsReceivedB = _redeem(userB, sharesB);

        // Verify intermediate state 2 (empty vault)
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

        // Verify first redemption amounts
        assertEq(assetsReceivedA1, 75, "User A should receive 75 USDC (100 - 25)");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC (300 - 75)");

        // Step 8: User A deposits 100 USDC again
        uint256 sharesA2 = _deposit(userA, 100);

        // Verify intermediate state 3
        user = userA;
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 101,
                masterVaultTotalSupply: 101 * DEAD_SHARES,
                masterVaultTokenBalance: 100,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        user = vm.addr(1);

        // Step 9: User A redeems all shares again
        uint256 assetsReceivedA2 = _redeem(userA, sharesA2);

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

        // Verify final user holdings
        _checkHoldings(userAInitialBalance - 25, userBInitialBalance - 75, 100);

        // Verify second redemption amount
        assertEq(assetsReceivedA2, 100, "User A should receive 100 USDC on second redemption");
    }

    /// @dev Scenario: Profit claim, loss, full redemptions, then new deposit and redemption, 100% allocation
    function test_scenario07_profitLossThenNewDeposit_100PercentAllocation() public {
        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users (200 for A: 100+100)
        _mintTokens(userA, 200);
        _mintTokens(userB, 300);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA1 = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB = _deposit(userB, 300);

        vault.rebalance(type(int256).min + 1);

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
        assertEq(vault.balanceOf(userB), 300 * DEAD_SHARES, "User B shares mismatch");
        user = vm.addr(1);

        // Step 3: Subvault wins 100 USDC (25% profit)
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

        // Step 6: User A redeems all shares
        uint256 assetsReceivedA1 = _redeem(userA, sharesA1);

        // Step 7: User B redeems all shares
        uint256 assetsReceivedB = _redeem(userB, sharesB);

        // Verify intermediate state 2 (empty vault)
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

        // Verify first redemption amounts
        assertEq(assetsReceivedA1, 75, "User A should receive 75 USDC (100 - 25)");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC (300 - 75)");

        // Step 8: User A deposits 100 USDC again
        uint256 sharesA2 = _deposit(userA, 100);

        vm.warp(block.timestamp + 2);
        vault.rebalance(type(int256).min + 1);

        // Verify intermediate state 3
        user = userA;
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 101,
                masterVaultTotalSupply: 101 * DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 100,
                subVaultTotalAssets: 100,
                subVaultTotalSupply: 100,
                subVaultTokenBalance: 100
            })
        );
        user = vm.addr(1);

        // Step 9: User A redeems all shares again
        uint256 assetsReceivedA2 = _redeem(userA, sharesA2);

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

        // Verify final user holdings
        _checkHoldings(userAInitialBalance - 25, userBInitialBalance - 75, 100);

        // Verify second redemption amount
        assertEq(assetsReceivedA2, 100, "User A should receive 100 USDC on second redemption");
    }
}
