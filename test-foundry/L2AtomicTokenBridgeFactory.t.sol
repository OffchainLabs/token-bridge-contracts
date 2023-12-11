// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {
    L2AtomicTokenBridgeFactory,
    L2RuntimeCode,
    ProxyAdmin
} from "contracts/tokenbridge/arbitrum/L2AtomicTokenBridgeFactory.sol";
import {L2GatewayRouter} from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import {L2ERC20Gateway} from "contracts/tokenbridge/arbitrum/gateway/L2ERC20Gateway.sol";
import {L2CustomGateway} from "contracts/tokenbridge/arbitrum/gateway/L2CustomGateway.sol";
import {L2WethGateway} from "contracts/tokenbridge/arbitrum/gateway/L2WethGateway.sol";
import {aeWETH} from "contracts/tokenbridge/libraries/aeWETH.sol";
import {CreationCodeHelper} from "contracts/tokenbridge/libraries/CreationCodeHelper.sol";
import {UpgradeExecutor} from "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import {ArbMulticall2} from "contracts/rpc-utils/MulticallV2.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "forge-std/console.sol";

contract L2AtomicTokenBridgeFactoryTest is Test {
    L2AtomicTokenBridgeFactory public l2Factory;
    address public deployer = makeAddr("deployer");

    address public router;
    address public standardGateway;
    address public customGateway;
    address public wethGateway;
    address public weth;
    address public upgradeExecutor;
    address public multicall;

    /// 'deployL2Contracts' inputs
    address public l1Router = makeAddr("l1Router");
    address public l1StandardGateway = makeAddr("l1StandardGateway");
    address public l1CustomGateway = makeAddr("l1CustomGateway");
    address public l1WethGateway = makeAddr("l1WethGateway");
    address public l1Weth = makeAddr("l1Weth");
    address public rollupOwner = makeAddr("rollupOwner");
    address public aliasedL1UpgradeExecutor = makeAddr("aliasedL1UpgradeExecutor");

    L2RuntimeCode runtimeCode;

    address private constant ADDRESS_DEAD = address(0x000000000000000000000000000000000000dEaD);

    function setUp() public {
        l2Factory = new L2AtomicTokenBridgeFactory();

        // set templates
        router = address(new L2GatewayRouter());
        standardGateway = address(new L2ERC20Gateway());
        customGateway = address(new L2CustomGateway());
        wethGateway = address(new L2WethGateway());
        weth = address(new aeWETH());
        upgradeExecutor = address(new UpgradeExecutor());
        multicall = address(new ArbMulticall2());

        /// bytecode which is sent via retryable
        runtimeCode = L2RuntimeCode(
            router.code,
            standardGateway.code,
            customGateway.code,
            wethGateway.code,
            weth.code,
            upgradeExecutor.code,
            multicall.code
        );
    }

    /* solhint-disable func-name-mixedcase */
    function test_deployL2Contracts_checkRouter() public {
        _deployL2Contracts();

        address expectedProxyAdminAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2PA"), block.chainid, address(this))),
            keccak256(type(ProxyAdmin).creationCode),
            address(l2Factory)
        );

        address expectedL2ERC20GwAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2SGW"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );

        address expectedL2RouterAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2R"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );
        assertEq(
            L2GatewayRouter(expectedL2RouterAddress).counterpartGateway(),
            l1Router,
            "Wrong l1Router"
        );
        assertEq(
            L2GatewayRouter(expectedL2RouterAddress).defaultGateway(),
            expectedL2ERC20GwAddress,
            "Wrong defaultGateway"
        );

        address expectedL2RouterLogicAddress = Create2.computeAddress(
            bytes32(0),
            keccak256(CreationCodeHelper.getCreationCodeFor(runtimeCode.router)),
            address(l2Factory)
        );
        assertEq(
            L2GatewayRouter(expectedL2RouterLogicAddress).counterpartGateway(),
            ADDRESS_DEAD,
            "Wrong l1Router"
        );
        assertEq(
            L2GatewayRouter(expectedL2RouterLogicAddress).defaultGateway(),
            ADDRESS_DEAD,
            "Wrong defaultGateway"
        );
    }

    function test_deployL2Contracts_checkCustomGateway() public {
        _deployL2Contracts();

        // custom gateway
        address expectedProxyAdminAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2PA"), block.chainid, address(this))),
            keccak256(type(ProxyAdmin).creationCode),
            address(l2Factory)
        );

        address expectedL2CustomGwAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2CGW"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );

        address expectedL2RouterAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2R"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );

        assertEq(
            L2CustomGateway(expectedL2CustomGwAddress).counterpartGateway(),
            l1CustomGateway,
            "Wrong counterpartGateway"
        );
        assertEq(
            L2CustomGateway(expectedL2CustomGwAddress).router(),
            expectedL2RouterAddress,
            "Wrong router"
        );
    }

    function test_deployL2Contracts_revert_AlreadyExists() public {
        _deployL2Contracts();

        vm.expectRevert(
            abi.encodeWithSelector(
                L2AtomicTokenBridgeFactory.L2AtomicTokenBridgeFactory_AlreadyExists.selector
            )
        );
        l2Factory.deployL2Contracts(
            runtimeCode,
            l1Router,
            l1StandardGateway,
            l1CustomGateway,
            l1WethGateway,
            l1Weth,
            makeAddr("l2StandardGatewayCanonicalAddress"),
            rollupOwner,
            aliasedL1UpgradeExecutor
        );
    }

    function _deployL2Contracts() internal {
        address l2StandardGatewayCanonicalAddress;

        /// expected L2 standard gateway address needs to be provided to 'deployL2Contracts' call as well
        address expectedProxyAdminAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2PA"), block.chainid, address(this))),
            keccak256(type(ProxyAdmin).creationCode),
            address(l2Factory)
        );
        address expectedL2ERC20GwAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2SGW"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );
        l2StandardGatewayCanonicalAddress = expectedL2ERC20GwAddress;

        /// do the call
        l2Factory.deployL2Contracts(
            runtimeCode,
            l1Router,
            l1StandardGateway,
            l1CustomGateway,
            l1WethGateway,
            l1Weth,
            l2StandardGatewayCanonicalAddress,
            rollupOwner,
            aliasedL1UpgradeExecutor
        );
    }

    function _computeAddress(bytes32 salt, address proxyAdmin) internal view returns (address) {
        return Create2.computeAddress(
            salt,
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(l2Factory, proxyAdmin, bytes(""))
                )
            ),
            address(l2Factory)
        );
    }
}
