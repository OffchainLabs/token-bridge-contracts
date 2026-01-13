// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

/// @notice Roles system for MasterVaults.
///         Each MasterVault will have a reference to a singleton MasterVaultRoles contract, in addition to inheriting MasterVaultRoles directly.
///         This allows for easier management of roles across multiple vaults.
contract MasterVaultRoles is AccessControlEnumerableUpgradeable {
    /// @notice The admin can:
    ///         - Grant/revoke all roles (besides DEFAULT_ADMIN_ROLE, which is unused)
    ///         - Add/remove whitelisted subvaults
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice The general manager can:
    ///         - Grant/revoke GENERAL_MANAGER_ROLE, FEE_MANAGER_ROLE, PAUSER_ROLE, and KEEPER_ROLE
    ///         - Set the subVault to any whitelisted subVault
    ///         - Set the target allocation
    ///         - Set the minimum rebalance amount
    bytes32 public constant GENERAL_MANAGER_ROLE = keccak256("GENERAL_MANAGER_ROLE");
    /// @notice The fee manager can:
    ///         - Toggle performance fees on/off
    ///         - Set the performance fee beneficiary
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    /// @notice The pauser can:
    ///         - pause/unpause deposits and withdrawals
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice The keeper can:
    ///         - rebalance 
    ///         - distribute performance fees
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    function __MasterVaultRoles_init() internal onlyInitializing {
        __AccessControlEnumerable_init();
    }

    function initialize(address admin) external initializer {
        // set ADMIN_ROLE as admin of all roles
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(GENERAL_MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(FEE_MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(KEEPER_ROLE, ADMIN_ROLE);

        // set GENERAL_MANAGER_ROLE as admin of appropriate roles
        _setRoleAdmin(GENERAL_MANAGER_ROLE, GENERAL_MANAGER_ROLE);
        _setRoleAdmin(FEE_MANAGER_ROLE, GENERAL_MANAGER_ROLE);
        _setRoleAdmin(PAUSER_ROLE, GENERAL_MANAGER_ROLE);
        _setRoleAdmin(KEEPER_ROLE, GENERAL_MANAGER_ROLE);

        // grant ADMIN_ROLE to admin
        _grantRole(ADMIN_ROLE, admin);
    }
}
