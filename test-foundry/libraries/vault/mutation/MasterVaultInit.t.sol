// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultMutationBase} from "./MasterVaultMutationBase.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {TestERC20} from "../../../../contracts/tokenbridge/test/TestERC20.sol";
import {IAccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";

contract MasterVaultInitTest is MasterVaultMutationBase {
    // Move initialization tests here (mutants #1–#23 in MasterVault.sol, #6 in MasterVaultRoles.sol)
}
