// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {L1YbbERC20Gateway} from "./gateway/L1YbbERC20Gateway.sol";
import {L1YbbCustomGateway} from "./gateway/L1YbbCustomGateway.sol";
import {IMasterVaultFactory} from "../libraries/vault/IMasterVaultFactory.sol";
import {IGatewayRouter} from "../libraries/gateway/IGatewayRouter.sol";
import {ClonableBeaconProxy} from "../libraries/ClonableBeaconProxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

library L1YbbBridgeDeployer {
    struct YbbDeploymentParams {
        address inbox;
        address proxyAdmin;
        address upgradeExecutor;
        address router;
        address l2StandardGateway;
        address l2CustomGateway;
        address l2BeaconProxyFactory;
    }

    struct YbbTemplates {
        address ybbStandardGatewayTemplate;
        address ybbCustomGatewayTemplate;
        address masterVaultFactoryTemplate;
    }

    struct YbbDeploymentResult {
        address masterVaultFactory;
        address standardGateway;
        address customGateway;
    }

    function deployYbbComponents(
        YbbDeploymentParams memory params,
        YbbTemplates memory templates,
        bytes32 masterVaultSalt,
        bytes32 standardGatewaySalt,
        bytes32 customGatewaySalt
    ) external returns (YbbDeploymentResult memory result) {
        // Deploy MasterVaultFactory
        result.masterVaultFactory = _deployProxy(
            masterVaultSalt,
            templates.masterVaultFactoryTemplate,
            params.proxyAdmin
        );

        // Deploy and initialize YBB Standard Gateway
        result.standardGateway = _deployProxy(
            standardGatewaySalt,
            templates.ybbStandardGatewayTemplate,
            params.proxyAdmin
        );

        L1YbbERC20Gateway(result.standardGateway).initialize(
            params.l2StandardGateway,
            params.router,
            params.inbox,
            keccak256(type(ClonableBeaconProxy).creationCode),
            params.l2BeaconProxyFactory,
            result.masterVaultFactory
        );

        // Deploy and initialize YBB Custom Gateway
        result.customGateway = _deployProxy(
            customGatewaySalt,
            templates.ybbCustomGatewayTemplate,
            params.proxyAdmin
        );

        L1YbbCustomGateway(result.customGateway).initialize(
            params.l2CustomGateway,
            params.router,
            params.inbox,
            params.upgradeExecutor,
            result.masterVaultFactory
        );

        return result;
    }

    function initializeMasterVaultFactory(
        address masterVaultFactory,
        address upgradeExecutor,
        address router
    ) external {
        IMasterVaultFactory(masterVaultFactory).initialize(
            upgradeExecutor,
            IGatewayRouter(router)
        );
    }

    function _deployProxy(
        bytes32 salt,
        address logic,
        address admin
    ) internal returns (address) {
        return address(
            new TransparentUpgradeableProxy{salt: salt}(logic, admin, bytes(""))
        );
    }
}
