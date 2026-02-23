// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultMutationBase} from "./MasterVaultMutationBase.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {Vm} from "forge-std/Test.sol";

contract MasterVaultFeesTest is MasterVaultMutationBase {
    // Move totalProfit and distributePerformanceFee tests here
    // (mutants #162, #166, #168, #176, #180 in MasterVault.sol)
}
