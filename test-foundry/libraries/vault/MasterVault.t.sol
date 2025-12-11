// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "./MasterVaultCore.t.sol";
import { MockSubVault } from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract MasterVaultTest is MasterVaultCoreTest {
    // first deposit
    function test_deposit() public {
        address _assetsHoldingVault = address(vault.subVault()) == address(0)
            ? address(vault)
            : address(vault.subVault());
        uint256 _assetsHoldingVaultBalanceBefore = token.balanceOf(_assetsHoldingVault);

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 100;

        token.approve(address(vault), depositAmount);

        uint256 shares = vault.deposit(depositAmount, user);

        uint256 _assetsHoldingVaultBalanceAfter = token.balanceOf(_assetsHoldingVault);
        uint256 diff = _assetsHoldingVaultBalanceAfter - _assetsHoldingVaultBalanceBefore;

        assertEq(vault.balanceOf(user), shares, "User should receive shares");
        assertEq(vault.totalAssets(), depositAmount, "Vault should hold deposited assets");
        assertEq(vault.totalSupply(), shares, "Total supply should equal shares minted");

        assertEq(diff, depositAmount, "Vault should increase holding of assets");
        assertGt(token.balanceOf(_assetsHoldingVault), 0, "Vault should hold the tokens");

        assertEq(vault.totalSupply(), diff, "First deposit should be at a rate of 1");

        vm.stopPrank();
    }

    // first mint
    function test_mint() public {
        address _assetsHoldingVault = address(vault.subVault()) == address(0)
            ? address(vault)
            : address(vault.subVault());

        uint256 _assetsHoldingVaultBalanceBefore = token.balanceOf(_assetsHoldingVault);

        vm.startPrank(user);
        token.mint();
        uint256 sharesToMint = 100;

        token.approve(address(vault), type(uint256).max);

        //   assertEq(1, vault.totalAssets(), "First mint should be at a rate of 1"); // 0
        // assertEq(1, vault.totalSupply(), "First mint should be at a rate of 1");   // 0


        uint256 assetsCost = vault.mint(sharesToMint, user);

        uint256 _assetsHoldingVaultBalanceAfter = token.balanceOf(_assetsHoldingVault);

        assertEq(vault.balanceOf(user), sharesToMint, "User should receive requested shares");
        assertEq(vault.totalSupply(), sharesToMint, "Total supply should equal shares minted");
        assertEq(vault.totalAssets(), assetsCost, "Vault should hold the assets deposited");
        assertEq(
            _assetsHoldingVaultBalanceAfter - _assetsHoldingVaultBalanceBefore,
            assetsCost,
            "Vault should hold the tokens"
        );

        assertEq(vault.totalSupply(), vault.totalAssets(), "First mint should be at a rate of 1");
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

contract MasterVaultTestWithSubvaultFresh is MasterVaultTest {
    function setUp() public override {
        super.setUp();
        MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
        vault.setSubVault(IERC4626(address(_subvault)), 0);
    }
}

contract MasterVaultTestWithSubvaultHoldingAssets is MasterVaultTest {
    function setUp() public override {
        super.setUp();

        MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
        uint256 _initAmount = 97659743;
        token.mint(_initAmount);
        token.approve(address(_subvault), _initAmount);
        _subvault.deposit(_initAmount, address(this));
        assertEq(
            _initAmount,
            _subvault.totalAssets(),
            "subvault should be initiated with assets = _initAmount"
        );
        assertEq(
            _initAmount,
            _subvault.totalSupply(),
            "subvault should be initiated with shares = _initAmount"
        );

        vault.setSubVault(IERC4626(address(_subvault)), 0);
    }
}
