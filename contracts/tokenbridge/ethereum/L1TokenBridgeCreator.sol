// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { L1GatewayRouter } from "./gateway/L1GatewayRouter.sol";
import { L1ERC20Gateway } from "./gateway/L1ERC20Gateway.sol";
import { L1CustomGateway } from "./gateway/L1CustomGateway.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract L1TokenBridgeCreator is Ownable {
    event OrbitTokenBridgeCreated(
        address router,
        address standardGateway,
        address customGateway,
        address proxyAdmin
    );
    event OrbitTokenBridgeTemplatesUpdated();

    L1GatewayRouter public routerTemplate;
    L1ERC20Gateway public standardGatewayTemplate;
    L1CustomGateway public customGatewayTemplate;

    constructor() Ownable() {}

    function setTemplates(
        L1GatewayRouter _router,
        L1ERC20Gateway _standardGateway,
        L1CustomGateway _customGateway
    ) external onlyOwner {
        routerTemplate = _router;
        standardGatewayTemplate = _standardGateway;
        customGatewayTemplate = _customGateway;
        emit OrbitTokenBridgeTemplatesUpdated();
    }

    function createTokenBridge() external {
        address proxyAdmin = address(new ProxyAdmin());

        L1GatewayRouter router = L1GatewayRouter(
            address(new TransparentUpgradeableProxy(address(routerTemplate), proxyAdmin, bytes("")))
        );
        L1ERC20Gateway standardGateway = L1ERC20Gateway(
            address(
                new TransparentUpgradeableProxy(
                    address(standardGatewayTemplate),
                    proxyAdmin,
                    bytes("")
                )
            )
        );
        L1CustomGateway customGateway = L1CustomGateway(
            address(
                new TransparentUpgradeableProxy(
                    address(customGatewayTemplate),
                    proxyAdmin,
                    bytes("")
                )
            )
        );

        emit OrbitTokenBridgeCreated(
            address(router),
            address(standardGateway),
            address(customGateway),
            proxyAdmin
        );
    }

    function initTokenBridge(
        L1GatewayRouter router,
        L1ERC20Gateway standardGateway,
        L1CustomGateway customGateway,
        address owner,
        address inbox,
        address l2Router,
        address l2StandardGateway,
        address l2CustomGateway,
        bytes32 cloneableProxyHash,
        address l2BeaconProxyFactory
    ) external {
        /// dependencies - l2Router, l2StandardGateway, l2CustomGateway, cloneableProxyHash, l2BeaconProxyFactory, owner, inbox
        router.initialize(owner, address(standardGateway), address(0), l2Router, inbox);
        standardGateway.initialize(
            l2StandardGateway,
            address(router),
            inbox,
            cloneableProxyHash,
            l2BeaconProxyFactory
        );
        customGateway.initialize(l2CustomGateway, address(router), inbox, owner);
    }
}
