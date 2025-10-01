// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../ClonableBeaconProxy.sol";
import "./IMasterVault.sol";
import "./IMasterVaultFactory.sol";
import "./MasterVault.sol";

contract MasterVaultFactory is IMasterVaultFactory, OwnableUpgradeable {
    error ZeroAddress();
    error BeaconNotDeployed();

    UpgradeableBeacon public beacon;
    BeaconProxyFactory public beaconProxyFactory;

    function initialize(address _owner) public initializer {
        _transferOwnership(_owner);

        MasterVault masterVaultImplementation = new MasterVault();
        beacon = new UpgradeableBeacon(address(masterVaultImplementation));
        beaconProxyFactory = new BeaconProxyFactory();
        beaconProxyFactory.initialize(address(beacon));
        beacon.transferOwnership(address(this));
    }

    function deployVault(address token) public returns (address vault) {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (address(beaconProxyFactory) == address(0)) {
            revert BeaconNotDeployed();
        }

        bytes32 userSalt = _getUserSalt(token);
        vault = beaconProxyFactory.createProxy(userSalt);

        IERC20Metadata tokenMetadata = IERC20Metadata(token);
        string memory name = string(abi.encodePacked("Master ", tokenMetadata.name()));
        string memory symbol = string(abi.encodePacked("m", tokenMetadata.symbol()));

        MasterVault(vault).vaultInit(IERC20(token), name, symbol, address(this));

        emit VaultDeployed(token, vault);
    }

    function _getUserSalt(address token) internal pure returns (bytes32) {
        return keccak256(abi.encode(token));
    }

    function calculateVaultAddress(address token) public view returns (address) {
        bytes32 userSalt = _getUserSalt(token);
        return beaconProxyFactory.calculateExpectedAddress(address(this), userSalt);
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
        address subVault,
        uint256 minSubVaultExchRateWad
    ) external onlyOwner {
        IMasterVault(masterVault).setSubVault(subVault, minSubVaultExchRateWad);
        emit SubVaultSet(masterVault, subVault);
    }
}
