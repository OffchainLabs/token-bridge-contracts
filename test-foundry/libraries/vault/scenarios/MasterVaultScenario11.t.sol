// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultScenarioCoreTest} from "./MasterVaultScenarioCore.t.sol";

/// This test proofs that rebalance withdraws all assets including profit from the subvault.
contract MasterVaultScenario11Test is MasterVaultScenarioCoreTest {
    /// @dev Scenario: 50% allocation, sub vault doubles in value, then allocation set to 0%
    /// User A deposits 400, 50% allocated to sub vault, sub vault doubles (100% profit)
    /// Allocation changed to 0%, rebalance withdraws all assets including profit
    function test_scenario11_profitWithdrawnFromSubVault() public {
        vault.setTargetAllocationWad(0.5e18);

        _mintTokens(userA, 400);
        _deposit(userA, 400);

        // rebalance to 50% alloc
        vault.rebalance(type(int256).min + 1);

        user = userA;
        _checkState(
            State({
                userShares: 400 * DEAD_SHARES,
                masterVaultTotalAssets: 401,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 201,
                masterVaultSubVaultShareBalance: 199,
                subVaultTotalAssets: 199,
                subVaultTotalSupply: 199,
                subVaultTokenBalance: 199
            })
        );

        // subvault doubles in value
        _simulateProfit(199);

        assertEq(vault.subVault().totalAssets(), 398, "Sub vault should have doubled");
        assertEq(vault.totalAssets(), 600, "Total assets should be 600");
        assertEq(vault.totalProfit(), 199, "Profit should be 199");

        // change allocation to 0% and rebalance
        vault.setTargetAllocationWad(0);
        vm.warp(block.timestamp + 2);
        vault.rebalance(0);

        // all assets withdrawn from subvault including profit
        assertEq(
            vault.subVault().balanceOf(address(vault)), 0, "Vault should hold no sub vault shares"
        );

        _checkState(
            State({
                userShares: 400 * DEAD_SHARES,
                masterVaultTotalAssets: 600,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 599,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );

        assertEq(token.balanceOf(address(vault.subVault())), 0, "Sub vault should have no tokens");
    }
}
