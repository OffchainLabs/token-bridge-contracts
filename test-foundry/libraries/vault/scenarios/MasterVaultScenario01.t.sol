// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultScenarioCoreTest } from "./MasterVaultScenarioCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario01Test is MasterVaultScenarioCoreTest {

    /// @dev Scenario: 2 users deposit and redeem with no profit/loss
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// User A redeems 100 shares, User B redeems 300 shares
    /// Expected: All state variables return to 0, no user gains/losses
    function test_scenario01_noGainNoLoss() public {
        // Setup: Mint tokens for users
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

        // Step 3: User A redeems 100 shares
        _redeem(userA, sharesA);

        // Step 4: User B redeems 300 shares
        _redeem(userB, sharesB);

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
        assertEq(vault.balanceOf(userB), 0, "User B should have 0 shares");

        // Verify user balances (no change)
        _checkHoldings(userAInitialBalance, userBInitialBalance, 0);
    }

    /// @dev Scenario: 2 users deposit and redeem with no profit/loss, 100% subvault allocation
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// User A redeems 100 shares, User B redeems 300 shares
    /// Expected: All state variables return to 0 (except dead shares), assets moved through subvault
    function test_scenario01_noGainNoLoss_100PercentAllocation() public {
        vault.setPerformanceFee(true);

        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        _mintTokens(userA, 100);
        _mintTokens(userB, 300);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB = _deposit(userB, 300);

        vault.rebalance();

        // Verify intermediate state
        user = userA;
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 401,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 0, // 100% allocated
                masterVaultSubVaultShareBalance: 400, // 1:1 in DefaultSubVault
                subVaultTotalAssets: 400,
                subVaultTotalSupply: 400,
                subVaultTokenBalance: 400
            })
        );
        assertEq(vault.balanceOf(userB), 300 * DEAD_SHARES, "User B shares mismatch");

        // Step 3: User A redeems 100 shares
        _redeem(userA, sharesA);

        // Step 4: User B redeems 300 shares
        _redeem(userB, sharesB);

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
        assertEq(vault.balanceOf(userB), 0, "User B should have 0 shares");

        // Verify user balances (no change)
        _checkHoldings(userAInitialBalance, userBInitialBalance, 0);
    }
}
