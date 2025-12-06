// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "./MasterVaultCore.t.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import { MockSubVault } from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract MasterVaultSharePriceNoFeeTest is MasterVaultCoreTest {
    /// @dev example 1. sharePrice = 1e18 means we need to pay 1 asset to get 1 share
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

    /// @dev example 2. sharePrice = 2 * 1e18 means we need to pay 2 asset to get 1 share
    function test_sharePrice_example2_twoToOne() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // Simulate vault growth: double the assets
        vm.prank(getAssetsHoldingVault());
        token.mint();

        // Now vault has 2x assets compared to shares
        uint256 price = vault.sharePrice();
        assertEq(price, 2e18, "Share price should be 2e18 when assets are 2x shares");
    }

    /// @dev example 3. sharePrice = 0.1 * 1e18 means we need to pay 0.1 asset to get 1 share
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
        vm.prank(getAssetsHoldingVault());
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
        vm.prank(getAssetsHoldingVault());
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

    // Tests for _convertToShares rounding scenarios
    // Example 1: sharePrice = 1 * 1e18 & assets = 1; then output should be {Up: 1, Down: 1}

    function test_convertToShares_example1_deposit() public {
        // Setup: sharePrice = 1e18
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), type(uint256).max);

        // Deposit 1 asset should give 1 share (rounds down)
        uint256 shares = vault.deposit(1, user);
        assertEq(shares, 1, "Deposit with sharePrice=1e18 and assets=1 should give 1 share");

        vm.stopPrank();
    }

    function test_convertToShares_example1_mint() public {
        // Setup: sharePrice = 1e18
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), type(uint256).max);

        // Mint 1 share should cost 1 asset (rounds down for user acquiring shares)
        uint256 assets = vault.mint(1, user);
        assertEq(assets, 1, "Mint with sharePrice=1e18 and shares=1 should cost 1 asset");

        vm.stopPrank();
    }

    function test_convertToShares_example1_withdraw() public {
        // Setup: deposit first
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), type(uint256).max);
        vault.deposit(100, user);

        // Withdraw 1 asset should burn 1 share (rounds up)
        uint256 sharesBurned = vault.withdraw(1, user, user);
        assertEq(sharesBurned, 1, "Withdraw with sharePrice=1e18 and assets=1 should burn 1 share");

        vm.stopPrank();
    }

    function test_convertToShares_example1_redeem() public {
        // Setup: deposit first
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), type(uint256).max);
        vault.deposit(100, user);

        // Redeem 1 share should give 1 asset
        uint256 assetsReceived = vault.redeem(1, user, user);
        assertEq(assetsReceived, 1, "Redeem with sharePrice=1e18 and shares=1 should give 1 asset");

        vm.stopPrank();
    }

    // Example 2: sharePrice = 0.1 * 1e18 & assets = 1; then output should be {Up: 10, Down: 10}

    function test_convertToShares_example2_deposit() public {
        // Setup: Create scenario where sharePrice = 0.1e18
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1000, user); // 1000 assets = 1000 shares
        vm.stopPrank();

        // Simulate loss: transfer out 90% of assets
        vm.prank(getAssetsHoldingVault());
        token.transfer(user, 900);

        // Now sharePrice = 0.1e18
        assertEq(vault.sharePrice(), 0.1e18, "Share price should be 0.1e18");

        vm.startPrank(user);
        token.approve(address(vault), 1);

        // Deposit 1 asset should give 10 shares (rounds down)
        uint256 shares = vault.deposit(1, user);
        assertEq(shares, 10, "Deposit with sharePrice=0.1e18 and assets=1 should give 10 shares");

        vm.stopPrank();
    }

    function test_convertToShares_example2_mint() public {
        // Setup: Create scenario where sharePrice = 0.1e18
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1000, user);
        vm.stopPrank();

        vm.prank(getAssetsHoldingVault());
        token.transfer(user, 900);

        assertEq(vault.sharePrice(), 0.1e18, "Share price should be 0.1e18");

        vm.startPrank(user);
        token.approve(address(vault), 1);

        // Mint 10 shares should cost 1 asset
        uint256 assets = vault.mint(10, user);
        assertEq(assets, 1, "Mint with sharePrice=0.1e18 and shares=10 should cost 1 asset");

        vm.stopPrank();
    }

    function test_convertToShares_example2_withdraw() public {
        // Setup
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1000, user);
        vm.stopPrank();

        vm.prank(getAssetsHoldingVault());
        token.transfer(user, 900);

        assertEq(vault.sharePrice(), 0.1e18, "Share price should be 0.1e18");

        vm.startPrank(user);

        // Withdraw 1 asset should burn 10 shares (rounds up)
        uint256 sharesBurned = vault.withdraw(1, user, user);
        assertEq(
            sharesBurned,
            10,
            "Withdraw with sharePrice=0.1e18 and assets=1 should burn 10 shares"
        );

        vm.stopPrank();
    }

    function test_convertToShares_example2_redeem() public {
        // Setup
        vm.startPrank(user);
        token.mint();
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1000, user);
        vm.stopPrank();

        vm.prank(getAssetsHoldingVault());
        token.transfer(user, 900);

        assertEq(vault.sharePrice(), 0.1e18, "Share price should be 0.1e18");

        vm.startPrank(user);

        // Redeem 10 shares should give 1 asset
        uint256 assetsReceived = vault.redeem(10, user, user);
        assertEq(
            assetsReceived,
            1,
            "Redeem with sharePrice=0.1e18 and shares=10 should give 1 asset"
        );

        vm.stopPrank();
    }

    // Example 3: sharePrice = 10 * 1e18 & assets = 1; then output should be {Up: 1, Down: 0}

    function test_convertToShares_example3_deposit() public {
        // Setup: Create scenario where sharePrice = 10e18
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = 100;
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        // Simulate vault growth: multiply assets by 10
        vm.prank(getAssetsHoldingVault());
        token.mint(initialDeposit * 9);

        // Now sharePrice = 10e18
        assertEq(vault.sharePrice(), 10e18, "Share price should be 10e18");

        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);

        // Deposit 1 asset should give 0 shares (rounds down)
        uint256 shares = vault.deposit(1, user);
        assertEq(shares, 0, "Deposit with sharePrice=10e18 and assets=1 should give 0 shares");

        vm.stopPrank();
    }

    function test_convertToShares_example3_mint() public {
        // Setup: Create scenario where sharePrice = 10e18
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = 100;
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        // Simulate vault growth: multiply assets by 10
        vm.prank(getAssetsHoldingVault());
        token.mint(initialDeposit * 9);

        assertEq(vault.sharePrice(), 10e18, "Share price should be 10e18");

        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);

        // Mint 1 share should cost 10 assets
        uint256 assets = vault.mint(1, user);
        assertEq(assets, 10, "Mint with sharePrice=10e18 and shares=1 should cost 10 assets");

        vm.stopPrank();
    }

    function test_convertToShares_example3_withdraw() public {
        // Setup
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = token.balanceOf(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        vm.startPrank(getAssetsHoldingVault());
        for (uint i = 0; i < 9; i++) {
            token.mint();
        }
        vm.stopPrank();

        assertEq(vault.sharePrice(), 10e18, "Share price should be 10e18");

        vm.startPrank(user);

        // Withdraw 1 asset should burn 1 share (rounds up: 1/10 -> 1)
        uint256 sharesBurned = vault.withdraw(1, user, user);
        assertEq(
            sharesBurned,
            1,
            "Withdraw with sharePrice=10e18 and assets=1 should burn 1 share (rounds up)"
        );

        vm.stopPrank();
    }

    function test_convertToShares_example3_redeem() public {
        // Setup
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = token.balanceOf(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        vm.startPrank(getAssetsHoldingVault());
        for (uint i = 0; i < 9; i++) {
            token.mint();
        }
        vm.stopPrank();

        assertEq(vault.sharePrice(), 10e18, "Share price should be 10e18");

        vm.startPrank(user);

        // Redeem 1 share should give 10 assets
        uint256 assetsReceived = vault.redeem(1, user, user);
        assertEq(
            assetsReceived,
            10,
            "Redeem with sharePrice=10e18 and shares=1 should give 10 assets"
        );

        vm.stopPrank();
    }

    // Example 4: sharePrice = 100 * 1e18 & assets = 99; then output should be {Up: 1, Down: 0}

    function test_convertToShares_example4_deposit() public {
        // Setup: Create scenario where sharePrice = 100e18
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = 1000;
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        // Simulate vault growth to reach sharePrice = 100e18
        // We need totalAssets = 100 * totalShares
        uint256 currentAssets = vault.totalAssets();
        uint256 currentShares = vault.totalSupply();
        uint256 targetAssets = currentShares * 100;
        uint256 assetsToAdd = targetAssets - currentAssets;

        vm.prank(getAssetsHoldingVault());
        token.mint(assetsToAdd);

        assertEq(vault.sharePrice(), 100e18, "Share price should be 100e18");

        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);

        // Deposit 99 assets should give 0 shares (rounds down: 99/100 -> 0)
        uint256 shares = vault.deposit(99, user);
        assertEq(shares, 0, "Deposit with sharePrice=100e18 and assets=99 should give 0 shares");

        vm.stopPrank();
    }

    function test_convertToShares_example4_mint() public {
        // Setup
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = 1000;
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        uint256 currentAssets = vault.totalAssets();
        uint256 currentShares = vault.totalSupply();
        uint256 targetAssets = currentShares * 100;
        uint256 assetsToAdd = targetAssets - currentAssets;

        vm.prank(getAssetsHoldingVault());
        token.mint(assetsToAdd);

        assertEq(vault.sharePrice(), 100e18, "Share price should be 100e18");

        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);

        // Mint 1 share should cost 100 assets
        uint256 assets = vault.mint(1, user);
        assertEq(assets, 100, "Mint with sharePrice=100e18 and shares=1 should cost 100 assets");

        vm.stopPrank();
    }

    function test_convertToShares_example4_withdraw() public {
        // Setup
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = 1000;
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        uint256 currentAssets = vault.totalAssets();
        uint256 currentShares = vault.totalSupply();
        uint256 targetAssets = currentShares * 100;
        uint256 assetsToAdd = targetAssets - currentAssets;

        vm.prank(getAssetsHoldingVault());
        token.mint(assetsToAdd);

        assertEq(vault.sharePrice(), 100e18, "Share price should be 100e18");

        vm.startPrank(user);

        // Withdraw 99 assets should burn 1 share (rounds up: 99/100 -> 1)
        uint256 sharesBurned = vault.withdraw(99, user, user);
        assertEq(
            sharesBurned,
            1,
            "Withdraw with sharePrice=100e18 and assets=99 should burn 1 share (rounds up)"
        );

        vm.stopPrank();
    }

    function test_convertToShares_example4_redeem() public {
        // Setup
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = 1000;
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        uint256 currentAssets = vault.totalAssets();
        uint256 currentShares = vault.totalSupply();
        uint256 targetAssets = currentShares * 100;
        uint256 assetsToAdd = targetAssets - currentAssets;

        vm.prank(getAssetsHoldingVault());
        token.mint(assetsToAdd);

        assertEq(vault.sharePrice(), 100e18, "Share price should be 100e18");

        vm.startPrank(user);

        // Redeem 1 share should give 100 assets
        uint256 assetsReceived = vault.redeem(1, user, user);
        assertEq(
            assetsReceived,
            100,
            "Redeem with sharePrice=100e18 and shares=1 should give 100 assets"
        );

        vm.stopPrank();
    }

    // Example 5: sharePrice = 100 * 1e18 & assets = 199; then output should be {Up: 2, Down: 1}

    function test_convertToShares_example5_deposit() public {
        // Setup: Create scenario where sharePrice = 100e18
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = 1000;
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        uint256 currentAssets = vault.totalAssets();
        uint256 currentShares = vault.totalSupply();
        uint256 targetAssets = currentShares * 100;
        uint256 assetsToAdd = targetAssets - currentAssets;

        vm.prank(getAssetsHoldingVault());
        token.mint(assetsToAdd);

        assertEq(vault.sharePrice(), 100e18, "Share price should be 100e18");

        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);

        // Deposit 199 assets should give 1 share (rounds down: 199/100 -> 1)
        uint256 shares = vault.deposit(199, user);
        assertEq(shares, 1, "Deposit with sharePrice=100e18 and assets=199 should give 1 share");

        vm.stopPrank();
    }

    function test_convertToShares_example5_mint() public {
        // Setup
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = 1000;
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        uint256 currentAssets = vault.totalAssets();
        uint256 currentShares = vault.totalSupply();
        uint256 targetAssets = currentShares * 100;
        uint256 assetsToAdd = targetAssets - currentAssets;

        vm.prank(getAssetsHoldingVault());
        token.mint(assetsToAdd);

        assertEq(vault.sharePrice(), 100e18, "Share price should be 100e18");

        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);

        // Mint 2 shares should cost 200 assets
        uint256 assets = vault.mint(2, user);
        assertEq(assets, 200, "Mint with sharePrice=100e18 and shares=2 should cost 200 assets");

        vm.stopPrank();
    }

    function test_convertToShares_example5_withdraw() public {
        // Setup
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = 1000;
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        uint256 currentAssets = vault.totalAssets();
        uint256 currentShares = vault.totalSupply();
        uint256 targetAssets = currentShares * 100;
        uint256 assetsToAdd = targetAssets - currentAssets;

        vm.prank(getAssetsHoldingVault());
        token.mint(assetsToAdd);

        assertEq(vault.sharePrice(), 100e18, "Share price should be 100e18");

        vm.startPrank(user);

        // Withdraw 199 assets should burn 2 shares (rounds up: 199/100 -> 2)
        uint256 sharesBurned = vault.withdraw(199, user, user);
        assertEq(
            sharesBurned,
            2,
            "Withdraw with sharePrice=100e18 and assets=199 should burn 2 shares (rounds up)"
        );

        vm.stopPrank();
    }

    function test_convertToShares_example5_redeem() public {
        // Setup
        vm.startPrank(user);
        token.mint();
        uint256 initialDeposit = 1000;
        token.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();

        uint256 currentAssets = vault.totalAssets();
        uint256 currentShares = vault.totalSupply();
        uint256 targetAssets = currentShares * 100;
        uint256 assetsToAdd = targetAssets - currentAssets;

        vm.prank(getAssetsHoldingVault());
        token.mint(assetsToAdd);

        assertEq(vault.sharePrice(), 100e18, "Share price should be 100e18");

        vm.startPrank(user);

        // Redeem 2 shares should give 200 assets
        uint256 assetsReceived = vault.redeem(2, user, user);
        assertEq(
            assetsReceived,
            200,
            "Redeem with sharePrice=100e18 and shares=2 should give 200 assets"
        );

        vm.stopPrank();
    }
}

contract MasterVaultSharePriceNoFeeTestWithSubvaultFresh is MasterVaultSharePriceNoFeeTest {
    function setUp() public override {
        super.setUp();
        MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
        vault.setSubVault(IERC4626(address(_subvault)), 0);
    }
}

