// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultMutationBase} from "./MasterVaultMutationBase.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultRebalanceCooldownTest is MasterVaultMutationBase {
    function test_rebalance_cooldownMath() public {
        _depositAs(10e18);
        vault.setTargetAllocationWad(3e17); // 30% allocation
        vault.setRebalanceCooldown(10);
        // Rebalance at t=100 (deposits ~30% of assets to subvault)
        vm.warp(100);
        vm.prank(keeper);
        vault.rebalance(-1e18);
        // Increase allocation so there's more to deposit
        vault.setTargetAllocationWad(8e17);
        // Warp only 5s (less than 10s cooldown)
        vm.warp(105);
        // With mutant (+): timeSinceLastRebalance = 105+100=205 >= 10, no cooldown revert
        // With correct code (-): timeSinceLastRebalance = 105-100=5 < 10, cooldown revert
        vm.prank(keeper);
        vm.expectRevert();
        vault.rebalance(-1e18);
    }

    function test_rebalance_cooldownEnforced() public {
        _depositAs(10e18);
        vault.setTargetAllocationWad(3e17); // 30%
        vault.setRebalanceCooldown(100);
        vm.warp(block.timestamp + 101);
        vm.prank(keeper);
        vault.rebalance(-1e18);
        // Increase allocation so second rebalance is also a deposit
        vault.setTargetAllocationWad(8e17);
        // Warp only 50s (less than 100 cooldown)
        vm.warp(block.timestamp + 50);
        vm.prank(keeper);
        vm.expectRevert();
        vault.rebalance(-1e18);
    }
}
