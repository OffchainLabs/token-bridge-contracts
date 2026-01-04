// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MathUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract MasterVaultScenario05Test is MasterVaultCoreTest {
    address public userA = address(0xA);
    address public userB = address(0xB);
    address public beneficiaryAddress = address(0x9999);

    function setUp() public override {
        super.setUp();
        // Enable performance fee for this scenario
        vault.setPerformanceFee(true);
        vault.setBeneficiary(beneficiaryAddress);
    }

    /// @dev Scenario: Complex scenario with profits, fees, second deposit, full redemption, third deposit, and losses
    /// Expected: Beneficiary keeps profits, users share losses proportionally
    function test_scenario05_profitThenLoss() public {
        // Setup: Mint tokens for users (300 total each: 100+100+100 for A, 300+300+300 for B)
        vm.prank(userA);
        token.mint(300);
        vm.prank(userB);
        token.mint(900);

        uint256 userAInitialBalance = token.balanceOf(userA);
        uint256 userBInitialBalance = token.balanceOf(userB);

        // Step 1: User A deposits 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        vault.deposit(100, userA);
        vm.stopPrank();

        // Step 2: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        vault.deposit(300, userB);
        vm.stopPrank();

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
        token.mint(100);
        token.transfer(address(vault), 100);

        assertEq(vault.totalAssets(), 500, "Vault should have 500 USDC after profit");
        assertEq(
            vault.totalProfit(MathUpgradeable.Rounding.Down),
            100,
            "Total profit should be 100 USDC"
        );

        // Step 4: Claim fees
        vault.distributePerformanceFee();

        assertEq(vault.totalAssets(), 400, "Vault should have 400 USDC after fee withdrawal");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        // Step 5: User A deposits another 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        vault.deposit(100, userA);
        vm.stopPrank();

        // Step 6: User B deposits another 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        vault.deposit(300, userB);
        vm.stopPrank();

        // Verify intermediate state 2
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
        vm.prank(userA);
        vault.redeem(200 * DEAD_SHARES, userA, userA);

        // Step 8: User B redeems 600 shares
        vm.prank(userB);
        vault.redeem(600 * DEAD_SHARES, userB, userB);

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
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        vault.deposit(100, userA);
        vm.stopPrank();

        // Step 10: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        vault.deposit(300, userB);
        vm.stopPrank();

        // Verify intermediate state 4
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
        vm.prank(address(vault));
        token.transfer(address(0xdead), 100);

        assertEq(vault.totalAssets(), 300, "Vault should have 300 USDC after loss");
        assertEq(vault.totalPrincipal(), 400, "Total principal should still be 400");

        // Step 12: User A redeems 100 shares
        vm.prank(userA);
        uint256 assetsReceivedA = vault.redeem(100 * DEAD_SHARES, userA, userA);

        // Step 13: User B redeems 300 shares
        vm.prank(userB);
        uint256 assetsReceivedB = vault.redeem(300 * DEAD_SHARES, userB, userB);

        // Verify final state
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

        // Verify user holdings change
        assertEq(token.balanceOf(userA), userAInitialBalance - 25, "User A should lose 25 USDC");
        assertEq(token.balanceOf(userB), userBInitialBalance - 75, "User B should lose 75 USDC");

        // Verify assets received in final redemption
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC in final redemption");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC in final redemption");

        // Verify beneficiary still has profits
        assertEq(
            token.balanceOf(beneficiaryAddress),
            100,
            "Beneficiary should have 100 USDC (all profits)"
        );
    }

    /// @dev Scenario: Complex scenario with profits, fees, second deposit, full redemption, third deposit, and losses, 100% allocation
    function test_scenario05_profitThenLoss_100PercentAllocation() public {
        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        vm.prank(userA);
        token.mint(300);
        vm.prank(userB);
        token.mint(900);

        uint256 userAInitialBalance = token.balanceOf(userA);
        uint256 userBInitialBalance = token.balanceOf(userB);

        // Step 1: User A deposits 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        vault.deposit(100, userA);
        vm.stopPrank();

        // Step 2: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        vault.deposit(300, userB);
        vm.stopPrank();

        // Verify intermediate state 1
        user = userA;
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 400,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 400,
                masterVaultTotalPrincipal: 400,
                subVaultTotalAssets: 400,
                subVaultTotalSupply: 400,
                subVaultTokenBalance: 400
            })
        );

        // Step 3: Subvault wins 100 USDC
        token.mint(100);
        token.transfer(address(vault.subVault()), 100);

        // Step 4: Claim fees
        vault.distributePerformanceFee();

        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");

        // Step 5: User A deposits another 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        vault.deposit(100, userA);
        vm.stopPrank();

        // Step 6: User B deposits another 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        vault.deposit(300, userB);
        vm.stopPrank();

        // Verify intermediate state 2
        // Subvault share price was 500/400 = 1.25.
        // Fee claim burned 100 assets = 80 shares. Subvault shares left: 320.
        // Second deposit of 400 assets. Shares minted: 400 / 1.25 = 320.
        // Total subvault shares: 320 + 320 = 640.
        _checkState(
            State({
                userShares: 200 * DEAD_SHARES,
                masterVaultTotalAssets: 800,
                masterVaultTotalSupply: 801 * DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 640,
                masterVaultTotalPrincipal: 800,
                subVaultTotalAssets: 800,
                subVaultTotalSupply: 640,
                subVaultTokenBalance: 800
            })
        );

        // Step 7: User A redeems 200 shares
        vm.prank(userA);
        vault.redeem(200 * DEAD_SHARES, userA, userA);

        // Step 8: User B redeems 600 shares
        vm.prank(userB);
        vault.redeem(600 * DEAD_SHARES, userB, userB);

        // Step 9: User A deposits 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        vault.deposit(100, userA);
        vm.stopPrank();

        // Step 10: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        vault.deposit(300, userB);
        vm.stopPrank();

        // Verify intermediate state 4
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 400,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 0,
                masterVaultSubVaultShareBalance: 400,
                masterVaultTotalPrincipal: 400,
                subVaultTotalAssets: 400,
                subVaultTotalSupply: 400,
                subVaultTokenBalance: 400
            })
        );

        // Step 11: Subvault loses 100 USDC (25% loss)
        vm.prank(address(vault.subVault()));
        token.transfer(address(0xdead), 100);

        // Step 12: User A redeems 100 shares
        vm.prank(userA);
        uint256 assetsReceivedA = vault.redeem(100 * DEAD_SHARES, userA, userA);

        // Step 13: User B redeems 300 shares
        vm.prank(userB);
        uint256 assetsReceivedB = vault.redeem(300 * DEAD_SHARES, userB, userB);

        // Verify final state
        assertEq(token.balanceOf(userA), userAInitialBalance - 25, "User A should lose 25 USDC");
        assertEq(token.balanceOf(userB), userBInitialBalance - 75, "User B should lose 75 USDC");
        assertEq(assetsReceivedA, 75, "User A should receive 75 USDC");
        assertEq(assetsReceivedB, 225, "User B should receive 225 USDC");
        assertEq(token.balanceOf(beneficiaryAddress), 100, "Beneficiary should have 100 USDC");
    }
}
