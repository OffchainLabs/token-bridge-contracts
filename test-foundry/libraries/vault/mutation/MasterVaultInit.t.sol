// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultMutationBase} from "./MasterVaultMutationBase.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {TestERC20} from "../../../../contracts/tokenbridge/test/TestERC20.sol";
import {IAccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";

contract MasterVaultInitTest is MasterVaultMutationBase {
    function test_initialize_setsERC20Name() public {
        string memory n = vault.name();
        assertTrue(bytes(n).length > 0, "name should be set");
    }

    function test_initialize_callsDecimals() public {
        assertEq(vault.decimals(), 18 + 6, "decimals should be underlying + EXTRA_DECIMALS");
    }

    function test_initialize_pausableInit() public {
        assertFalse(vault.paused(), "vault should not be paused initially");
        vm.prank(pauser);
        vault.pause();
        assertTrue(vault.paused(), "vault should be paused after pause()");
    }

    function test_initialize_setsSubVaultWhitelist() public {
        assertTrue(
            vault.isSubVaultWhitelisted(address(vault.subVault())),
            "initial subVault should be whitelisted"
        );
    }

    function test_initialize_minimumRebalanceAmount() public {
        assertEq(
            vault.minimumRebalanceAmount(),
            1, // we set it to 1 in setUp, but let's check on a fresh vault
            "minimumRebalanceAmount after setUp"
        );
        // Deploy a fresh vault to check default
        MasterVault freshVault = MasterVault(factory.deployVault(address(new TestERC20())));
        assertEq(
            freshVault.minimumRebalanceAmount(),
            freshVault.DEFAULT_MIN_REBALANCE_AMOUNT(),
            "default minimumRebalanceAmount"
        );
    }

    function test_initialize_rebalanceCooldown() public {
        MasterVault freshVault = MasterVault(factory.deployVault(address(new TestERC20())));
        assertEq(
            freshVault.rebalanceCooldown(),
            freshVault.MIN_REBALANCE_COOLDOWN(),
            "default rebalanceCooldown"
        );
    }
}
