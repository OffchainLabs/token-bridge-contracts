// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultScenarioCoreTest} from "./MasterVaultScenarioCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract MasterVaultScenario04Test is MasterVaultScenarioCoreTest {
    /// @dev Scenario: Profit, fee claim, then User A and B deposit more before redemptions
    /// Expected: Beneficiary keeps profits, users get back their total deposits
    function test_scenario04_depositAfterProfit() public {
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
                userShares: 100,
                masterVaultTotalAssets: 401,
                masterVaultTotalSupply: 401,
                masterVaultTokenBalance: 400,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        assertEq(vault.balanceOf(userB), 300, "User B shares mismatch");
        user = vm.addr(1);

        // Step 3: Vault wins 100 USDC (25% profit)
        _simulateProfit(100);

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: Claim fees
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        vm.stopPrank();

        // Step 5: User A deposits another 100 USDC
        uint256 sharesA2 = _deposit(userA, 100);

        // Step 6: User B deposits another 300 USDC
        uint256 sharesB2 = _deposit(userB, 300);

        // Step 7: User A redeems all 200 shares
        uint256 assetsReceivedA = _redeem(userA, 200);

        // Step 8: User B redeems all 600 shares
        uint256 assetsReceivedB = _redeem(userB, 600);

        // Verify final state
        _checkState(
            State({
                userShares: 0,
                masterVaultTotalAssets: 1,
                masterVaultTotalSupply: 1,
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
        assertEq(assetsReceivedA, 200, "User A should receive 200 USDC");
        assertEq(assetsReceivedB, 600, "User B should receive 600 USDC");
    }

    /// @dev Scenario: Profit, fee claim, then User A and B deposit more before redemptions, 100% allocation
    function test_scenario04_depositAfterProfit_100PercentAllocation() public {
        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        _mintTokens(userA, 200);
        _mintTokens(userB, 600);

        // Step 1: User A deposits 100 USDC
        uint256 sharesA1 = _deposit(userA, 100);

        // Step 2: User B deposits 300 USDC
        uint256 sharesB1 = _deposit(userB, 300);

        vault.rebalance(type(int256).min + 1);

        // Step 3: Subvault wins 100 USDC (25% profit)
        _simulateProfit(100);

        assertEq(vault.totalAssets(), 501, "Vault should have 501 USDC after profit");
        assertEq(vault.totalProfit(), 100, "Total profit should be 100 USDC");

        // Step 4: Claim fees
        _distributePerformanceFee();

        assertEq(vault.totalAssets(), 401, "Vault should have 401 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        vm.stopPrank();

        // Step 5: User A deposits another 100 USDC
        uint256 sharesA2 = _deposit(userA, 100);

        // Step 6: User B deposits another 300 USDC
        uint256 sharesB2 = _deposit(userB, 300);

        // Step 7: User A redeems all 200 shares
        uint256 assetsReceivedA = _redeem(userA, 200);

        // Step 8: User B redeems all 600 shares
        uint256 assetsReceivedB = _redeem(userB, 600);

        // Verify final state
        _checkHoldings(userAInitialBalance, userBInitialBalance, 100);
        assertEq(assetsReceivedA, 200, "User A should receive 200 USDC");
        assertEq(assetsReceivedB, 600, "User B should receive 600 USDC");
    }
}
