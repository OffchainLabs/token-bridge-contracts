// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { L2GatewayRouter } from "./gateway/L2GatewayRouter.sol";
import { L2ERC20Gateway } from "./gateway/L2ERC20Gateway.sol";
import { L2CustomGateway } from "./gateway/L2CustomGateway.sol";
import { StandardArbERC20 } from "./StandardArbERC20.sol";
import { BeaconProxyFactory } from "../libraries/ClonableBeaconProxy.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { CREATE3 } from "solmate/src/utils/CREATE3.sol";

contract L2AtomicTokenBridgeFactory {
    event OrbitL2TokenBridgeCreated(address router);

    address public proxyAdmin;
    L2GatewayRouter public router;
    L2ERC20Gateway public standardGateway;

    function deployRouter(
        bytes memory creationCode,
        address l1Router,
        address standardGateway
    ) external {
        proxyAdmin = address(new ProxyAdmin());

        address routerLogicAddress = CREATE3.deploy(
            keccak256(bytes("OrbitL2GatewayRouter")),
            creationCode,
            0
        );

        // create proxy
        router = L2GatewayRouter(
            address(new TransparentUpgradeableProxy(routerLogicAddress, proxyAdmin, bytes("")))
        );

        // init proxy
        router.initialize(l1Router, address(standardGateway));

        emit OrbitL2TokenBridgeCreated(address(router));
    }

    function deployStandardGateway(bytes memory creationCode, address l1StandardGateway) external {
        address standardGatewayLogicAddress = CREATE3.deploy(
            keccak256(bytes("OrbitL2StandardGateway")),
            creationCode,
            0
        );

        // create proxy
        standardGateway = L2ERC20Gateway(
            address(
                new TransparentUpgradeableProxy(standardGatewayLogicAddress, proxyAdmin, bytes(""))
            )
        );

        // create beacon
        StandardArbERC20 standardArbERC20 = new StandardArbERC20();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(standardArbERC20));
        BeaconProxyFactory beaconProxyFactory = new BeaconProxyFactory();

        // init contracts
        beaconProxyFactory.initialize(address(beacon));
        standardGateway.initialize(l1StandardGateway, address(router), address(beaconProxyFactory));
    }

    function deployCustomGateway(bytes memory creationCode, address l1CustomGateway) external {
        address customGatewayLogicAddress = CREATE3.deploy(
            keccak256(bytes("OrbitL2CustomGateway")),
            creationCode,
            0
        );

        // create proxy
        L2CustomGateway customGateway = L2CustomGateway(
            address(
                new TransparentUpgradeableProxy(customGatewayLogicAddress, proxyAdmin, bytes(""))
            )
        );

        customGateway.initialize(l1CustomGateway, address(router));
    }
}
