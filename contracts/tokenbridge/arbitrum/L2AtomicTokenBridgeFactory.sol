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
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

contract L2AtomicTokenBridgeFactory {
    address public proxyAdmin;
    L2GatewayRouter public router;
    L2ERC20Gateway public standardGateway;
    L2CustomGateway public customGateway;

    function deployRouter(
        bytes memory creationCode,
        address l1Router,
        address l2StandardGatewayExpectedAddress
    ) external {
        proxyAdmin = address(new ProxyAdmin{ salt: keccak256(bytes("OrbitL2ProxyAdmin")) }());

        address routerLogicAddress = Create2.deploy(
            0,
            keccak256(bytes("OrbitL2GatewayRouterLogic")),
            creationCode
        );

        // create proxy
        router = L2GatewayRouter(
            address(
                new TransparentUpgradeableProxy{
                    salt: keccak256(bytes("OrbitL2GatewayRouterProxy"))
                }(routerLogicAddress, proxyAdmin, bytes(""))
            )
        );

        // init proxy
        router.initialize(l1Router, l2StandardGatewayExpectedAddress);
    }

    function deployStandardGateway(bytes memory creationCode, address l1StandardGateway) external {
        address standardGatewayLogicAddress = Create2.deploy(
            0,
            keccak256(bytes("OrbitL2StandardGatewayLogic")),
            creationCode
        );

        // create proxy
        standardGateway = L2ERC20Gateway(
            address(
                new TransparentUpgradeableProxy{
                    salt: keccak256(bytes("OrbitL2StandardGatewayProxy"))
                }(standardGatewayLogicAddress, proxyAdmin, bytes(""))
            )
        );

        // create beacon
        StandardArbERC20 standardArbERC20 = new StandardArbERC20{
            salt: keccak256(bytes("OrbitStandardArbERC20"))
        }();
        UpgradeableBeacon beacon = new UpgradeableBeacon{
            salt: keccak256(bytes("OrbitUpgradeableBeacon"))
        }(address(standardArbERC20));
        BeaconProxyFactory beaconProxyFactory = new BeaconProxyFactory{
            salt: keccak256(bytes("OrbitBeaconProxyFactory"))
        }();

        // init contracts
        beaconProxyFactory.initialize(address(beacon));
        standardGateway.initialize(l1StandardGateway, address(router), address(beaconProxyFactory));
    }

    function deployCustomGateway(bytes memory creationCode, address l1CustomGateway) external {
        address customGatewayLogicAddress = Create2.deploy(
            0,
            keccak256(bytes("OrbitL2CustomGatewayLogic")),
            creationCode
        );

        // create proxy
        customGateway = L2CustomGateway(
            address(
                new TransparentUpgradeableProxy{
                    salt: keccak256(bytes("OrbitL2CustomGatewayProxy"))
                }(customGatewayLogicAddress, proxyAdmin, bytes(""))
            )
        );

        customGateway.initialize(l1CustomGateway, address(router));
    }
}
