// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import { TestERC20 } from "../../../contracts/tokenbridge/test/TestERC20.sol";
import { MockSubVault } from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MasterVaultTest is Test {
    MasterVault public vault;
    TestERC20 public token;

    event SubvaultChanged(address indexed oldSubvault, address indexed newSubvault);

    address public user = address(0x1);
    string public name = "Master Test Token";
    string public symbol = "mTST";

    function setUp() public {
        token = new TestERC20();
        vault = new MasterVault(IERC20(address(token)), name, symbol);
    }

    function test_initialize() public {
        assertEq(address(vault.asset()), address(token), "Invalid asset");
        assertEq(vault.name(), name, "Invalid name");
        assertEq(vault.symbol(), symbol, "Invalid symbol");
        assertEq(vault.decimals(), token.decimals(), "Invalid decimals");
        assertEq(vault.totalSupply(), 0, "Invalid initial supply");
        assertEq(vault.totalAssets(), 0, "Invalid initial assets");
        assertEq(address(vault.subVault()), address(0), "SubVault should be zero initially");
    }

    function test_WithoutSubvault_deposit() public {
        assertEq(address(vault.subVault()), address(0), "SubVault should be zero initially");

        // user deposit 500 tokens to vault
        // by this test expec:
        //- user to receive 500 shares
        //- total shares supply to increase by 500
        //- total assets to increase by 500

        uint256 minShares = 0;

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);

        token.approve(address(vault), depositAmount);

        uint256 sharesBefore = vault.balanceOf(user);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();

        uint256 shares = vault.deposit(depositAmount, user, minShares);

        assertEq(vault.balanceOf(user), sharesBefore + shares, "Invalid user balance");
        assertEq(vault.totalSupply(), totalSupplyBefore + shares, "Invalid total supply");
        assertEq(vault.totalAssets(), totalAssetsBefore + depositAmount, "Invalid total assets");
        assertEq(token.balanceOf(user), 0, "User tokens should be transferred");

        vm.stopPrank();
    }

    function test_deposit_RevertTooFewSharesReceived() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        uint256 minShares = depositAmount * 2; // Unrealistic requirement

        token.approve(address(vault), depositAmount);

        vm.expectRevert(MasterVault.TooFewSharesReceived.selector);
        vault.deposit(depositAmount, user, minShares);

        vm.stopPrank();
    }

    function test_setSubvault() public {
        MockSubVault subVault = new MockSubVault(
            IERC20(address(token)),
            "Sub Vault Token",
            "svTST"
        );

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);
        vm.stopPrank();

        assertEq(address(vault.subVault()), address(0), "SubVault should be zero initially");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should equal deposit");

        uint256 minSubVaultExchRateWad = 1e18;

        vm.expectEmit(true, true, false, false);
        emit SubvaultChanged(address(0), address(subVault));

        vault.setSubVault(subVault, minSubVaultExchRateWad);

        assertEq(address(vault.subVault()), address(subVault), "SubVault should be set");
        assertEq(vault.subVaultExchRateWad(), 1e18, "Exchange rate should be 1:1 initially");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should remain the same");
        assertEq(subVault.balanceOf(address(vault)), depositAmount, "SubVault should have received assets");
    }

    function test_switchSubvault() public {
        MockSubVault oldSubVault = new MockSubVault(
            IERC20(address(token)),
            "Old Sub Vault",
            "osvTST"
        );

        MockSubVault newSubVault = new MockSubVault(
            IERC20(address(token)),
            "New Sub Vault",
            "nsvTST"
        );

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);
        vm.stopPrank();

        vault.setSubVault(oldSubVault, 1e18);

        assertEq(address(vault.subVault()), address(oldSubVault), "Old subvault should be set");
        assertEq(oldSubVault.balanceOf(address(vault)), depositAmount, "Old subvault should have assets");
        assertEq(newSubVault.balanceOf(address(vault)), 0, "New subvault should have no assets initially");

        uint256 minAssetExchRateWad = 1e18;
        uint256 minNewSubVaultExchRateWad = 1e18;

        vm.expectEmit(true, true, false, false);
        emit SubvaultChanged(address(oldSubVault), address(0));
        vm.expectEmit(true, true, false, false);
        emit SubvaultChanged(address(0), address(newSubVault));

        vault.switchSubVault(newSubVault, minAssetExchRateWad, minNewSubVaultExchRateWad);

        assertEq(address(vault.subVault()), address(newSubVault), "New subvault should be set");
        assertEq(vault.subVaultExchRateWad(), 1e18, "Exchange rate should remain 1:1");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should remain the same");
        assertEq(oldSubVault.balanceOf(address(vault)), 0, "Old subvault should have no assets");
        assertEq(newSubVault.balanceOf(address(vault)), depositAmount, "New subvault should have received assets");
    }

    function test_revokeSubvault() public {
        MockSubVault subVault = new MockSubVault(
            IERC20(address(token)),
            "Sub Vault Token",
            "svTST"
        );

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);
        vm.stopPrank();

        vault.setSubVault(subVault, 1e18);

        assertEq(address(vault.subVault()), address(subVault), "SubVault should be set");
        assertEq(subVault.balanceOf(address(vault)), depositAmount, "SubVault should have assets");
        assertEq(vault.subVaultExchRateWad(), 1e18, "Exchange rate should be 1:1");

        uint256 minAssetExchRateWad = 1e18;

        vm.expectEmit(true, true, false, false);
        emit SubvaultChanged(address(subVault), address(0));

        vault.revokeSubVault(minAssetExchRateWad);

        assertEq(address(vault.subVault()), address(0), "SubVault should be revoked");
        assertEq(vault.subVaultExchRateWad(), 1e18, "Exchange rate should reset to 1:1");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should remain the same");
        assertEq(subVault.balanceOf(address(vault)), 0, "SubVault should have no assets");
        assertEq(token.balanceOf(address(vault)), depositAmount, "MasterVault should have assets directly");
    }

}
