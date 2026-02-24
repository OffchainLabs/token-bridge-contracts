// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest} from "../MasterVaultCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {TestERC20} from "../../../../contracts/tokenbridge/test/TestERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Test.sol";

contract MasterVaultFeesTest is MasterVaultCoreTest {
    function test_totalProfit_correctMath() public {
        // this test was AI generated to target a mutant where subtract is replaced with modulo in profit calculation

        // Use a scenario where profit > principal, so % gives different result than -
        // Deposit 10e18, simulate 20e18 profit → totalAssets ≈ 30e18, principal ≈ 10e18
        // With -: profit = 30e18 - 10e18 = 20e18
        // With %: profit = 30e18 % 10e18 = 0 (since 30 is divisible by 10)
        _depositAs(10e18);
        token.mintAmount(20e18);
        token.transfer(address(vault), 20e18);
        uint256 profit = vault.totalProfit();
        assertEq(profit, 20e18, "profit should be 20e18");
    }

    function test_distributePerformanceFee_noBeneficiary_reverts() public {
        MasterVault freshVault = MasterVault(factory.deployVault(address(new TestERC20())));
        freshVault.rolesRegistry().grantRole(freshVault.KEEPER_ROLE(), address(this));
        vm.expectRevert(MasterVault.BeneficiaryNotSet.selector);
        freshVault.distributePerformanceFee();
    }

    function test_distributePerformanceFee_zeroProfit_noEvent() public {
        // No profit -> early return, should NOT emit PerformanceFeesWithdrawn
        // If mutant removes early return, the event would still be emitted with (beneficiary, 0, 0)
        vm.prank(keeper);
        vm.recordLogs();
        vault.distributePerformanceFee();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics[0] != keccak256("PerformanceFeesWithdrawn(address,uint256,uint256)"),
                "should not emit PerformanceFeesWithdrawn when profit is zero"
            );
        }
    }

    function test_distributePerformanceFee_transfersIdleProfit() public {
        _depositAs(100e18);
        token.mintAmount(10e18);
        token.transfer(address(vault), 10e18);
        uint256 vaultBalBefore = token.balanceOf(address(vault));
        vm.prank(keeper);
        vault.distributePerformanceFee();
        uint256 vaultBalAfter = token.balanceOf(address(vault));
        assertEq(token.balanceOf(beneficiaryAddr), 10e18, "beneficiary should receive profit");
        assertEq(vaultBalBefore - vaultBalAfter, 10e18, "vault should lose exactly the profit amount");
    }

    function test_distributePerformanceFee_allProfitInSubVault() public {
        _setupWithAllocation(100e18, 99e16); // 99% to subvault
        // Simulate profit in subvault
        token.mintAmount(5e18);
        token.transfer(address(vault.subVault()), 5e18);
        uint256 idleBefore = token.balanceOf(address(vault));
        uint256 profit = vault.totalProfit();
        assertTrue(profit > 0);
        assertEq(profit, 5e18, "profit should be 5e18");
        vm.prank(keeper);
        vault.distributePerformanceFee();
        // If mutant makes `if(true)`, it calls safeTransfer(beneficiary, 0) when idle profit is 0.
        // This would still succeed, so this is more about ensuring overall correctness.
        assertEq(token.balanceOf(beneficiaryAddr), profit, "beneficiary receives full profit");
        assertEq(token.balanceOf(address(vault)), 0, "should take all idle from vault");
        assertEq(token.balanceOf(address(vault.subVault())), 100e18, "should withdraw only profit from subvault");
    }

    function test_distributePerformanceFee_allProfitIdle_noSubVaultWithdraw() public {
        _depositAs(100e18);
        // Profit is all idle (no allocation to subvault)
        token.mintAmount(5e18);
        token.transfer(address(vault), 5e18);
        uint256 subVaultSharesBefore = vault.subVault().balanceOf(address(vault));
        vm.prank(keeper);
        vault.distributePerformanceFee();
        uint256 subVaultSharesAfter = vault.subVault().balanceOf(address(vault));
        assertEq(subVaultSharesBefore, subVaultSharesAfter, "no subvault shares should change");
        assertEq(token.balanceOf(beneficiaryAddr), 5e18, "beneficiary gets idle profit");
    }

    function test_distributePerformanceFee_noSubVaultWithdrawCall() public {
        _depositAs(100e18);
        // All profit is idle — amountToWithdraw will be 0
        token.mintAmount(5e18);
        token.transfer(address(vault), 5e18);

        vm.prank(keeper);
        vm.recordLogs();
        vault.distributePerformanceFee();

        // The mutant calls subVault.withdraw(0, ...) which emits a Withdraw event.
        // Correct code skips the call entirely, so no Withdraw event from the subvault.
        bytes32 withdrawSig = keccak256("Withdraw(address,address,address,uint256,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(vault.subVault())) {
                assertTrue(logs[i].topics[0] != withdrawSig, "subVault should not emit Withdraw");
            }
        }
    }

    function test_distributePerformanceFee_noTransferCallWhenIdleZero() public {
        _setupWithAllocation(100e18, 1e18); // 100% to subvault, idle should be 0
        assertEq(token.balanceOf(address(vault)), 0, "idle should be 0 after 100% rebalance");

        // All profit in subvault — amountToTransfer will be 0
        token.mintAmount(5e18);
        token.transfer(address(vault.subVault()), 5e18);

        vm.prank(keeper);
        vm.recordLogs();
        vault.distributePerformanceFee();

        // The mutant calls safeTransfer(beneficiary, 0) which emits Transfer(vault, beneficiary, 0).
        // Correct code skips the call, so no such Transfer event.
        bytes32 transferSig = keccak256("Transfer(address,address,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == transferSig && logs[i].emitter == address(token)) {
                (uint256 amount) = abi.decode(logs[i].data, (uint256));
                if (amount == 0) {
                    address from = address(uint160(uint256(logs[i].topics[1])));
                    address to = address(uint160(uint256(logs[i].topics[2])));
                    assertTrue(
                        !(from == address(vault) && to == beneficiaryAddr),
                        "should not transfer 0 from vault to beneficiary"
                    );
                }
            }
        }
    }

    function test_distributePerformanceFee_withdrawsFromSubVault() public {
        // Put nearly everything into subvault so idle is very small
        _setupWithAllocation(100e18, 99e16); // 99% to subvault
        uint256 idleBeforeProfit = token.balanceOf(address(vault));
        // Simulate profit LARGER than idle, forcing withdrawal from subvault
        uint256 profitAmount = idleBeforeProfit + 5e18;
        token.mintAmount(profitAmount);
        token.transfer(address(vault.subVault()), profitAmount);
        uint256 profit = vault.totalProfit();
        assertTrue(profit > idleBeforeProfit, "profit exceeds idle");
        uint256 subVaultBalBefore = token.balanceOf(address(vault.subVault()));
        vm.prank(keeper);
        vault.distributePerformanceFee();
        uint256 subVaultBalAfter = token.balanceOf(address(vault.subVault()));
        assertEq(token.balanceOf(beneficiaryAddr), profit, "beneficiary should receive all profit");
        assertTrue(subVaultBalBefore > subVaultBalAfter, "subvault balance should decrease");
    }
}
