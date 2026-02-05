// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {L1ERC20Gateway} from "./gateway/L1ERC20Gateway.sol";
import {L1CustomGateway} from "./gateway/L1CustomGateway.sol";
import {L1WethGateway} from "./gateway/L1WethGateway.sol";
import {L1OrbitERC20Gateway} from "./gateway/L1OrbitERC20Gateway.sol";
import {L1OrbitCustomGateway} from "./gateway/L1OrbitCustomGateway.sol";
import {L1YbbERC20Gateway} from "./gateway/L1YbbERC20Gateway.sol";
import {L1YbbCustomGateway} from "./gateway/L1YbbCustomGateway.sol";
import {IMasterVaultFactory} from "../libraries/vault/IMasterVaultFactory.sol";
import {IGatewayRouter} from "../libraries/gateway/IGatewayRouter.sol";
import {ClonableBeaconProxy} from "../libraries/ClonableBeaconProxy.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title L1GatewayDeployer
 * @notice Library for deploying all L1 gateway components (standard, custom, WETH, and YBB)
 */
library L1GatewayDeployer {
    // ============ Standard Gateway Structs ============

    struct StandardDeploymentParams {
        address inbox;
        address proxyAdmin;
        address upgradeExecutor;
        address router;
        address l2StandardGateway;
        address l2CustomGateway;
        address l2BeaconProxyFactory;
        bool isFeeTokenBased;
    }

    struct StandardTemplates {
        address standardGatewayTemplate;
        address feeTokenBasedStandardGatewayTemplate;
        address customGatewayTemplate;
        address feeTokenBasedCustomGatewayTemplate;
    }

    struct StandardDeploymentResult {
        address standardGateway;
        address customGateway;
    }

    // ============ WETH Gateway Structs ============

    struct WethDeploymentParams {
        address inbox;
        address proxyAdmin;
        address router;
        address l2WethGateway;
        address l1Weth;
        address l2Weth;
    }

    struct WethDeploymentResult {
        address wethGateway;
    }

    // ============ YBB Gateway Structs ============

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

    // ============ Standard Gateway Deployment ============

    function deployStandardGateways(
        StandardDeploymentParams memory params,
        StandardTemplates memory templates,
        bytes32 standardGatewaySalt,
        bytes32 customGatewaySalt
    ) external returns (StandardDeploymentResult memory result) {
        {
            address template = params.isFeeTokenBased
                ? templates.feeTokenBasedStandardGatewayTemplate
                : templates.standardGatewayTemplate;

            result.standardGateway = _deployProxy(standardGatewaySalt, template, params.proxyAdmin);

            L1ERC20Gateway(result.standardGateway)
                .initialize(
                    params.l2StandardGateway,
                    params.router,
                    params.inbox,
                    keccak256(type(ClonableBeaconProxy).creationCode),
                    params.l2BeaconProxyFactory
                );
        }

        {
            address template = params.isFeeTokenBased
                ? templates.feeTokenBasedCustomGatewayTemplate
                : templates.customGatewayTemplate;

            result.customGateway = _deployProxy(customGatewaySalt, template, params.proxyAdmin);

            L1CustomGateway(result.customGateway)
                .initialize(
                    params.l2CustomGateway, params.router, params.inbox, params.upgradeExecutor
                );
        }

        return result;
    }

    // ============ WETH Gateway Deployment ============

    function deployWethGateway(
        WethDeploymentParams memory params,
        address wethGatewayTemplate,
        bytes32 wethGatewaySalt
    ) external returns (WethDeploymentResult memory result) {
        result.wethGateway = _deployProxy(wethGatewaySalt, wethGatewayTemplate, params.proxyAdmin);

        L1WethGateway(payable(result.wethGateway))
            .initialize(
                params.l2WethGateway, params.router, params.inbox, params.l1Weth, params.l2Weth
            );

        return result;
    }

    // ============ YBB Gateway Deployment ============

    function deployYbbGateways(
        YbbDeploymentParams memory params,
        YbbTemplates memory templates,
        bytes32 masterVaultSalt,
        bytes32 standardGatewaySalt,
        bytes32 customGatewaySalt
    ) external returns (YbbDeploymentResult memory result) {
        result.masterVaultFactory =
            _deployProxy(masterVaultSalt, templates.masterVaultFactoryTemplate, params.proxyAdmin);

        result.standardGateway = _deployProxy(
            standardGatewaySalt, templates.ybbStandardGatewayTemplate, params.proxyAdmin
        );

        L1YbbERC20Gateway(result.standardGateway)
            .initialize(
                params.l2StandardGateway,
                params.router,
                params.inbox,
                keccak256(type(ClonableBeaconProxy).creationCode),
                params.l2BeaconProxyFactory,
                result.masterVaultFactory
            );

        result.customGateway =
            _deployProxy(customGatewaySalt, templates.ybbCustomGatewayTemplate, params.proxyAdmin);

        L1YbbCustomGateway(result.customGateway)
            .initialize(
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
        IMasterVaultFactory(masterVaultFactory).initialize(upgradeExecutor, IGatewayRouter(router));
    }

    // ============ Internal ============

    function _deployProxy(bytes32 salt, address logic, address admin) internal returns (address) {
        return address(new TransparentUpgradeableProxy{salt: salt}(logic, admin, bytes("")));
    }
}
