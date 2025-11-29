// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "./MasterVaultCore.t.sol";

contract MasterVaultTest is MasterVaultCoreTest {
    // first deposit 
    function test_deposit() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 100;

        token.approve(address(vault), depositAmount);

        uint256 shares = vault.deposit(depositAmount, user);

        assertEq(vault.balanceOf(user), shares, "User should receive shares");
        assertEq(vault.totalAssets(), depositAmount, "Vault should hold deposited assets");
        assertEq(vault.totalSupply(), shares, "Total supply should equal shares minted");
        assertEq(token.balanceOf(address(vault)), depositAmount, "Vault should hold the tokens");

        assertGt(token.balanceOf(address(vault)), 0, "Vault should hold the tokens");
        assertEq(
            vault.totalSupply(),
            token.balanceOf(address(vault)),
            "First deposit should be at a rate of 1"
        );

        vm.stopPrank();
    }

    // first mint
    function test_mint() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 100;
        uint256 expectedShares = depositAmount; // rate 1:1

        token.approve(address(vault), depositAmount);

        uint256 shares = vault.mint(depositAmount, user);

        assertEq(vault.balanceOf(user), shares, "User should receive shares");
        assertEq(expectedShares, shares, "User received shares should be equal to returned shares");

        assertEq(vault.totalAssets(), depositAmount, "Vault should hold deposited assets");
        assertEq(vault.totalSupply(), shares, "Total supply should equal shares minted");
        assertEq(token.balanceOf(address(vault)), depositAmount, "Vault should hold the tokens");

        vm.stopPrank();
    }

    function test_withdraw() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

        uint256 userSharesBefore = vault.balanceOf(user);
        uint256 withdrawAmount = depositAmount; // withdraw all assets

        uint256 sharesRedeemed = vault.withdraw(withdrawAmount, user, user);

        assertEq(vault.balanceOf(user), 0, "User should have no shares left");
        assertEq(token.balanceOf(user), depositAmount, "User should receive all withdrawn tokens");
        assertEq(vault.totalAssets(), 0, "Vault should have no assets left");
        assertEq(vault.totalSupply(), 0, "Total supply should be zero");
        assertEq(token.balanceOf(address(vault)), 0, "Vault should have no tokens left");
        assertEq(sharesRedeemed, userSharesBefore, "All shares should be redeemed");

        vm.stopPrank();
    }

    function test_redeem() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);

        uint256 sharesToRedeem = shares; // redeem all shares

        uint256 assetsReceived = vault.redeem(sharesToRedeem, user, user);

        assertEq(vault.balanceOf(user), 0, "User should have no shares left");
        assertEq(token.balanceOf(user), depositAmount, "User should receive all assets back");
        assertEq(vault.totalAssets(), 0, "Vault should have no assets left");
        assertEq(vault.totalSupply(), 0, "Total supply should be zero");
        assertEq(token.balanceOf(address(vault)), 0, "Vault should have no tokens left");
        assertEq(assetsReceived, depositAmount, "All assets should be received");

        vm.stopPrank();
    }
}
