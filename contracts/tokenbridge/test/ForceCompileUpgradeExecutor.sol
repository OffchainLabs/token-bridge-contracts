// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.16;

// Force hardhat to compile the concrete UpgradeExecutor so its artifact is available for tests.
// This is needed because L1AtomicTokenBridgeCreator only imports IUpgradeExecutor (the interface).
import {UpgradeExecutor} from "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
