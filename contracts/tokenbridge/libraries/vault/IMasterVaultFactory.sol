// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../gateway/IGatewayRouter.sol";

interface IMasterVaultFactory {
    event VaultDeployed(address indexed token, address indexed vault);

    function initialize(
        address _rolesRegistry,
        address _beaconProxyFactory,
        IGatewayRouter _gatewayRouter
    ) external;
    function deployVault(address token) external returns (address vault);
    function calculateVaultAddress(address token) external view returns (address);
    function getVault(address token) external returns (address);
}
