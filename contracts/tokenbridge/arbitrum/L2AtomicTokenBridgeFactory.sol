// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {L2GatewayRouter} from "./gateway/L2GatewayRouter.sol";
import {L2ERC20Gateway} from "./gateway/L2ERC20Gateway.sol";
import {L2CustomGateway} from "./gateway/L2CustomGateway.sol";
import {L2WethGateway} from "./gateway/L2WethGateway.sol";
import {StandardArbERC20} from "./StandardArbERC20.sol";
import {IUpgradeExecutor} from "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";
import {CreationCodeHelper} from "../libraries/CreationCodeHelper.sol";
import {BeaconProxyFactory} from "../libraries/ClonableBeaconProxy.sol";
import {aeWETH} from "../libraries/aeWETH.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title Layer2 token bridge creator
 * @notice This contract is used to deploy token bridge on L2 chain.
 * @dev L1AtomicTokenBridgeCreator shall call `deployL2Contracts` using retryable and that will result in deployment of canonical token bridge contracts.
 */
contract L2AtomicTokenBridgeFactory {
    error L2AtomicTokenBridgeFactory_AlreadyExists();

    // In order to avoid having uninitialized logic contracts, `initialize` function will be called
    // on all logic contracts which don't have initializers disabled. This dummy non-zero address
    // will be provided to those initializers, as values written to the logic contract's storage
    // are not used.
    address private constant ADDRESS_DEAD = address(0x000000000000000000000000000000000000dEaD);

    function deployL2Contracts(
        L2RuntimeCode calldata l2Code,
        address l1Router,
        address l1StandardGateway,
        address l1CustomGateway,
        address l1WethGateway,
        address l1Weth,
        address l2StandardGatewayCanonicalAddress,
        address rollupOwner,
        address aliasedL1UpgradeExecutor
    ) external {
        // Create proxyAdmin which will be used for all contracts. Revert if canonical deployment already exists
        {
            address proxyAdminAddress = Create2.computeAddress(
                _getL2Salt(OrbitSalts.L2_PROXY_ADMIN),
                keccak256(type(ProxyAdmin).creationCode),
                address(this)
            );
            if (proxyAdminAddress.code.length > 0) {
                revert L2AtomicTokenBridgeFactory_AlreadyExists();
            }
        }
        address proxyAdmin = address(new ProxyAdmin{salt: _getL2Salt(OrbitSalts.L2_PROXY_ADMIN)}());

        // deploy router/gateways/executor
        address upgradeExecutor = _deployUpgradeExecutor(
            l2Code.upgradeExecutor, rollupOwner, proxyAdmin, aliasedL1UpgradeExecutor
        );
        address router =
            _deployRouter(l2Code.router, l1Router, l2StandardGatewayCanonicalAddress, proxyAdmin);
        _deployStandardGateway(
            l2Code.standardGateway, l1StandardGateway, router, proxyAdmin, upgradeExecutor
        );
        _deployCustomGateway(l2Code.customGateway, l1CustomGateway, router, proxyAdmin);

        // fee token based creator will provide address(0) as WETH is not used in ERC20-based chains
        if (l1WethGateway != address(0)) {
            _deployWethGateway(
                l2Code.wethGateway, l2Code.aeWeth, l1WethGateway, l1Weth, router, proxyAdmin
            );
        }

        // deploy multicall
        Create2.deploy(
            0,
            _getL2Salt(OrbitSalts.L2_MULTICALL),
            CreationCodeHelper.getCreationCodeFor(l2Code.multicall)
        );

        // transfer ownership to L2 upgradeExecutor
        ProxyAdmin(proxyAdmin).transferOwnership(upgradeExecutor);
    }

    function _deployUpgradeExecutor(
        bytes calldata runtimeCode,
        address rollupOwner,
        address proxyAdmin,
        address aliasedL1UpgradeExecutor
    ) internal returns (address) {
        // canonical L2 upgrade executor with dummy logic
        address canonicalUpgradeExecutor = _deploySeedProxy(proxyAdmin, OrbitSalts.L2_EXECUTOR);

        // Create UpgradeExecutor logic and upgrade to it.
        address upExecutorLogic = Create2.deploy(
            0,
            _getL2Salt(OrbitSalts.L2_EXECUTOR),
            CreationCodeHelper.getCreationCodeFor(runtimeCode)
        );

        ProxyAdmin(proxyAdmin).upgrade(
            ITransparentUpgradeableProxy(canonicalUpgradeExecutor), upExecutorLogic
        );

        // init logic contract with dummy values
        address[] memory empty = new address[](0);
        IUpgradeExecutor(upExecutorLogic).initialize(ADDRESS_DEAD, empty);

        // init upgrade executor
        address[] memory executors = new address[](2);
        executors[0] = rollupOwner;
        executors[1] = aliasedL1UpgradeExecutor;
        IUpgradeExecutor(canonicalUpgradeExecutor).initialize(canonicalUpgradeExecutor, executors);

        return canonicalUpgradeExecutor;
    }

    function _deployRouter(
        bytes calldata runtimeCode,
        address l1Router,
        address l2StandardGatewayCanonicalAddress,
        address proxyAdmin
    ) internal returns (address) {
        // canonical L2 router with dummy logic
        address canonicalRouter = _deploySeedProxy(proxyAdmin, OrbitSalts.L2_ROUTER);

        // create L2 router logic and upgrade
        address routerLogic = Create2.deploy(
            0, _getL2Salt(OrbitSalts.L2_ROUTER), CreationCodeHelper.getCreationCodeFor(runtimeCode)
        );
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(canonicalRouter), routerLogic);

        // init logic contract with dummy values.
        L2GatewayRouter(routerLogic).initialize(ADDRESS_DEAD, ADDRESS_DEAD);

        // init
        L2GatewayRouter(canonicalRouter).initialize(l1Router, l2StandardGatewayCanonicalAddress);

        return canonicalRouter;
    }

    function _deployStandardGateway(
        bytes calldata runtimeCode,
        address l1StandardGateway,
        address router,
        address proxyAdmin,
        address upgradeExecutor
    ) internal {
        // canonical L2 standard gateway with dummy logic
        address canonicalStdGateway = _deploySeedProxy(proxyAdmin, OrbitSalts.L2_STANDARD_GATEWAY);

        // create L2 standard gateway logic and upgrade
        address stdGatewayLogic = Create2.deploy(
            0,
            _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY),
            CreationCodeHelper.getCreationCodeFor(runtimeCode)
        );
        ProxyAdmin(proxyAdmin).upgrade(
            ITransparentUpgradeableProxy(canonicalStdGateway), stdGatewayLogic
        );

        // init logic contract with dummy values
        L2ERC20Gateway(stdGatewayLogic).initialize(ADDRESS_DEAD, ADDRESS_DEAD, ADDRESS_DEAD);

        // create beacon
        StandardArbERC20 standardArbERC20 =
            new StandardArbERC20{salt: _getL2Salt(OrbitSalts.BEACON_PROXY_FACTORY)}();
        UpgradeableBeacon beacon = new UpgradeableBeacon{
            salt: _getL2Salt(OrbitSalts.BEACON_PROXY_FACTORY)
        }(address(standardArbERC20));
        BeaconProxyFactory beaconProxyFactory =
            new BeaconProxyFactory{salt: _getL2Salt(OrbitSalts.BEACON_PROXY_FACTORY)}();

        // init contracts
        beaconProxyFactory.initialize(address(beacon));
        L2ERC20Gateway(canonicalStdGateway).initialize(
            l1StandardGateway, router, address(beaconProxyFactory)
        );

        // make L2 executor the beacon owner
        beacon.transferOwnership(upgradeExecutor);
    }

    function _deployCustomGateway(
        bytes calldata runtimeCode,
        address l1CustomGateway,
        address router,
        address proxyAdmin
    ) internal {
        // canonical L2 custom gateway with dummy logic
        address canonicalCustomGateway = _deploySeedProxy(proxyAdmin, OrbitSalts.L2_CUSTOM_GATEWAY);

        // create L2 custom gateway logic and upgrade
        address customGatewayLogicAddress = Create2.deploy(
            0,
            _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY),
            CreationCodeHelper.getCreationCodeFor(runtimeCode)
        );
        ProxyAdmin(proxyAdmin).upgrade(
            ITransparentUpgradeableProxy(canonicalCustomGateway), customGatewayLogicAddress
        );

        // init logic contract with dummy values
        L2CustomGateway(customGatewayLogicAddress).initialize(ADDRESS_DEAD, ADDRESS_DEAD);

        // init
        L2CustomGateway(canonicalCustomGateway).initialize(l1CustomGateway, router);
    }

    function _deployWethGateway(
        bytes calldata wethGatewayRuntimeCode,
        bytes calldata aeWethRuntimeCode,
        address l1WethGateway,
        address l1Weth,
        address router,
        address proxyAdmin
    ) internal {
        // canonical L2 WETH with dummy logic
        address canonicalL2Weth = _deploySeedProxy(proxyAdmin, OrbitSalts.L2_WETH);

        // Create L2WETH logic and upgrade
        address l2WethLogic = Create2.deploy(
            0,
            _getL2Salt(OrbitSalts.L2_WETH),
            CreationCodeHelper.getCreationCodeFor(aeWethRuntimeCode)
        );
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(canonicalL2Weth), l2WethLogic);

        // canonical L2 WETH gateway with dummy logic
        address canonicalL2WethGateway = _deploySeedProxy(proxyAdmin, OrbitSalts.L2_WETH_GATEWAY);

        // create L2WETH gateway logic and upgrade
        address l2WethGatewayLogic = Create2.deploy(
            0,
            _getL2Salt(OrbitSalts.L2_WETH_GATEWAY),
            CreationCodeHelper.getCreationCodeFor(wethGatewayRuntimeCode)
        );
        ProxyAdmin(proxyAdmin).upgrade(
            ITransparentUpgradeableProxy(canonicalL2WethGateway), l2WethGatewayLogic
        );

        // init logic contract with dummy values
        L2WethGateway(payable(l2WethGatewayLogic)).initialize(
            ADDRESS_DEAD, ADDRESS_DEAD, ADDRESS_DEAD, ADDRESS_DEAD
        );

        // init gateway
        L2WethGateway(payable(canonicalL2WethGateway)).initialize(
            l1WethGateway, router, l1Weth, address(canonicalL2Weth)
        );

        // init logic contract with dummy values
        aeWETH(payable(l2WethLogic)).initialize("", "", 0, ADDRESS_DEAD, ADDRESS_DEAD);

        // init L2Weth
        aeWETH(payable(canonicalL2Weth)).initialize(
            "WETH", "WETH", 18, canonicalL2WethGateway, l1Weth
        );
    }

    /**
     * In addition to hard-coded prefix, salt for L2 contracts depends on msg.sender and the chainId. Deploying L2 token bridge contracts is
     * permissionless. By making msg.sender part of the salt we know exactly which set of contracts is the "canonical" one for given chain,
     * deployed by L1TokenBridgeRetryableSender via retryable ticket.
     */
    function _getL2Salt(bytes memory prefix) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(prefix, block.chainid, msg.sender));
    }

    /**
     * Deploys a proxy with address(this) as logic in order to get deterministic address
     * the proxy is salted using a salt derived from the prefix, the chainId and the sender
     */
    function _deploySeedProxy(address proxyAdmin, bytes memory prefix) internal returns (address) {
        return address(
            new TransparentUpgradeableProxy{salt: _getL2Salt(prefix)}(
                address(this), proxyAdmin, bytes("")
            )
        );
    }
}

