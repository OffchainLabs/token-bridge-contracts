// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./IMasterVault.sol";
import "./MasterVault.sol";

contract MasterVaultFactory {
    event VaultDeployed(address indexed token, address indexed gateway, address vault);

    error VaultDeploymentFailed();
    error ZeroAddress();

    function deployVault(address token, address subVault) external returns (address vault) {
        if (token == address(0) || subVault == address(0)) {
            revert ZeroAddress();
        }

        address gateway = msg.sender;
        bytes32 salt = _getSalt(token, gateway);

        bytes memory bytecode = abi.encodePacked(
            type(MasterVault).creationCode,
            abi.encode(token, gateway, subVault)
        );

        vault = Create2.deploy(0, salt, bytecode);

        if (vault == address(0)) {
            revert VaultDeploymentFailed();
        }

        emit VaultDeployed(token, gateway, vault);
    }

    function calculateVaultAddress(
        address token,
        address gateway,
        address subVault
    ) external view returns (address) {
        bytes32 salt = _getSalt(token, gateway);
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(type(MasterVault).creationCode, abi.encode(token, gateway, subVault))
        );
        return Create2.computeAddress(salt, bytecodeHash);
    }

    function getVault(
        address token,
        address gateway,
        address subVault
    ) external view returns (address) {
        bytes32 salt = _getSalt(token, gateway);
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(type(MasterVault).creationCode, abi.encode(token, gateway, subVault))
        );
        return Create2.computeAddress(salt, bytecodeHash);
    }

    function _getSalt(
        address token,
        address gateway,
        address subVault
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token, gateway, subVault, block.chainid));
    }
}
