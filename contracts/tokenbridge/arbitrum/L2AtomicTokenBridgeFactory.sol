// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {L2GatewayRouter} from "./gateway/L2GatewayRouter.sol";
import {L2ERC20Gateway} from "./gateway/L2ERC20Gateway.sol";
import {L2CustomGateway} from "./gateway/L2CustomGateway.sol";
import {L2WethGateway} from "./gateway/L2WethGateway.sol";
import {StandardArbERC20} from "./StandardArbERC20.sol";
import {IUpgradeExecutor} from "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";
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
        // create proxyAdmin which will be used for all contracts
        address proxyAdmin =
            address(new ProxyAdmin{ salt: _getL2Salt(OrbitSalts.L2_PROXY_ADMIN) }());

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
        Create2.deploy(0, _getL2Salt(OrbitSalts.L2_MULTICALL), _creationCodeFor(l2Code.multicall));

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
        address canonicalUpgradeExecutor = address(
            new TransparentUpgradeableProxy{ salt: _getL2Salt(OrbitSalts.L2_EXECUTOR) }(
                address(new CanonicalAddressSeed{ salt: _getL2Salt(OrbitSalts.L2_EXECUTOR_LOGIC) }()),
                proxyAdmin,
                bytes("")
            )
        );

        // create UpgradeExecutor logic and upgrade to it
        address upExecutorLogic = Create2.deploy(
            0, _getL2Salt(OrbitSalts.L2_EXECUTOR_LOGIC), _creationCodeFor(runtimeCode)
        );
        ProxyAdmin(proxyAdmin).upgrade(
            ITransparentUpgradeableProxy(canonicalUpgradeExecutor), upExecutorLogic
        );

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
        address canonicalRouter = address(
            new TransparentUpgradeableProxy{ salt: _getL2Salt(OrbitSalts.L2_ROUTER) }(
                address(new CanonicalAddressSeed{ salt: _getL2Salt(OrbitSalts.L2_ROUTER_LOGIC) }()),
                proxyAdmin,
                bytes("")
            )
        );

        // create L2 router logic and upgrade
        address routerLogic =
            Create2.deploy(0, _getL2Salt(OrbitSalts.L2_ROUTER_LOGIC), _creationCodeFor(runtimeCode));
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(canonicalRouter), routerLogic);

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
        address canonicalStdGateway = address(
            new TransparentUpgradeableProxy{ salt: _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY) }(
                address(
                    new CanonicalAddressSeed{
                        salt: _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY_LOGIC)
                    }()
                ),
                proxyAdmin,
                bytes("")
            )
        );

        // create L2 standard gateway logic and upgrade
        address stdGatewayLogic = Create2.deploy(
            0, _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY_LOGIC), _creationCodeFor(runtimeCode)
        );
        ProxyAdmin(proxyAdmin).upgrade(
            ITransparentUpgradeableProxy(canonicalStdGateway), stdGatewayLogic
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
        address canonicalCustomGateway = address(
            new TransparentUpgradeableProxy{ salt: _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY) }(
                address(
                    new CanonicalAddressSeed{
                        salt: _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY_LOGIC)
                    }()
                ),
                proxyAdmin,
                bytes("")
            )
        );

        // create L2 custom gateway logic and upgrade
        address customGatewayLogicAddress = Create2.deploy(
            0, _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY_LOGIC), _creationCodeFor(runtimeCode)
        );
        ProxyAdmin(proxyAdmin).upgrade(
            ITransparentUpgradeableProxy(canonicalCustomGateway), customGatewayLogicAddress
        );

        // init
        L2GatewayRouter(canonicalCustomGateway).initialize(l1CustomGateway, router);
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
        address canonicalL2Weth = address(
            new TransparentUpgradeableProxy{ salt: _getL2Salt(OrbitSalts.L2_WETH) }(
                address(new CanonicalAddressSeed{ salt: _getL2Salt(OrbitSalts.L2_WETH_LOGIC) }()),
                proxyAdmin,
                bytes("")
            )
        );

        // create L2WETH logic and upgrade
        address l2WethLogic = Create2.deploy(
            0, _getL2Salt(OrbitSalts.L2_WETH_LOGIC), _creationCodeFor(aeWethRuntimeCode)
        );
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(canonicalL2Weth), l2WethLogic);

        // canonical L2 WETH gateway with dummy logic
        address canonicalL2WethGateway = address(
            new TransparentUpgradeableProxy{ salt: _getL2Salt(OrbitSalts.L2_WETH_GATEWAY) }(
                address(
                    new CanonicalAddressSeed{ salt: _getL2Salt(OrbitSalts.L2_WETH_GATEWAY_LOGIC) }()
                ),
                proxyAdmin,
                bytes("")
            )
        );

        // create L2WETH gateway logic and upgrade
        address l2WethGatewayLogic = Create2.deploy(
            0,
            _getL2Salt(OrbitSalts.L2_WETH_GATEWAY_LOGIC),
            _creationCodeFor(wethGatewayRuntimeCode)
        );
        ProxyAdmin(proxyAdmin).upgrade(
            ITransparentUpgradeableProxy(canonicalL2WethGateway), l2WethGatewayLogic
        );

        // init gateway
        L2WethGateway(payable(canonicalL2WethGateway)).initialize(
            l1WethGateway, router, l1Weth, address(canonicalL2Weth)
        );

        // init L2Weth
        aeWETH(payable(canonicalL2Weth)).initialize(
            "WETH", "WETH", 18, canonicalL2WethGateway, l1Weth
        );
    }

    function _getL2Salt(bytes memory prefix) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(prefix, msg.sender));
    }

    /**
     * @notice Generate a creation code that results on a contract with `code` as bytecode.
     *         Source - https://github.com/0xsequence/sstore2/blob/master/contracts/utils/Bytecode.sol
     * @param code The returning value of the resulting `creationCode`
     * @return creationCode (constructor) for new contract
     */
    function _creationCodeFor(bytes memory code) internal pure returns (bytes memory) {
        /*
            0x00    0x63         0x63XXXXXX  PUSH4 _code.length  size
            0x01    0x80         0x80        DUP1                size size
            0x02    0x60         0x600e      PUSH1 14            14 size size
            0x03    0x60         0x6000      PUSH1 00            0 14 size size
            0x04    0x39         0x39        CODECOPY            size
            0x05    0x60         0x6000      PUSH1 00            0 size
            0x06    0xf3         0xf3        RETURN
            <CODE>
        */

        return abi.encodePacked(hex"63", uint32(code.length), hex"80600E6000396000F3", code);
    }
}

