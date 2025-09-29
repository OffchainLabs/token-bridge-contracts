// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IMasterVault.sol";
import "./IMasterVaultFactory.sol";
import "./MasterVault.sol";

contract MasterVaultFactory is IMasterVaultFactory, OwnableUpgradeable {

    error ZeroAddress();

    function initialize(address _owner) public initializer {
        _transferOwnership(_owner);
    }

    function deployVault(address token) public returns (address vault) {
        if (token == address(0)) {
            revert ZeroAddress();
        }

        IERC20Metadata tokenMetadata = IERC20Metadata(token);
        string memory name = string(abi.encodePacked("Master ", tokenMetadata.name()));
        string memory symbol = string(abi.encodePacked("m", tokenMetadata.symbol()));

        bytes memory bytecode = abi.encodePacked(
            type(MasterVault).creationCode,
            abi.encode(token, name, symbol)
        );

        vault = Create2.deploy(0, bytes32(0), bytecode);

        emit VaultDeployed(token, vault);
    }

    function calculateVaultAddress(address token) public view returns (address) {
        IERC20Metadata tokenMetadata = IERC20Metadata(token);
        string memory name = string(abi.encodePacked("Master ", tokenMetadata.name()));
        string memory symbol = string(abi.encodePacked("m", tokenMetadata.symbol()));

        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(MasterVault).creationCode,
                abi.encode(token, name, symbol)
            )
        );
        return Create2.computeAddress(bytes32(0), bytecodeHash);
    }

    function getVault(address token) external returns (address) {
        address vault = calculateVaultAddress(token);
        if (vault.code.length == 0) {
            return deployVault(token);
        }
        return vault;
    }

    // todo: consider a method to enable bridge owner to transfer specific master vault ownership to new address
    function setSubVault(
        address masterVault,
        address subVault
    ) external onlyOwner {
        IMasterVault(masterVault).setSubVault(subVault);
        emit SubVaultSet(masterVault, subVault);
    }
}