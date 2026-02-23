// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultMutationBase} from "./MasterVaultMutationBase.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultRebalanceTest is MasterVaultMutationBase {
    // Move rebalance tests here:
    // - target allocation met (#74)
    // - withdraw path: exchRate sign (#102, #103), amount math (#104, #105),
    //   minimumRebalanceAmount (#112), exchRate tolerance (#115)
    // - deposit path: exchRate sign (#81), minimumRebalanceAmount (#91),
    //   exchRate checks (#95, #97, #98, #99, #100)
    // - lastRebalanceTime (#117, #118, #119)
}
