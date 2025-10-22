// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface IMasterVaultFactory {
    event VaultDeployed(address indexed token, address indexed vault);
    event SubVaultSet(address indexed masterVault, address indexed subVault);

    function initialize(address _owner) external;
    function deployVault(address token) external returns (address vault);
    function calculateVaultAddress(address token) external view returns (address);
    function getVault(address token) external returns (address);
    function setSubVault(address masterVault, address subVault, uint256 minSubVaultExchRateWad) external;
}