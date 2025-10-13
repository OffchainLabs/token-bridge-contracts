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
    event TargetAllocationChanged(uint256 oldBps, uint256 newBps);
    event Rebalanced(uint256 movedToSubVault, uint256 withdrawnFromSubVault);

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

        vault.setTargetAllocation(0, 100);

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

    function test_WithoutSubvault_withdraw() public {
        uint256 maxSharesBurned = type(uint256).max;

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);

        uint256 withdrawAmount = depositAmount / 2;
        uint256 userSharesBefore = vault.balanceOf(user);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();

        uint256 shares = vault.withdraw(withdrawAmount, user, user, maxSharesBurned);

        assertEq(vault.balanceOf(user), userSharesBefore - shares, "User shares should decrease");
        assertEq(vault.totalSupply(), totalSupplyBefore - shares, "Total supply should decrease");
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount, "Total assets should decrease");
        assertEq(token.balanceOf(user), withdrawAmount, "User should receive withdrawn assets");
        assertEq(token.balanceOf(address(vault)), depositAmount - withdrawAmount, "Vault should have remaining assets");

        vm.stopPrank();
    }

    function test_WithSubvault_withdraw() public {
        MockSubVault subVault = new MockSubVault(
            IERC20(address(token)),
            "Sub Vault Token",
            "svTST"
        );

        vm.startPrank(user);
        token.mint();
        uint256 firstDepositAmount = token.balanceOf(user);
        token.approve(address(vault), firstDepositAmount);
        vault.deposit(firstDepositAmount, user, 0);
        vm.stopPrank();

        vault.setSubVault(subVault, 1e18);

        uint256 withdrawAmount = firstDepositAmount / 2;
        uint256 maxSharesBurned = type(uint256).max;

        vm.startPrank(user);
        uint256 userSharesBefore = vault.balanceOf(user);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 subVaultSharesBefore = subVault.balanceOf(address(vault));

        uint256 shares = vault.withdraw(withdrawAmount, user, user, maxSharesBurned);

        assertEq(vault.balanceOf(user), userSharesBefore - shares, "User shares should decrease");
        assertEq(vault.totalSupply(), totalSupplyBefore - shares, "Total supply should decrease");
        assertEq(vault.totalAssets(), totalAssetsBefore - withdrawAmount, "Total assets should decrease");
        assertEq(token.balanceOf(user), withdrawAmount, "User should receive withdrawn assets");
        assertLt(subVault.balanceOf(address(vault)), subVaultSharesBefore, "SubVault shares should decrease");

        token.mint();
        uint256 secondDepositAmount = token.balanceOf(user) - withdrawAmount;
        token.approve(address(vault), secondDepositAmount);
        vault.deposit(secondDepositAmount, user, 0);

        vault.balanceOf(user);
        uint256 finalTotalAssets = vault.totalAssets();
        subVault.balanceOf(address(vault));

        vault.withdraw(finalTotalAssets, user, user, type(uint256).max);

        assertEq(vault.balanceOf(user), 0, "User should have no shares left");
        assertEq(vault.totalSupply(), 0, "Total supply should be zero");
        assertEq(vault.totalAssets(), 0, "Total assets should be zero");
        assertEq(token.balanceOf(user), firstDepositAmount + secondDepositAmount, "User should have all original tokens");
        assertEq(subVault.balanceOf(address(vault)), 0, "SubVault should have no shares left");

        vm.stopPrank();
    }

    function test_setTargetAllocation() public {
        assertEq(vault.targetSubVaultAllocationBps(), 10000, "Initial allocation should be 100%");

        vm.expectEmit(true, true, true, true);
        emit TargetAllocationChanged(10000, 5000);
        vault.setTargetAllocation(5000, 100);

        assertEq(vault.targetSubVaultAllocationBps(), 5000, "Allocation should be updated to 50%");

        vault.setTargetAllocation(0, 100);
        assertEq(vault.targetSubVaultAllocationBps(), 0, "Allocation should be updated to 0%");
    }

    function test_setTargetAllocation_RevertInvalidBps() public {
        vm.expectRevert(MasterVault.InvalidAllocationBps.selector);
        vault.setTargetAllocation(10001, 100);
    }

    function test_currentAllocationBps_noSubVault() public {
        vm.prank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);

        vm.startPrank(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user, 0);
        vm.stopPrank();

        assertEq(vault.currentAllocationBps(), 0, "Should return 0 when no subvault");
    }

    function test_currentAllocationBps_withSubVault() public {
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

        assertEq(vault.currentAllocationBps(), 10000, "Should be 100% when all assets in subvault");
    }

    function test_rebalance_reduceAllocation() public {
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
        assertEq(vault.currentAllocationBps(), 10000, "Initial allocation should be 100%");

        vault.setTargetAllocation(5000, 100);

        uint256 currentAlloc = vault.currentAllocationBps();
        assertApproxEqAbs(currentAlloc, 5000, 10, "Allocation should be close to 50%");
        assertGt(token.balanceOf(address(vault)), 0, "MasterVault should have liquid assets");
    }

    function test_rebalance_increaseAllocation() public {
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
        vault.setTargetAllocation(5000, 100);

        uint256 allocAfterRebalance = vault.currentAllocationBps();
        assertApproxEqAbs(allocAfterRebalance, 5000, 10, "Allocation should be close to 50% after rebalance");

        vault.setTargetAllocation(10000, 100);

        uint256 currentAlloc = vault.currentAllocationBps();
        assertApproxEqAbs(currentAlloc, 10000, 10, "Allocation should be close to 100%");
    }

    function test_switchSubVault_withGradualMigration() public {
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
        assertEq(vault.currentAllocationBps(), 10000, "Should start at 100%");

        vault.setTargetAllocation(5000, 100);
        assertApproxEqAbs(vault.currentAllocationBps(), 5000, 10, "Should be at 50%");

        vault.setTargetAllocation(0, 100);
        assertEq(vault.currentAllocationBps(), 0, "Should be at 0%");

        vault.switchSubVault(newSubVault, 1e18, 1e18);

        assertEq(address(vault.subVault()), address(newSubVault), "New subvault should be set");
        assertEq(oldSubVault.balanceOf(address(vault)), 0, "Old subvault should have no assets");

        vault.setTargetAllocation(10000, 100);
        assertApproxEqAbs(vault.currentAllocationBps(), 10000, 10, "Should rebalance to 100% in new vault");
    }

    function test_switchSubVault_revertsIfAllocationNotZero() public {
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
        vault.setTargetAllocation(5000, 100);

        vm.expectRevert(MasterVault.MustReduceAllocationBeforeSwitching.selector);
        vault.switchSubVault(newSubVault, 1e18, 1e18);
    }

    function test_deposit_respectsTargetAllocation() public {
        MockSubVault subVault = new MockSubVault(
            IERC20(address(token)),
            "Sub Vault Token",
            "svTST"
        );

        vm.startPrank(user);
        token.mint();
        uint256 firstDeposit = token.balanceOf(user) / 2;
        token.approve(address(vault), firstDeposit);
        vault.deposit(firstDeposit, user, 0);
        vm.stopPrank();

        vault.setSubVault(subVault, 1e18);
        vault.setTargetAllocation(5000, 100);

        vm.startPrank(user);
        token.mint();
        uint256 secondDeposit = token.balanceOf(user);
        token.approve(address(vault), secondDeposit);
        vault.deposit(secondDeposit, user, 0);
        vm.stopPrank();

        uint256 currentAlloc = vault.currentAllocationBps();
        assertApproxEqAbs(currentAlloc, 5000, 100, "New deposits should respect target allocation");
    }

    function test_withdraw_prefersLiquidAssets() public {
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

        vault.setTargetAllocation(5000, 100);
        vault.setSubVault(subVault, 1e18);

        uint256 liquidAssetsBefore = token.balanceOf(address(vault));
        uint256 subVaultSharesBefore = subVault.balanceOf(address(vault));

        vm.startPrank(user);
        uint256 withdrawAmount = liquidAssetsBefore / 2;
        vault.withdraw(withdrawAmount, user, user, type(uint256).max);
        vm.stopPrank();

        assertEq(subVault.balanceOf(address(vault)), subVaultSharesBefore, "SubVault shares should remain unchanged for small withdrawal");
    }

}
