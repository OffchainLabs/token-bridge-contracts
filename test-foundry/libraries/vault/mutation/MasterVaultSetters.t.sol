// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultMutationBase} from "./MasterVaultMutationBase.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultSettersTest is MasterVaultMutationBase {
    // Move setter tests here:
    // - setTargetAllocationWad (#130, #131, #134, #135)
    // - setMinimumRebalanceAmount (#141, #142)
    // - setRebalanceCooldown (#143, #144, #145, #146, #147, #148)
}
