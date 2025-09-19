// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./IMasterVault.sol";
import "./MasterVault.sol";

contract MasterVaultFactory {
    event VaultDeployed(address indexed token, address indexed gateway, address vault);

    error VaultDeploymentFailed();
    error ZeroAddress();

    function deployVault(address token) public returns (address vault) {
        if (token == address(0)) {
            revert ZeroAddress();
        }

        address gateway = msg.sender;

        bytes memory bytecode = abi.encodePacked(
            type(MasterVault).creationCode,
            abi.encode(token)
        );

        vault = Create2.deploy(0, bytes32(0), bytecode);

        emit VaultDeployed(token, gateway, vault);
    }

    function calculateVaultAddress(
        address token
    ) public view returns (address) {
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(type(MasterVault).creationCode, abi.encode(token))
        );
        return Create2.computeAddress(bytes32(0), bytecodeHash);
    }

    function getVault(
        address token
    ) external returns (address) {
        address vault = calculateVaultAddress(token);
        if (vault.code.length == 0) {
            return deployVault(token);
        }
        return vault;
    }
}
