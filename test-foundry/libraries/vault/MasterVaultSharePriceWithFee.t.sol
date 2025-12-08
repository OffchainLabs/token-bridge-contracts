// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "./MasterVaultCore.t.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultSharePriceWithFeeTest is MasterVaultCoreTest {
    function setUp() public override {
        super.setUp();
        // Enable performance fee for all tests in this file
        vault.setPerformanceFee(true);
    }

    /// @dev When performance fee is enabled, sharePrice is capped at 1e18
    function test_sharePrice_cappedAt1e18_whenProfitable() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Simulate vault growth: double the assets
        vm.prank(address(vault));
        token.mint();

        // With performance fee enabled, sharePrice should be capped at 1e18 even though actual ratio is 2:1
        uint256 price = vault.sharePrice();
        assertEq(
            price,
            1e18,
            "Share price should be capped at 1e18 when performance fee is enabled"
        );
    }

    /// @dev When vault has losses, sharePrice can be below 1e18 even with performance fee
    function test_sharePrice_belowCap_whenLosses() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 1000;
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Simulate vault loss: transfer out 10%
        vm.prank(address(vault));
        token.transfer(user, 100);

        // sharePrice should be 0.9e18 (900/1000)
        uint256 price = vault.sharePrice();
        assertEq(price, 0.9e18, "Share price should reflect losses even with performance fee");
    }

    /// @dev Test deposit behavior when performance fee is enabled and vault is profitable
    function test_deposit_withProfitableVault() public {
        // Initial deposit
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = token.balanceOf(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        // Vault gains profit
        vm.prank(address(vault));
        token.mint();

        // Now sharePrice is capped at 1e18
        assertEq(vault.sharePrice(), 1e18, "Share price should be 1e18");

        // New user deposits
        vm.startPrank(address(0x2));
        token.mint(1000);
        token.approve(address(vault), 1000);

        // With sharePrice = 1e18, depositing 1000 assets should give 1000 shares
        uint256 shares = vault.deposit(1000, address(0x2));
        assertEq(shares, 1000, "Should receive 1000 shares for 1000 assets at 1e18 sharePrice");
        vm.stopPrank();
    }

    /// @dev Test redeem behavior when performance fee is enabled and vault is profitable
    function test_redeem_withProfitableVault() public {
        // Initial deposit
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = token.balanceOf(user);
        token.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(initialDeposit, user);
        vm.stopPrank();

        // Vault gains profit (doubles)
        vm.prank(address(vault));
        token.mint();

        // User redeems shares - should only get back principal (due to _effectiveAssets)
        vm.prank(user);
        uint256 assetsReceived = vault.redeem(shares, user, user);

        // With performance fee, user should only get their principal back, not the profits
        assertEq(assetsReceived, initialDeposit, "User should only receive principal, not profits");
    }

    /// @dev Test withdraw behavior when performance fee is enabled and vault is profitable
    function test_withdraw_withProfitableVault() public {
        // Initial deposit
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = token.balanceOf(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        // Vault gains profit (doubles)
        vm.prank(address(vault));
        token.mint();

        // User tries to withdraw all their principal
        vm.prank(user);
        uint256 sharesBurned = vault.withdraw(initialDeposit, user, user);

        // Should burn all shares to get principal back
        assertGt(sharesBurned, 0, "Should burn shares to withdraw principal");
    }

    /// @dev Test that users socialize losses when performance fee is enabled
    function test_socializeLosses_withPerformanceFee() public {
        // Two users deposit equal amounts
        vm.startPrank(user);
        token.mint();
        uint256 deposit1 = 1000;
        token.approve(address(vault), deposit1);
        uint256 shares1 = vault.deposit(deposit1, user);
        vm.stopPrank();

        vm.startPrank(address(0x2));
        token.mint(1000);
        token.approve(address(vault), 1000);
        uint256 shares2 = vault.deposit(1000, address(0x2));
        vm.stopPrank();

        // Vault loses 50% of assets
        vm.prank(address(vault));
        token.transfer(address(0x999), 1000);

        // Both users should be able to redeem proportionally
        vm.prank(user);
        uint256 assets1 = vault.redeem(shares1, user, user);

        vm.prank(address(0x2));
        uint256 assets2 = vault.redeem(shares2, address(0x2), address(0x2));

        // Each should get 500 (50% of their original 1000)
        assertEq(assets1, 500, "User 1 should get 500 assets (50% loss)");
        assertEq(assets2, 500, "User 2 should get 500 assets (50% loss)");
    }

    /// @dev Test that users DON'T socialize profits when performance fee is enabled
    function test_noSocializeProfits_withPerformanceFee() public {
        // User 1 deposits
        vm.startPrank(user);
        token.mint();
        uint256 deposit1 = 1000;
        token.approve(address(vault), deposit1);
        uint256 shares1 = vault.deposit(deposit1, user);
        vm.stopPrank();

        // Vault gains profit (doubles)
        vm.prank(address(vault));
        token.mint(1000);

        // User 2 deposits same amount
        vm.startPrank(address(0x2));
        token.mint(1000);
        token.approve(address(vault), 1000);
        uint256 shares2 = vault.deposit(1000, address(0x2));
        vm.stopPrank();

        // User 1 redeems - should only get their principal back (1000)
        vm.prank(user);
        uint256 assets1 = vault.redeem(shares1, user, user);
        assertEq(assets1, deposit1, "User 1 should only get their principal, not share in profits");

        // User 2 redeems - should also get their principal back (1000)
        vm.prank(address(0x2));
        uint256 assets2 = vault.redeem(shares2, address(0x2), address(0x2));
        assertEq(assets2, 1000, "User 2 should get their principal");
    }

    /// @dev Test sharePrice = 1e18 scenario with performance fee
    function test_convertToShares_perfFee_example1() public {
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), type(uint256).max);

        // Deposit 1 asset should give 1 share
        uint256 shares = vault.deposit(1, user);
        assertEq(shares, 1, "Should receive 1 share for 1 asset");

        vm.stopPrank();
    }

    /// @dev Test with vault losses and performance fee
    function test_convertToShares_perfFee_withLosses() public {
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1000, user);
        vm.stopPrank();

        // Simulate 50% loss
        vm.prank(address(vault));
        token.transfer(user, 500);

        // sharePrice = 0.5e18
        assertEq(vault.sharePrice(), 0.5e18, "Share price should be 0.5e18");

        vm.startPrank(user);
        token.approve(address(vault), 1);

        // Deposit 1 asset at 0.5e18 sharePrice should give 2 shares
        uint256 shares = vault.deposit(1, user);
        assertEq(shares, 2, "Should receive 2 shares for 1 asset at 0.5e18 sharePrice");

        vm.stopPrank();
    }
}
