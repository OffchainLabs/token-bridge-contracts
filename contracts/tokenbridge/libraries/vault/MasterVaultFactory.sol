// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "../ClonableBeaconProxy.sol";
import "./IMasterVault.sol";
import "./IMasterVaultFactory.sol";
import "./MasterVault.sol";
import "../gateway/IGatewayRouter.sol";

contract DefaultSubVault is ERC4626 {
    constructor(address token) ERC4626(IERC20(token)) ERC20("Default SubVault", "DSV") {}
}

// todo: slim down this contract
contract MasterVaultFactory is IMasterVaultFactory, Initializable {
    error ZeroAddress();
    error BeaconNotDeployed();

    BeaconProxyFactory public beaconProxyFactory;
    address public owner;
    IGatewayRouter public gatewayRouter;

    function initialize(address _owner, IGatewayRouter _gatewayRouter) public initializer {
        owner = _owner;
        gatewayRouter = _gatewayRouter;
        MasterVault masterVaultImplementation = new MasterVault();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(masterVaultImplementation));
        beaconProxyFactory = new BeaconProxyFactory();
        beaconProxyFactory.initialize(address(beacon));
        beacon.transferOwnership(_owner);
    }

    function deployVault(address token) public returns (address vault) {
        bytes32 userSalt = _getUserSalt(token);
        vault = beaconProxyFactory.createProxy(userSalt);

        string memory name = string(abi.encodePacked("Master ", _tryGetTokenName(token)));
        string memory symbol = string(abi.encodePacked("m", _tryGetTokenSymbol(token)));

        MasterVault(vault)
            .initialize(new DefaultSubVault(token), name, symbol, owner, gatewayRouter);

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
