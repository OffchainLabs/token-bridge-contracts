// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest} from "../MasterVaultCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultSettersTest is MasterVaultCoreTest {
    function test_setTargetAllocationWad_over100_reverts() public {
        vm.prank(generalManager);
        vm.expectRevert("Target allocation must be <= 100%");
        vault.setTargetAllocationWad(1e18 + 1);
    }

    function test_setTargetAllocationWad_unchanged_reverts() public {
        vault.setTargetAllocationWad(5e17);
        vm.prank(generalManager);
        vm.expectRevert("Allocation unchanged");
        vault.setTargetAllocationWad(5e17);
    }

    function test_setMinimumRebalanceAmount_setsValue() public {
        vault.setMinimumRebalanceAmount(42);
        assertEq(vault.minimumRebalanceAmount(), 42, "minimumRebalanceAmount should be 42");
    }

    function test_setRebalanceCooldown_atMinimum_succeeds() public {
        vault.setRebalanceCooldown(vault.MIN_REBALANCE_COOLDOWN());
        assertEq(vault.rebalanceCooldown(), vault.MIN_REBALANCE_COOLDOWN());
    }

    function test_setRebalanceCooldown_belowMinimum_reverts() public {
        uint256 minimum = vault.MIN_REBALANCE_COOLDOWN();
        vm.prank(generalManager);
        vm.expectRevert(abi.encodeWithSelector(MasterVault.RebalanceCooldownTooLow.selector, uint32(0), uint32(1)));
        vault.setRebalanceCooldown(uint32(minimum - 1));
    }

    function test_setRebalanceCooldown_setsValue() public {
        vault.setRebalanceCooldown(500);
        assertEq(vault.rebalanceCooldown(), 500, "rebalanceCooldown should be 500");
    }
}
