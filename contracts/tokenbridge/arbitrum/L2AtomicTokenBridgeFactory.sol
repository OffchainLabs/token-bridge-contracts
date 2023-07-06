// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {L2GatewayRouter} from "./gateway/L2GatewayRouter.sol";
import {L2ERC20Gateway} from "./gateway/L2ERC20Gateway.sol";
import {L2CustomGateway} from "./gateway/L2CustomGateway.sol";
import {L2WethGateway} from "./gateway/L2WethGateway.sol";
import {StandardArbERC20} from "./StandardArbERC20.sol";
import {BeaconProxyFactory} from "../libraries/ClonableBeaconProxy.sol";
import {aeWETH} from "../libraries/aeWETH.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title Layer2 token bridge creator
 * @notice This contract is used to deploy token bridge on L2 chain.
 * @dev L1AtomicTokenBridgeCreator shall call `deployL2Contracts` using retryable and that will result in deployment of canonical token bridge contracts.
 */
contract L2AtomicTokenBridgeFactory {
    function deployL2Contracts(
        bytes memory routerCreationCode,
        bytes memory standardGatewayCreationCode,
        bytes memory customGatewayCreationCode,
        bytes memory wethGatewayCreationCode,
        bytes memory aeWethCreationCode,
        address l1Router,
        address l1StandardGateway,
        address l1CustomGateway,
        address l1WethGateway,
        address l1Weth,
        address l2StandardGatewayExpectedAddress,
        address proxyAdminOwner
    ) external {
        // create proxyAdmin which will be used for all contracts
        address proxyAdmin = address(new ProxyAdmin{ salt: _getL2Salt(OrbitSalts.L2_PROXY_ADMIN) }());

        // deploy router/gateways
        address router = _deployRouter(routerCreationCode, l1Router, l2StandardGatewayExpectedAddress, proxyAdmin);
        _deployStandardGateway(standardGatewayCreationCode, l1StandardGateway, router, proxyAdmin);
        _deployCustomGateway(customGatewayCreationCode, l1CustomGateway, router, proxyAdmin);
        _deployWethGateway(wethGatewayCreationCode, aeWethCreationCode, l1WethGateway, l1Weth, router, proxyAdmin);

        // transfer ownership to L1Creator's msg.sender
        ProxyAdmin(proxyAdmin).transferOwnership(proxyAdminOwner);
    }

    function _deployRouter(
        bytes memory creationCode,
        address l1Router,
        address l2StandardGatewayExpectedAddress,
        address proxyAdmin
    ) internal returns (address) {
        // create logic and proxy
        address routerLogicAddress = Create2.deploy(0, _getL2Salt(OrbitSalts.L2_ROUTER_LOGIC), creationCode);
        L2GatewayRouter router = L2GatewayRouter(
            address(
                new TransparentUpgradeableProxy{ salt: _getL2Salt(OrbitSalts.L2_ROUTER) }(
                    routerLogicAddress,
                    proxyAdmin,
                    bytes("")
                )
            )
        );

        // init
        router.initialize(l1Router, l2StandardGatewayExpectedAddress);

        return address(router);
    }

    function _deployStandardGateway(
        bytes memory creationCode,
        address l1StandardGateway,
        address router,
        address proxyAdmin
    ) internal {
        // create logic and proxy
        address standardGatewayLogicAddress =
            Create2.deploy(0, _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY_LOGIC), creationCode);
        L2ERC20Gateway standardGateway = L2ERC20Gateway(
            address(
                new TransparentUpgradeableProxy{
                    salt: _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY)
                }(standardGatewayLogicAddress, proxyAdmin, bytes(""))
            )
        );

        // create beacon
        StandardArbERC20 standardArbERC20 = new StandardArbERC20{
            salt: _getL2Salt(OrbitSalts.L2_STANDARD_ERC20)
        }();
        UpgradeableBeacon beacon = new UpgradeableBeacon{
            salt: _getL2Salt(OrbitSalts.UPGRADEABLE_BEACON)
        }(address(standardArbERC20));
        BeaconProxyFactory beaconProxyFactory = new BeaconProxyFactory{
            salt: _getL2Salt(OrbitSalts.BEACON_PROXY_FACTORY)
        }();

        // init contracts
        beaconProxyFactory.initialize(address(beacon));
        standardGateway.initialize(l1StandardGateway, router, address(beaconProxyFactory));
    }

    function _deployCustomGateway(
        bytes memory creationCode,
        address l1CustomGateway,
        address router,
        address proxyAdmin
    ) internal {
        address customGatewayLogicAddress =
            Create2.deploy(0, _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY_LOGIC), creationCode);

        // create logic and proxy
        L2CustomGateway customGateway = L2CustomGateway(
            address(
                new TransparentUpgradeableProxy{ salt: _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY) }(
                    customGatewayLogicAddress,
                    proxyAdmin,
                    bytes("")
                )
            )
        );

        // init
        customGateway.initialize(l1CustomGateway, router);
    }

    function _deployWethGateway(
        bytes memory wethGatewayCreationCode,
        bytes memory aeWethCreationCode,
        address l1WethGateway,
        address l1Weth,
        address router,
        address proxyAdmin
    ) internal {
        // L2 WETH
        address aeWethLogic = Create2.deploy(0, _getL2Salt(OrbitSalts.L2_WETH_LOGIC), aeWethCreationCode);
        aeWETH l2Weth = aeWETH(
            payable(
                address(
                    new TransparentUpgradeableProxy{ salt: _getL2Salt(OrbitSalts.L2_WETH) }(
                        aeWethLogic,
                        proxyAdmin,
                        bytes("")
                    )
                )
            )
        );

        // WETH gateway
        address wethGatewayLogicAddress =
            Create2.deploy(0, _getL2Salt(OrbitSalts.L2_WETH_GATEWAY_LOGIC), wethGatewayCreationCode);
        L2WethGateway wethGateway = L2WethGateway(
            payable(
                address(
                    new TransparentUpgradeableProxy{
                        salt: _getL2Salt(OrbitSalts.L2_WETH_GATEWAY)
                    }(wethGatewayLogicAddress, proxyAdmin, bytes(""))
                )
            )
        );

        // init gateway
        wethGateway.initialize(l1WethGateway, router, l1Weth, address(l2Weth));

        // init L2Weth
        l2Weth.initialize("WETH", "WETH", 18, address(wethGateway), l1Weth);
    }

    function _getL2Salt(bytes32 prefix) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(prefix, msg.sender));
    }
}

