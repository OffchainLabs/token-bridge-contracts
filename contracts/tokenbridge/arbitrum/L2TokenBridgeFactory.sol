// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {L2GatewayRouter} from "./gateway/L2GatewayRouter.sol";
import {L2ERC20Gateway} from "./gateway/L2ERC20Gateway.sol";
import {L2CustomGateway} from "./gateway/L2CustomGateway.sol";
import {StandardArbERC20} from "./StandardArbERC20.sol";
import {BeaconProxyFactory} from "../libraries/ClonableBeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract L2TokenBridgeFactory {
    event OrbitL2TokenBridgeCreated(
        address router, address standardGateway, address customGateway, address beaconProxyFactory, address proxyAdmin
    );

    constructor(address l1Router, address l1StandardGateway, address l1CustomGateway) {
        address proxyAdmin = address(new ProxyAdmin());

        // create router/gateways
        L2GatewayRouter router = L2GatewayRouter(_deployBehindProxy(address(new L2GatewayRouter()), proxyAdmin));
        L2ERC20Gateway standardGateway = L2ERC20Gateway(_deployBehindProxy(address(new L2ERC20Gateway()), proxyAdmin));
        L2CustomGateway customGateway = L2CustomGateway(_deployBehindProxy(address(new L2CustomGateway()), proxyAdmin));

        // create beacon
        StandardArbERC20 standardArbERC20 = new StandardArbERC20();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(standardArbERC20));
        BeaconProxyFactory beaconProxyFactory = new BeaconProxyFactory();

        // init contracts
        router.initialize(l1Router, address(standardGateway));
        beaconProxyFactory.initialize(address(beacon));
        standardGateway.initialize(l1StandardGateway, address(router), address(beaconProxyFactory));
        customGateway.initialize(l1CustomGateway, address(router));

        emit OrbitL2TokenBridgeCreated(
            address(router), address(standardGateway), address(customGateway), address(beaconProxyFactory), proxyAdmin
        );
    }

    function _deployBehindProxy(address logic, address proxyAdmin) internal returns (address) {
        return address(new TransparentUpgradeableProxy(logic, proxyAdmin, bytes("")));
    }
}