/**
 * Dummy contract used as initial logic contract for proxies, in order to get canonical (CREATE2 based) address. Then we can upgrade to any logic without having canonical addresses impacted.
 */
contract CanonicalAddressSeed {}

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
 */
library OrbitSalts {
    bytes public constant L1_PROXY_ADMIN = bytes("OrbitL1ProxyAdmin");
    bytes public constant L1_ROUTER = bytes("OrbitL1GatewayRouterProxy");
    bytes public constant L1_STANDARD_GATEWAY = bytes("OrbitL1StandardGatewayProxy");
    bytes public constant L1_CUSTOM_GATEWAY = bytes("OrbitL1CustomGatewayProxy");
    bytes public constant L1_WETH_GATEWAY = bytes("OrbitL1WethGatewayProxy");

    bytes public constant L2_PROXY_ADMIN = bytes("OrbitL2ProxyAdmin");
    bytes public constant L2_ROUTER_LOGIC = bytes("OrbitL2GatewayRouterLogic");
    bytes public constant L2_ROUTER = bytes("OrbitL2GatewayRouterProxy");
    bytes public constant L2_STANDARD_GATEWAY_LOGIC = bytes("OrbitL2StandardGatewayLogic");
    bytes public constant L2_STANDARD_GATEWAY = bytes("OrbitL2StandardGatewayProxy");
    bytes public constant L2_CUSTOM_GATEWAY_LOGIC = bytes("OrbitL2CustomGatewayLogic");
    bytes public constant L2_CUSTOM_GATEWAY = bytes("OrbitL2CustomGatewayProxy");
    bytes public constant L2_WETH_GATEWAY_LOGIC = bytes("OrbitL2WethGatewayLogic");
    bytes public constant L2_WETH_GATEWAY = bytes("OrbitL2WethGatewayProxy");
    bytes public constant L2_WETH_LOGIC = bytes("OrbitL2WETH");
    bytes public constant L2_WETH = bytes("OrbitL2WETHProxy");
    bytes public constant L2_STANDARD_ERC20 = bytes("OrbitStandardArbERC20");
    bytes public constant UPGRADEABLE_BEACON = bytes("OrbitUpgradeableBeacon");
    bytes public constant BEACON_PROXY_FACTORY = bytes("OrbitBeaconProxyFactory");
    bytes public constant L2_EXECUTOR_LOGIC = bytes("OrbitL2UpgradeExecutorLogic");
    bytes public constant L2_EXECUTOR = bytes("OrbitL2UpgradeExecutorProxy");
    bytes public constant L2_MULTICALL = bytes("OrbitL2Multicall");
}
