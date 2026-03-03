// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultScenarioCoreTest} from "./MasterVaultScenarioCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract MasterVaultScenario03Test is MasterVaultScenarioCoreTest {
    /// @dev Scenario: 2 users deposit, vault wins 100 USDC, beneficiary claims all profit
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// Vault wins 100 USDC (25% profit)
    /// Beneficiary claims 100 USDC
    /// User A redeems 100 shares, User B redeems 300 shares
    /// Expected: Users get back their initial deposit, beneficiary keeps profit
    function test_scenario03_profitToBeneficiary() public {
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

        // Step 3: Vault wins 100 USDC (25% profit)
        _simulateProfit(100);

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: Claim fees
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        // Step 5: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 6: User B redeems all shares
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
        _checkHoldings(userAInitialBalance, userBInitialBalance, 100);

        // Verify assets received
        assertEq(assetsReceivedA, 100, "User A should receive 100 USDC");
        assertEq(assetsReceivedB, 300, "User B should receive 300 USDC");
    }

    /// @dev Scenario: 2 users deposit, subvault wins 100 USDC, beneficiary claims all profit, 100% allocation
    function test_scenario03_profitToBeneficiary_100PercentAllocation() public {
        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        _mintTokens(userA, 100);
        _mintTokens(userB, 300);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB = _deposit(userB, 300);

        vault.rebalance(type(int256).min + 1);

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

        // Step 3: Subvault wins 100 USDC (25% profit)
        _simulateProfit(100);

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: Claim fees
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        // Step 5: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 6: User B redeems all shares
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
        _checkHoldings(userAInitialBalance, userBInitialBalance, 100);

        // Verify assets received
        assertEq(assetsReceivedA, 100, "User A should receive 100 USDC");
        assertEq(assetsReceivedB, 300, "User B should receive 300 USDC");
    }
}
