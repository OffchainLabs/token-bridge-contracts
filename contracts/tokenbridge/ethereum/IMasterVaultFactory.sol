// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface IMasterVaultFactory {
    function initialize(address upgradeExecutor) external;
    function deployVault(address token) external returns (address);
    function getVault(address token) external returns (address);
}