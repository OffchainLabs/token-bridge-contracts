// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest} from "../MasterVaultCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract MasterVaultRebalanceTest is MasterVaultCoreTest {
    function test_rebalance_targetAllocationMet_reverts() public {
        _setupWithAllocation(1e18, 5e17);
        // Rebalance again with same allocation - should be met now
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(MasterVault.TargetAllocationMet.selector);
        vault.rebalance(0);
    }

    function test_rebalance_withdraw_negativeExchRate_reverts() public {
        _setupWithAllocation(10e18, 8e17);
        vault.setTargetAllocationWad(2e17);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.RebalanceExchRateWrongSign.selector, int256(-1))
        );
        vault.rebalance(-1);
    }

    function test_rebalance_deposit_positiveExchRate_reverts() public {
        _depositAs(1e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.RebalanceExchRateWrongSign.selector, int256(1))
        );
        vault.rebalance(1);
    }

    function test_rebalance_withdraw_zeroExchRate_succeeds() public {
        _setupWithAllocation(10e18, 8e17);
        vault.setTargetAllocationWad(2e17);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vault.rebalance(0);
    }

    function test_rebalance_withdraw_correctAmount() public {
        // this test was AI generated to catch a mutated desiredWithdraw calculation
        _setupWithAllocation(10e18, 8e17); // 80% to subvault

        uint256 idleBefore = token.balanceOf(address(vault));
        uint256 totalAssetsBefore = vault.totalAssets();

        vault.setTargetAllocationWad(2e17); // 20% to subvault, want more idle
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vault.rebalance(0);

        uint256 idleAfter = token.balanceOf(address(vault));
        // idle should be 80% of total assets now
        // With mutant #104 (+), desiredWithdraw would be idleTarget + idle (huge), capped by maxWithdrawable
        // With mutant #105 (*), desiredWithdraw would be idleTarget * idle (huge), capped by maxWithdrawable
        // Both would withdraw too much, leaving much more idle than expected
        uint256 idleTarget80pct = totalAssetsBefore * 80 / 100;
        assertEq(idleAfter, idleTarget80pct, "idle should be exactly 80% of total assets");
    }

    function test_rebalance_withdraw_tooSmall_reverts() public {
        _setupWithAllocation(10e18, 5e17);

        vault.setMinimumRebalanceAmount(100e18); // huge minimum
        vault.setTargetAllocationWad(49e16); // tiny change to trigger small withdraw
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(
            MasterVault.RebalanceAmountTooSmall.selector, false, 1e17 - 1, 1e17 - 1, 100e18
        ));
        vault.rebalance(0);
    }

    function test_rebalance_withdraw_exchRateTooLow_reverts() public {
        _setupWithAllocation(10e18, 8e17);
        vault.setTargetAllocationWad(2e17);
        vm.warp(block.timestamp + 2);
        // Pass a very high minExchRateWad so the exchange rate check fails
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(
            MasterVault.RebalanceExchRateTooLow.selector, int256(100e18), int256(6e18 - 1), 6e18 - 1
        ));
        vault.rebalance(int256(100e18));
    }

    function test_rebalance_deposit_tooSmall_reverts() public {
        _depositAs(10e18);
        vault.setMinimumRebalanceAmount(100e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(
            MasterVault.RebalanceAmountTooSmall.selector, true, 5e18 - 1, 5e18 - 1, 100e18
        ));
        vault.rebalance(-1e18);
    }

    function test_rebalance_deposit_exchRatePasses() public {
        // this test was AI generated to catch a mutated minExchRateWad comparison
        _depositAs(10e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        // -1e18 means 1:1 exchange rate tolerance. For a 1:1 subvault this should pass.
        // With #97 (++minExchRateWad): -(-1e18+1) = 999999999999999999, actualRate=1e18 > 999999999999999999 → reverts
        // With #100 (~minExchRateWad): ~(-1e18) = 1e18-1, actualRate=1e18 > 1e18-1 → reverts
        vm.prank(keeper);
        vault.rebalance(-1e18);
    }

    function test_rebalance_deposit_exchRate_tooStrict_reverts() public {
        _depositAs(10e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        // Pass -1 (tolerance of 1 wei per share) - actual rate is 1e18, so 1e18 > 1 reverts
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(
            MasterVault.RebalanceExchRateTooLow.selector, int256(-1), -int256(5e18 - 1), 5e18 - 1
        ));
        vault.rebalance(-1);
    }

    function test_rebalance_deposit_exchRate_revertExactArgs() public {
        _depositAs(10e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        // Use -2 so uint256(-(-2)) = 2. actualExchRate=1e18 > 2, should revert.
        // Replicate the contract's exact math to predict depositAmount:
        uint256 idleBalance = token.balanceOf(address(vault));
        // totalAssetsUp uses Rounding.Up for previewMint (subvault has 0 shares so it's just 1+idle)
        uint256 totalAssetsUp = 1 + idleBalance; // no subvault shares yet
        uint64 alloc = vault.targetAllocationWad();
        uint256 idleTargetUp = (totalAssetsUp * (1e18 - alloc) + 1e18 - 1) / 1e18; // round up
        uint256 desiredDeposit = idleBalance - idleTargetUp;
        uint256 maxDepositable = vault.subVault().maxDeposit(address(vault));
        uint256 depositAmount = desiredDeposit < maxDepositable ? desiredDeposit : maxDepositable;
        // Normal: RebalanceExchRateTooLow(-2, -int256(depositAmount), depositAmount)
        // Mutant: ~int256(depositAmount) = -(depositAmount+1) instead of -depositAmount
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                MasterVault.RebalanceExchRateTooLow.selector,
                int256(-2),
                -int256(depositAmount),
                depositAmount
            )
        );
        vault.rebalance(-2);
    }

    function test_rebalance_updatesLastRebalanceTime() public {
        _depositAs(1e18);
        vault.setTargetAllocationWad(5e17);
        uint256 rebalanceTime = block.timestamp + 100;
        vm.warp(rebalanceTime);
        vm.prank(keeper);
        vault.rebalance(-1e18);
        assertEq(vault.lastRebalanceTime(), rebalanceTime, "lastRebalanceTime should be updated");
    }

    function test_rebalance_drain_whenTargetIsZero() public {
        // Deposit and allocate 50% to subvault
        _setupWithAllocation(10e18, 5e17);
        uint256 subVaultSharesBefore = vault.subVault().balanceOf(address(vault));
        assertTrue(subVaultSharesBefore > 0, "should have subvault shares");

        // Set target to 0% — should trigger drain path (redeem), not rebalanceToTarget (withdraw)
        vault.setTargetAllocationWad(0);
        vm.warp(block.timestamp + 2);

        // Drain uses redeem(allShares) — verify it's called
        vm.expectCall(
            address(vault.subVault()),
            abi.encodeCall(IERC4626.redeem, (subVaultSharesBefore, address(vault), address(vault)))
        );
        vm.prank(keeper);
        vault.rebalance(0);

        // Drain should redeem ALL subvault shares
        uint256 subVaultSharesAfter = vault.subVault().balanceOf(address(vault));
        assertEq(subVaultSharesAfter, 0, "drain should redeem all subvault shares");
    }

    function test_rebalance_drain_noShares_reverts() public {
        _depositAs(10e18);
        // Target is 0 and no subvault shares — drain should revert
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(MasterVault.TargetAllocationMet.selector);
        vault.rebalance(0);
    }

    function test_rebalance_drain_negativeExchRate_reverts() public {
        _setupWithAllocation(10e18, 5e17);
        vault.setTargetAllocationWad(0);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.RebalanceExchRateWrongSign.selector, int256(-1))
        );
        vault.rebalance(-1);
    }

    function test_rebalance_drain_exchRateTooLow_reverts() public {
        _setupWithAllocation(10e18, 5e17);
        vault.setTargetAllocationWad(0);
        vm.warp(block.timestamp + 2);

        uint256 subVaultShares = vault.subVault().maxRedeem(address(vault));
        uint256 assetsReceived = vault.subVault().previewRedeem(subVaultShares);

        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                MasterVault.RebalanceExchRateTooLow.selector,
                int256(100e18),
                int256(assetsReceived),
                subVaultShares
            )
        );
        vault.rebalance(int256(100e18));
    }
}
