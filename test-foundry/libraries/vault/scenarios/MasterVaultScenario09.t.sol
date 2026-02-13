// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultScenarioCoreTest} from "./MasterVaultScenarioCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario09Test is MasterVaultScenarioCoreTest {
    /// @dev Scenario: Multiple profit claims
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// Vault wins 50 USDC → beneficiary claims 50
    /// Vault wins 50 USDC more → beneficiary claims another 50
    /// Users redeem all
    /// Expected: Multiple fee distributions work correctly, users get back principal
    function test_scenario09_multipleProfitClaims() public {
        // Setup: Mint tokens for users
        _mintTokens(userA, 100);
        _mintTokens(userB, 300);

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

        // Step 3: Vault wins 50 USDC
        _simulateProfit(50);

        assertEq(vault.totalAssets(), 451, "Vault should have 451 USDC after first profit");
        assertEq(vault.totalProfit(), 50, "Total profit should be 50 USDC");

        // Step 4: Beneficiary claims first 50 USDC
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after first fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 50, "Beneficiary should have 50 USDC");
        assertEq(vault.totalProfit(), 0, "Profit should be 0 after claim");

        vm.stopPrank();

        // Step 5: Vault wins 50 USDC more
        _simulateProfit(50);

        assertEq(vault.totalAssets(), 451, "Vault should have 451 USDC after second profit");
        assertEq(vault.totalProfit(), 50, "Total profit should be 50 USDC again");

        // Step 6: Beneficiary claims second 50 USDC
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after second fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC total");
        assertEq(vault.totalProfit(), 0, "Profit should be 0 after second claim");

        vm.stopPrank();

        // Step 7: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 8: User B redeems all shares
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

        // Users should get back their principal
        assertEq(assetsReceivedA, 100, "User A should receive 100 USDC");
        assertEq(assetsReceivedB, 300, "User B should receive 300 USDC");

        // Verify final holdings (no loss, beneficiary got all profit)
        _checkHoldings(userAInitialBalance, userBInitialBalance, 100);
    }

    /// @dev Scenario: Multiple profit claims, 100% allocation
    function test_scenario09_multipleProfitClaims_100PercentAllocation() public {
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

        // Step 3: Subvault wins 50 USDC
        _simulateProfit(50);

        assertEq(vault.totalAssets(), 451, "Vault should have 451 USDC after first profit");
        assertEq(vault.totalProfit(), 50, "Total profit should be 50 USDC");

        // Step 4: Beneficiary claims first 50 USDC
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after first fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 50, "Beneficiary should have 50 USDC");

        vm.stopPrank();

        // Step 5: Subvault wins 50 USDC more
        _simulateProfit(50);

        assertEq(vault.totalAssets(), 451, "Vault should have 451 USDC after second profit");
        assertEq(vault.totalProfit(), 50, "Total profit should be 50 USDC again");

        // Step 6: Beneficiary claims second 50 USDC
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after second fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC total");

        vm.stopPrank();

        // Step 7: User A redeems all shares
        uint256 assetsReceivedA = _redeem(userA, sharesA);

        // Step 8: User B redeems all shares
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

        // Users should get back their principal
        assertEq(assetsReceivedA, 100, "User A should receive 100 USDC");
        assertEq(assetsReceivedB, 300, "User B should receive 300 USDC");

        // Verify final holdings (no loss, beneficiary got all profit)
        _checkHoldings(userAInitialBalance, userBInitialBalance, 100);
    }
}
