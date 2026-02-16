// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../ClonableBeaconProxy.sol";
import "./IMasterVaultFactory.sol";
import "./MasterVault.sol";
import "../gateway/IGatewayRouter.sol";

contract DefaultSubVault is ERC4626 {
    constructor(address token) ERC4626(IERC20(token)) ERC20("Default SubVault", "DSV") {}
}

// todo: slim down this contract
contract MasterVaultFactory is IMasterVaultFactory, Initializable {
    BeaconProxyFactory public beaconProxyFactory;
    MasterVaultRoles public rolesRegistry;
    IGatewayRouter public gatewayRouter;

    function initialize(
        address _masterVaultImplementation,
        address _admin,
        IGatewayRouter _gatewayRouter
    ) public initializer {
        MasterVaultRoles _rolesRegistry = new MasterVaultRoles();
        _rolesRegistry.initialize(_admin);
        rolesRegistry = _rolesRegistry;

        UpgradeableBeacon beacon = new UpgradeableBeacon(_masterVaultImplementation);
        beacon.transferOwnership(_admin);
        BeaconProxyFactory _beaconProxyFactory = new BeaconProxyFactory();
        _beaconProxyFactory.initialize(address(beacon));
        beaconProxyFactory = _beaconProxyFactory;

        gatewayRouter = _gatewayRouter;
    }

    function deployVault(address token) public returns (address vault) {
        bytes32 userSalt = _getUserSalt(token);
        vault = beaconProxyFactory.createProxy(userSalt);

        string memory name = string(abi.encodePacked("Master ", _tryGetTokenName(token)));
        string memory symbol = string(abi.encodePacked("m", _tryGetTokenSymbol(token)));

        MasterVault(vault)
            .initialize(new DefaultSubVault(token), name, symbol, rolesRegistry, gatewayRouter);

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

    function _tryGetTokenName(address token) internal view returns (string memory) {
        try IERC20Metadata(token).name() returns (string memory name) {
            return name;
        } catch {
            return "";
        }
    }

    function _tryGetTokenSymbol(address token) internal view returns (string memory) {
        try IERC20Metadata(token).symbol() returns (string memory symbol) {
            return symbol;
        } catch {
            return "";
        }
    }
}
