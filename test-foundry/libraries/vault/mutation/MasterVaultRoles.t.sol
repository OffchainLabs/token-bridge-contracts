// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultMutationBase} from "./MasterVaultMutationBase.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultRolesTest is MasterVaultMutationBase {
    // --- standalone rolesRegistry ---

    function test_rolesRegistry_adminRoleAdmin_isAdminRole() public {
        assertEq(
            vault.rolesRegistry().getRoleAdmin(vault.ADMIN_ROLE()),
            vault.ADMIN_ROLE(),
            "ADMIN_ROLE admin should be ADMIN_ROLE"
        );
    }

    function test_rolesRegistry_generalManagerRoleAdmin_isAdminRole() public {
        assertEq(
            vault.rolesRegistry().getRoleAdmin(vault.GENERAL_MANAGER_ROLE()),
            vault.ADMIN_ROLE(),
            "GENERAL_MANAGER_ROLE admin should be ADMIN_ROLE"
        );
    }

    function test_rolesRegistry_feeManagerRoleAdmin_isGeneralManagerRole() public {
        assertEq(
            vault.rolesRegistry().getRoleAdmin(vault.FEE_MANAGER_ROLE()),
            vault.GENERAL_MANAGER_ROLE(),
            "FEE_MANAGER_ROLE admin should be GENERAL_MANAGER_ROLE"
        );
    }

    function test_rolesRegistry_pauserRoleAdmin_isGeneralManagerRole() public {
        assertEq(
            vault.rolesRegistry().getRoleAdmin(vault.PAUSER_ROLE()),
            vault.GENERAL_MANAGER_ROLE(),
            "PAUSER_ROLE admin should be GENERAL_MANAGER_ROLE"
        );
    }

    function test_rolesRegistry_keeperRoleAdmin_isGeneralManagerRole() public {
        assertEq(
            vault.rolesRegistry().getRoleAdmin(vault.KEEPER_ROLE()),
            vault.GENERAL_MANAGER_ROLE(),
            "KEEPER_ROLE admin should be GENERAL_MANAGER_ROLE"
        );
    }

    // --- MasterVault (inherits MasterVaultRoles) ---

    function test_vault_adminRoleAdmin_isAdminRole() public {
        assertEq(
            vault.getRoleAdmin(vault.ADMIN_ROLE()),
            vault.ADMIN_ROLE(),
            "vault ADMIN_ROLE admin should be ADMIN_ROLE"
        );
    }

    function test_vault_generalManagerRoleAdmin_isAdminRole() public {
        assertEq(
            vault.getRoleAdmin(vault.GENERAL_MANAGER_ROLE()),
            vault.ADMIN_ROLE(),
            "vault GENERAL_MANAGER_ROLE admin should be ADMIN_ROLE"
        );
    }

    function test_vault_feeManagerRoleAdmin_isGeneralManagerRole() public {
        assertEq(
            vault.getRoleAdmin(vault.FEE_MANAGER_ROLE()),
            vault.GENERAL_MANAGER_ROLE(),
            "vault FEE_MANAGER_ROLE admin should be GENERAL_MANAGER_ROLE"
        );
    }

    function test_vault_pauserRoleAdmin_isGeneralManagerRole() public {
        assertEq(
            vault.getRoleAdmin(vault.PAUSER_ROLE()),
            vault.GENERAL_MANAGER_ROLE(),
            "vault PAUSER_ROLE admin should be GENERAL_MANAGER_ROLE"
        );
    }

    function test_vault_keeperRoleAdmin_isGeneralManagerRole() public {
        assertEq(
            vault.getRoleAdmin(vault.KEEPER_ROLE()),
            vault.GENERAL_MANAGER_ROLE(),
            "vault KEEPER_ROLE admin should be GENERAL_MANAGER_ROLE"
        );
    }
}
