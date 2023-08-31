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

    function deployL2Contracts(
        L2RuntimeCode calldata l2Code,
        address l1Router,
        address l1StandardGateway,
        address l1CustomGateway,
        address l1WethGateway,
        address l1Weth,
        address l2StandardGatewayCanonicalAddress,
        address rollupOwner
    ) external {
        // create proxyAdmin which will be used for all contracts. Revert if canonical deployment already exists
        address proxyAdminAddress = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_PROXY_ADMIN), keccak256(type(ProxyAdmin).creationCode), address(this)
        );
        if (proxyAdminAddress.code.length > 0) {
            revert L2AtomicTokenBridgeFactory_AlreadyExists();
        }
        address proxyAdmin = address(new ProxyAdmin{ salt: _getL2Salt(OrbitSalts.L2_PROXY_ADMIN) }());

        // deploy router/gateways
        address router = _deployRouter(l2Code.router, l1Router, l2StandardGatewayCanonicalAddress, proxyAdmin);
        _deployStandardGateway(l2Code.standardGateway, l1StandardGateway, router, proxyAdmin);
        _deployCustomGateway(l2Code.customGateway, l1CustomGateway, router, proxyAdmin);
        _deployWethGateway(l2Code.wethGateway, l2Code.aeWeth, l1WethGateway, l1Weth, router, proxyAdmin);

        // transfer ownership to rollup's owner
        ProxyAdmin(proxyAdmin).transferOwnership(rollupOwner);
    }

    function _deployRouter(
        bytes calldata runtimeCode,
        address l1Router,
        address l2StandardGatewayCanonicalAddress,
        address proxyAdmin
    ) internal returns (address) {
        // canonical L2 router with dummy logic
        address canonicalRouter =
            _deploySeedProxy(proxyAdmin, _getL2Salt(OrbitSalts.L2_ROUTER), _getL2Salt(OrbitSalts.L2_ROUTER_LOGIC));

        // create L2 router logic and upgrade
        address routerLogic = Create2.deploy(0, _getL2Salt(OrbitSalts.L2_ROUTER_LOGIC), _creationCodeFor(runtimeCode));
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(canonicalRouter), routerLogic);

        // init
        L2GatewayRouter(canonicalRouter).initialize(l1Router, l2StandardGatewayCanonicalAddress);

        return canonicalRouter;
    }

    function _deployStandardGateway(
        bytes calldata runtimeCode,
        address l1StandardGateway,
        address router,
        address proxyAdmin
    ) internal {
        // canonical L2 standard gateway with dummy logic
        address canonicalStdGateway = _deploySeedProxy(
            proxyAdmin, _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY), _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY_LOGIC)
        );

        // create L2 standard gateway logic and upgrade
        address stdGatewayLogic =
            Create2.deploy(0, _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY_LOGIC), _creationCodeFor(runtimeCode));
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(canonicalStdGateway), stdGatewayLogic);

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
        L2ERC20Gateway(canonicalStdGateway).initialize(l1StandardGateway, router, address(beaconProxyFactory));
    }

    function _deployCustomGateway(
        bytes calldata runtimeCode,
        address l1CustomGateway,
        address router,
        address proxyAdmin
    ) internal {
        // canonical L2 custom gateway with dummy logic
        address canonicalCustomGateway = _deploySeedProxy(
            proxyAdmin, _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY), _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY_LOGIC)
        );

        // create L2 custom gateway logic and upgrade
        address customGatewayLogicAddress =
            Create2.deploy(0, _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY_LOGIC), _creationCodeFor(runtimeCode));
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(canonicalCustomGateway), customGatewayLogicAddress);

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
        address canonicalL2Weth =
            _deploySeedProxy(proxyAdmin, _getL2Salt(OrbitSalts.L2_WETH), _getL2Salt(OrbitSalts.L2_WETH_LOGIC));

        // create L2WETH logic and upgrade
        address l2WethLogic =
            Create2.deploy(0, _getL2Salt(OrbitSalts.L2_WETH_LOGIC), _creationCodeFor(aeWethRuntimeCode));
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(canonicalL2Weth), l2WethLogic);

        // canonical L2 WETH gateway with dummy logic
        address canonicalL2WethGateway = _deploySeedProxy(
            proxyAdmin, _getL2Salt(OrbitSalts.L2_WETH_GATEWAY), _getL2Salt(OrbitSalts.L2_WETH_GATEWAY_LOGIC)
        );

        // create L2WETH gateway logic and upgrade
        address l2WethGatewayLogic =
            Create2.deploy(0, _getL2Salt(OrbitSalts.L2_WETH_GATEWAY_LOGIC), _creationCodeFor(wethGatewayRuntimeCode));
        ProxyAdmin(proxyAdmin).upgrade(ITransparentUpgradeableProxy(canonicalL2WethGateway), l2WethGatewayLogic);

        // init gateway
        L2WethGateway(payable(canonicalL2WethGateway)).initialize(
            l1WethGateway, router, l1Weth, address(canonicalL2Weth)
        );

        // init L2Weth
        aeWETH(payable(canonicalL2Weth)).initialize("WETH", "WETH", 18, canonicalL2WethGateway, l1Weth);
    }

    function _getL2Salt(bytes32 prefix) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(prefix, msg.sender));
    }

    /**
     * Deploys a proxy with empty logic contract in order to get deterministic address which does not depend on actual logic contract.
     */
    function _deploySeedProxy(address proxyAdmin, bytes32 proxySalt, bytes32 logicSalt) internal returns (address) {
        return address(
            new TransparentUpgradeableProxy{ salt: proxySalt }(
                address(new CanonicalAddressSeed{ salt: logicSalt}()),
                proxyAdmin,
                bytes("")
            )
        );
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