/**
 * Placeholder for bytecode of token bridge contracts which is sent from L1 to L2 through retryable ticket.
 */
struct L2RuntimeCode {
    bytes router;
    bytes standardGateway;
    bytes customGateway;
    bytes wethGateway;
    bytes aeWeth;
    bytes upgradeExecutor;
    bytes multicall;
}

/**
 * Collection of salts used in CREATE2 deployment of L2 token bridge contracts.
 * Logic contracts are deployed using the same salt as the proxy, it's fine as they have different code
 */
library OrbitSalts {
    bytes internal constant L1_ROUTER = bytes("L1R");
    bytes internal constant L1_STANDARD_GATEWAY = bytes("L1SGW");
    bytes internal constant L1_CUSTOM_GATEWAY = bytes("L1CGW");
    bytes internal constant L1_WETH_GATEWAY = bytes("L1WGW");

    bytes internal constant L2_PROXY_ADMIN = bytes("L2PA");
    bytes internal constant L2_ROUTER = bytes("L2R");
    bytes internal constant L2_STANDARD_GATEWAY = bytes("L2SGW");
    bytes internal constant L2_CUSTOM_GATEWAY = bytes("L2CGW");
    bytes internal constant L2_WETH_GATEWAY = bytes("L2WGW");
    bytes internal constant L2_WETH = bytes("L2W");
    bytes internal constant BEACON_PROXY_FACTORY = bytes("L2BPF");
    bytes internal constant L2_EXECUTOR = bytes("L2E");
    bytes internal constant L2_MULTICALL = bytes("L2MC");
}
