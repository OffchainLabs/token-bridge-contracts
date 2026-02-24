// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest} from "../MasterVaultCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultPauseTest is MasterVaultCoreTest {
    function test_pause_works() public {
        vm.prank(pauser);
        vault.pause();
        assertTrue(vault.paused(), "should be paused");
    }

    function test_unpause_works() public {
        vm.prank(pauser);
        vault.pause();
        assertTrue(vault.paused());
        vm.prank(pauser);
        vault.unpause();
        assertFalse(vault.paused(), "should be unpaused");
    }
}
