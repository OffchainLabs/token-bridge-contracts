// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "./MasterVaultCore.t.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultSharePriceTest is MasterVaultCoreTest {
    /// @dev example 1. sharePrice = 1e18 means we need to pay 1 asset to get 1 share regardless of the decimals
    function test_sharePrice_example1_oneToOne() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 100;
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        uint256 price = vault.sharePrice();
        assertEq(price, 1e18, "Share price should be 1e18 for 1:1 ratio");
    }

    /// @dev example 2. sharePrice = 2 * 1e18 means we need to pay 2 asset to get 1 share regardless of the decimals
    function test_sharePrice_example2_twoToOne() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Simulate vault growth: double the assets
        vm.prank(address(vault));
        token.mint();

        // Now vault has 2x assets compared to shares
        uint256 price = vault.sharePrice();
        assertEq(price, 2e18, "Share price should be 2e18 when assets are 2x shares");
    }

    /// @dev example 3. sharePrice = 0.1 * 1e18 means we need to pay 0.1 asset to get 1 share regardless of the decimals
    function test_sharePrice_example3_oneToTen() public {
        // This scenario would require shares > assets, which happens in loss scenarios
        // We'll simulate by having 1000 shares but only 100 assets
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 1000;
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // simulate vault loss: transfer out 90% of assets
        vm.prank(address(vault));
        token.transfer(user, 900);

        // vault has 100 assets but 1000 shares
        uint256 price = vault.sharePrice();
        assertEq(price, 0.1e18, "Share price should be 0.1e18 when assets are 1/10 of shares");
    }

    /// @dev example 4. vault holds 99 USDC and 100 shares => sharePrice = 99 * 1e18 / 100
    function test_sharePrice_example4_ninetyNineToHundred() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 100;
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // simulate vault loss: transfer out 1 unit
        vm.prank(address(vault));
        token.transfer(user, 1);

        // vault has 99 assets and 100 shares
        uint256 price = vault.sharePrice();
        uint256 expectedPrice = (99 * 1e18) / 100;
        assertEq(price, expectedPrice, "Share price should be 99/100 * 1e18");
        assertEq(price, 0.99e18, "Share price should be 0.99e18");
    }

    function test_sharePrice_zeroSupply() public {
        uint256 price = vault.sharePrice();
        assertEq(price, 1e18, "Share price should default to 1e18 when supply is zero");
    }
}