/**
 * Collection of salts used in CREATE2 deployment of L2 token bridge contracts.
 */
library OrbitSalts {
    bytes32 public constant L1_PROXY_ADMIN = keccak256(bytes("OrbitL1ProxyAdmin"));
    bytes32 public constant L1_ROUTER = keccak256(bytes("OrbitL1GatewayRouterProxy"));
    bytes32 public constant L1_STANDARD_GATEWAY = keccak256(bytes("OrbitL1StandardGatewayProxy"));
    bytes32 public constant L1_CUSTOM_GATEWAY = keccak256(bytes("OrbitL1CustomGatewayProxy"));
    bytes32 public constant L1_WETH_GATEWAY = keccak256(bytes("OrbitL1WethGatewayProxy"));

    bytes32 public constant L2_PROXY_ADMIN = keccak256(bytes("OrbitL2ProxyAdmin"));
    bytes32 public constant L2_ROUTER_LOGIC = keccak256(bytes("OrbitL2GatewayRouterLogic"));
    bytes32 public constant L2_ROUTER = keccak256(bytes("OrbitL2GatewayRouterProxy"));
    bytes32 public constant L2_STANDARD_GATEWAY_LOGIC = keccak256(bytes("OrbitL2StandardGatewayLogic"));
    bytes32 public constant L2_STANDARD_GATEWAY = keccak256(bytes("OrbitL2StandardGatewayProxy"));
    bytes32 public constant L2_CUSTOM_GATEWAY_LOGIC = keccak256(bytes("OrbitL2CustomGatewayLogic"));
    bytes32 public constant L2_CUSTOM_GATEWAY = keccak256(bytes("OrbitL2CustomGatewayProxy"));
    bytes32 public constant L2_WETH_GATEWAY_LOGIC = keccak256(bytes("OrbitL2WethGatewayLogic"));
    bytes32 public constant L2_WETH_GATEWAY = keccak256(bytes("OrbitL2WethGatewayProxy"));
    bytes32 public constant L2_WETH_LOGIC = keccak256(bytes("OrbitL2WETH"));
    bytes32 public constant L2_WETH = keccak256(bytes("OrbitL2WETHProxy"));
    bytes32 public constant L2_STANDARD_ERC20 = keccak256(bytes("OrbitStandardArbERC20"));
    bytes32 public constant UPGRADEABLE_BEACON = keccak256(bytes("OrbitUpgradeableBeacon"));
    bytes32 public constant BEACON_PROXY_FACTORY = keccak256(bytes("OrbitBeaconProxyFactory"));
}
