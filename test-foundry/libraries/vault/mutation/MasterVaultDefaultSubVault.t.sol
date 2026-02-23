// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultMutationBase} from "./MasterVaultMutationBase.t.sol";
import {
    DefaultSubVault
} from "../../../../contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";

contract MasterVaultDefaultSubVaultTest is MasterVaultMutationBase {
    function test_defaultSubVault_withdraw_onlyMasterVault() public {
        DefaultSubVault dsv = DefaultSubVault(address(vault.subVault()));
        address attacker = address(0xdead);
        vm.prank(attacker);
        vm.expectRevert("ONLY_MASTER_VAULT");
        dsv.withdraw(1, attacker, attacker);
    }

    function test_defaultSubVault_withdraw_requireTrue_onlyMasterVault() public {
        DefaultSubVault dsv = DefaultSubVault(address(vault.subVault()));
        vm.prank(address(vault));
        // should not revert when called by masterVault (with 0 amount)
        dsv.withdraw(0, address(vault), address(vault));
    }

    function test_defaultSubVault_mint_reverts() public {
        DefaultSubVault dsv = DefaultSubVault(address(vault.subVault()));
        vm.expectRevert("UNSUPPORTED");
        dsv.mint(1, address(this));
    }

    function test_defaultSubVault_redeem_reverts() public {
        DefaultSubVault dsv = DefaultSubVault(address(vault.subVault()));
        vm.expectRevert("UNSUPPORTED");
        dsv.redeem(1, address(this), address(this));
    }
}
