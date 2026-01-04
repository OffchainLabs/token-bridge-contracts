// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";
import { MasterVault } from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultScenario01Test is MasterVaultCoreTest {
    address public userA = address(0xA);
    address public userB = address(0xB);
    address public beneficiaryAddress = address(0x9999);

    function setUp() public override {
        super.setUp();
        // Enable performance fee for this scenario
        vault.setPerformanceFee(true);
        vault.setBeneficiary(beneficiaryAddress);
    }

    /// @dev Scenario: 2 users deposit and redeem with no profit/loss
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// User A redeems 100 shares, User B redeems 300 shares
    /// Expected: All state variables return to 0, no user gains/losses
    function test_scenario01_noGainNoLoss() public {
        // Setup: Mint tokens for users
        vm.prank(userA);
        token.mint(100);
        vm.prank(userB);
        token.mint(300);

        uint256 userAInitialBalance = token.balanceOf(userA);
        uint256 userBInitialBalance = token.balanceOf(userB);

        // Step 1: User A deposits 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        uint256 sharesA = vault.deposit(100, userA);
        vm.stopPrank();

        // Step 2: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        uint256 sharesB = vault.deposit(300, userB);
        vm.stopPrank();

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

        // Step 3: User A redeems 100 shares
        vm.prank(userA);
        vault.redeem(sharesA, userA, userA);

        // Step 4: User B redeems 300 shares
        vm.prank(userB);
        vault.redeem(sharesB, userB, userB);

        // Verify final state
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
        assertEq(vault.balanceOf(userB), 0, "User B should have 0 shares");

        // Verify user balances (no change)
        assertEq(token.balanceOf(userA), userAInitialBalance, "User A should have no gain/loss");
        assertEq(token.balanceOf(userB), userBInitialBalance, "User B should have no gain/loss");

        // Verify beneficiary received nothing
        assertEq(
            token.balanceOf(beneficiaryAddress),
            0,
            "Beneficiary should have 0 (nothing claimed)"
        );
    }

    /// @dev Scenario: 2 users deposit and redeem with no profit/loss, 100% subvault allocation
    /// User A deposits 100 USDC, User B deposits 300 USDC
    /// User A redeems 100 shares, User B redeems 300 shares
    /// Expected: All state variables return to 0 (except dead shares), assets moved through subvault
    function test_scenario01_noGainNoLoss_100PercentAllocation() public {
        // Set target allocation to 100%
        vault.setTargetAllocationWad(1e18);

        // Setup: Mint tokens for users
        vm.prank(userA);
        token.mint(100);
        vm.prank(userB);
        token.mint(300);

        uint256 userAInitialBalance = token.balanceOf(userA);
        uint256 userBInitialBalance = token.balanceOf(userB);

        // Step 1: User A deposits 100 USDC
        vm.startPrank(userA);
        token.approve(address(vault), 100);
        uint256 sharesA = vault.deposit(100, userA);
        vm.stopPrank();

        // Step 2: User B deposits 300 USDC
        vm.startPrank(userB);
        token.approve(address(vault), 300);
        uint256 sharesB = vault.deposit(300, userB);
        vm.stopPrank();

        // Verify intermediate state
        user = userA;
        _checkState(
            State({
                userShares: 100 * DEAD_SHARES,
                masterVaultTotalAssets: 400,
                masterVaultTotalSupply: 401 * DEAD_SHARES,
                masterVaultTokenBalance: 0, // 100% allocated
                masterVaultSubVaultShareBalance: 400, // 1:1 in DefaultSubVault
                masterVaultTotalPrincipal: 400,
                subVaultTotalAssets: 400,
                subVaultTotalSupply: 400,
                subVaultTokenBalance: 400
            })
        );
        assertEq(vault.balanceOf(userB), 300 * DEAD_SHARES, "User B shares mismatch");

        // Step 3: User A redeems 100 shares
        vm.prank(userA);
        vault.redeem(sharesA, userA, userA);

        // Step 4: User B redeems 300 shares
        vm.prank(userB);
        vault.redeem(sharesB, userB, userB);

        // Verify final state
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
        assertEq(vault.balanceOf(userB), 0, "User B should have 0 shares");

        // Verify user balances (no change)
        assertEq(token.balanceOf(userA), userAInitialBalance, "User A should have no gain/loss");
        assertEq(token.balanceOf(userB), userBInitialBalance, "User B should have no gain/loss");

        // Verify beneficiary received nothing
        assertEq(
            token.balanceOf(beneficiaryAddress),
            0,
            "Beneficiary should have 0 (nothing claimed)"
        );
    }
}
