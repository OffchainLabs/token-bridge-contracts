// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultMutationBase} from "./MasterVaultMutationBase.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MockSubVault} from "../../../../contracts/tokenbridge/test/MockSubVault.sol";
import {TestERC20} from "../../../../contracts/tokenbridge/test/TestERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract MasterVaultSetSubVaultTest is MasterVaultMutationBase {
    // Move setSubVault guard tests here (mutants #122, #124, #126, #128 in MasterVault.sol)
}
