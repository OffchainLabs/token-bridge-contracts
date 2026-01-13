// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

contract MasterVaultRoles is AccessControlEnumerableUpgradeable {
    /// @notice Subvault manager role can set/revoke subvaults, set target allocation, and set minimum rebalance amount
    /// @dev    Should never be granted to the zero address
    bytes32 public constant SUBVAULT_MANAGER_ROLE = keccak256("SUBVAULT_MANAGER_ROLE");
    /// @notice Fee manager role can toggle performance fees and set the performance fee beneficiary
    /// @dev    Should never be granted to the zero address
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    /// @notice Pauser role can pause/unpause deposits and withdrawals (todo: pause should pause EVERYTHING)
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Keeper role can rebalance the vault and distribute performance fees
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER");

    function __MasterVaultRoles_init() internal onlyInitializing {
        __AccessControlEnumerable_init();
    }

    function initialize(address admin) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEE_MANAGER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(KEEPER_ROLE, admin);
    }
}
