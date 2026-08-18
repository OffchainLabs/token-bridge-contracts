// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultScenarioCoreTest } from "./MasterVaultScenarioCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario02Test is MasterVaultScenarioCoreTest {
    /// @dev Scenario: 2 users deposit, vault loses 100 USDC, users socialize losses
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// Vault loses 100 USDC (25% loss)
    /// User A redeems 100 shares, User B redeems 300 shares
    /// Expected: Users socialize the loss proportionally (25% each)
    function test_scenario02_socializeLosses() public {
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

        // Step 3: Vault loses 100 USDC (25% loss)
        _simulateLoss(100);

        assertEq(vault.totalAssets(), 301, "Vault should have 301 USDC after loss");

        // Step 4: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 5: User B redeems all shares
        uint256 assetsReceivedB = _redeem(userB, sharesB);

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

        // Verify user holdings change
        _checkHoldings(userAInitialBalance - 25, userBInitialBalance - 75, 0);

        // Verify assets received
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC (100 - 25)");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC (300 - 75)");
    }

    /// @dev Scenario: 2 users deposit, subvault loses 100 USDC, users socialize losses, 100% allocation
    function test_scenario02_socializeLosses_100PercentAllocation() public {
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
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 400,
                subVaultTotalAssets: 400,
                subVaultTotalSupply: 400,
                subVaultTokenBalance: 400
            })
        );

        // Step 3: Subvault loses 100 USDC (25% loss)
        _simulateLoss(100);

        assertEq(vault.totalAssets(), 301, "Vault should have 301 USDC after loss");

        // Step 4: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 5: User B redeems all shares
        uint256 assetsReceivedB = _redeem(userB, sharesB);

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

        // Verify user holdings change
        _checkHoldings(userAInitialBalance - 25, userBInitialBalance - 75, 0);

        // Verify assets received
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC (100 - 25)");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC (300 - 75)");
    }
}
