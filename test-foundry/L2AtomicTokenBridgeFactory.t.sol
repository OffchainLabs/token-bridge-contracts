// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {
    L2AtomicTokenBridgeFactory,
    L2RuntimeCode,
    ProxyAdmin,
    BeaconProxyFactory,
    StandardArbERC20,
    UpgradeableBeacon,
    aeWETH
} from "contracts/tokenbridge/arbitrum/L2AtomicTokenBridgeFactory.sol";
import {L2GatewayRouter} from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import {L2ERC20Gateway} from "contracts/tokenbridge/arbitrum/gateway/L2ERC20Gateway.sol";
import {L2CustomGateway} from "contracts/tokenbridge/arbitrum/gateway/L2CustomGateway.sol";
import {L2WethGateway} from "contracts/tokenbridge/arbitrum/gateway/L2WethGateway.sol";
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

    L2RuntimeCode public runtimeCode;

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

        // logic
        address expectedL2RouterLogicAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2R"), block.chainid, address(this))),
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

    function test_deployL2Contracts_checkStandardGateway() public {
        _deployL2Contracts();

        // standard gateway
        address expectedProxyAdminAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2PA"), block.chainid, address(this))),
            keccak256(type(ProxyAdmin).creationCode),
            address(l2Factory)
        );

        address expectedL2StandardGwAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2SGW"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );

        address expectedL2RouterAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2R"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );

        assertEq(
            L2ERC20Gateway(expectedL2StandardGwAddress).counterpartGateway(),
            l1StandardGateway,
            "Wrong counterpartGateway"
        );
        assertEq(
            L2ERC20Gateway(expectedL2StandardGwAddress).router(),
            expectedL2RouterAddress,
            "Wrong router"
        );

        // beacon proxy stuff
        address expectedL2BeaconProxyFactoryAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2BPF"), block.chainid, address(this))),
            keccak256(type(BeaconProxyFactory).creationCode),
            address(l2Factory)
        );
        assertEq(
            L2ERC20Gateway(expectedL2StandardGwAddress).beaconProxyFactory(),
            expectedL2BeaconProxyFactoryAddress,
            "Wrong beaconProxyFactory"
        );
        address expectedStandardArbERC20Address = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2BPF"), block.chainid, address(this))),
            keccak256(type(StandardArbERC20).creationCode),
            address(l2Factory)
        );
        address expectedBeaconAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2BPF"), block.chainid, address(this))),
            keccak256(
                abi.encodePacked(
                    type(UpgradeableBeacon).creationCode,
                    abi.encode(expectedStandardArbERC20Address)
                )
            ),
            address(l2Factory)
        );

        assertEq(
            UpgradeableBeacon(BeaconProxyFactory(expectedL2BeaconProxyFactoryAddress).beacon())
                .implementation(),
            expectedStandardArbERC20Address,
            "Wrong implementation"
        );
        assertEq(
            BeaconProxyFactory(expectedL2BeaconProxyFactoryAddress).beacon(),
            expectedBeaconAddress,
            "Wrong beacon"
        );
        assertEq(
            UpgradeableBeacon(expectedBeaconAddress).implementation(),
            expectedStandardArbERC20Address,
            "Wrong implementation"
        );

        address expectedL2UpgExecutorAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2E"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );
        assertEq(
            UpgradeableBeacon(expectedBeaconAddress).owner(),
            expectedL2UpgExecutorAddress,
            "Wrong beacon owner"
        );

        // logic
        address expectedL2StandardGwLogicAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2SGW"), block.chainid, address(this))),
            keccak256(CreationCodeHelper.getCreationCodeFor(runtimeCode.standardGateway)),
            address(l2Factory)
        );
        assertEq(
            L2ERC20Gateway(expectedL2StandardGwLogicAddress).counterpartGateway(),
            ADDRESS_DEAD,
            "Wrong counterpartGateway"
        );
        assertEq(
            L2ERC20Gateway(expectedL2StandardGwLogicAddress).router(), ADDRESS_DEAD, "Wrong router"
        );
        assertEq(
            L2ERC20Gateway(expectedL2StandardGwLogicAddress).beaconProxyFactory(),
            ADDRESS_DEAD,
            "Wrong beaconProxyFactory"
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

        // logic
        address expectedL2CustomGwLogicAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2CGW"), block.chainid, address(this))),
            keccak256(CreationCodeHelper.getCreationCodeFor(runtimeCode.customGateway)),
            address(l2Factory)
        );
        assertEq(
            L2CustomGateway(expectedL2CustomGwLogicAddress).counterpartGateway(),
            ADDRESS_DEAD,
            "Wrong counterpartGateway"
        );
        assertEq(
            L2CustomGateway(expectedL2CustomGwLogicAddress).router(), ADDRESS_DEAD, "Wrong router"
        );
    }

    function test_deployL2Contracts_checkWethGateway() public {
        _deployL2Contracts();

        // weth gateway
        address expectedProxyAdminAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2PA"), block.chainid, address(this))),
            keccak256(type(ProxyAdmin).creationCode),
            address(l2Factory)
        );

        address expectedL2WethGwAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2WGW"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );

        address expectedL2Weth = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2W"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );

        address expectedL2RouterAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2R"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );

        assertEq(
            L2WethGateway(payable(expectedL2WethGwAddress)).counterpartGateway(),
            l1WethGateway,
            "Wrong counterpartGateway"
        );
        assertEq(
            L2WethGateway(payable(expectedL2WethGwAddress)).router(),
            expectedL2RouterAddress,
            "Wrong router"
        );
        assertEq(L2WethGateway(payable(expectedL2WethGwAddress)).l1Weth(), l1Weth, "Wrong l1Weth");
        assertEq(
            L2WethGateway(payable(expectedL2WethGwAddress)).l2Weth(), expectedL2Weth, "Wrong l2Weth"
        );

        // wethgateway logic
        address expectedL2WethGwLogicAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2WGW"), block.chainid, address(this))),
            keccak256(CreationCodeHelper.getCreationCodeFor(runtimeCode.wethGateway)),
            address(l2Factory)
        );
        assertEq(
            L2WethGateway(payable(expectedL2WethGwLogicAddress)).counterpartGateway(),
            ADDRESS_DEAD,
            "Wrong counterpartGateway"
        );
        assertEq(
            L2WethGateway(payable(expectedL2WethGwLogicAddress)).router(),
            ADDRESS_DEAD,
            "Wrong router"
        );
        assertEq(
            L2WethGateway(payable(expectedL2WethGwLogicAddress)).l1Weth(),
            ADDRESS_DEAD,
            "Wrong l1Weth"
        );
        assertEq(
            L2WethGateway(payable(expectedL2WethGwLogicAddress)).l2Weth(),
            ADDRESS_DEAD,
            "Wrong l2Weth"
        );

        // weth
        aeWETH l2Weth = aeWETH(payable(expectedL2Weth));
        assertEq(l2Weth.name(), "WETH", "Wrong name");
        assertEq(l2Weth.symbol(), "WETH", "Wrong symbol");
        assertEq(l2Weth.decimals(), 18, "Wrong decimals");
        assertEq(l2Weth.l2Gateway(), expectedL2WethGwAddress, "Wrong l2Gateway");
        assertEq(l2Weth.l1Address(), l1Weth, "Wrong l1Weth");

        // weth logic
        address expectedL2WethLogicAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2W"), block.chainid, address(this))),
            keccak256(CreationCodeHelper.getCreationCodeFor(runtimeCode.aeWeth)),
            address(l2Factory)
        );
        aeWETH l2WethLogic = aeWETH(payable(expectedL2WethLogicAddress));
        assertEq(l2WethLogic.name(), "", "Wrong name");
        assertEq(l2WethLogic.symbol(), "", "Wrong symbol");
        assertEq(l2WethLogic.decimals(), 0, "Wrong decimals");
        assertEq(l2WethLogic.l2Gateway(), ADDRESS_DEAD, "Wrong l2Gateway");
        assertEq(l2WethLogic.l1Address(), ADDRESS_DEAD, "Wrong l1Weth");
    }

    function test_deployL2Contracts_checkUpgradeExecutor() public {
        _deployL2Contracts();

        // upgrade executor
        address expectedProxyAdminAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2PA"), block.chainid, address(this))),
            keccak256(type(ProxyAdmin).creationCode),
            address(l2Factory)
        );

        address expectedL2UpgExecutorAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2E"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );

        bytes32 executorRole = UpgradeExecutor(expectedL2UpgExecutorAddress).EXECUTOR_ROLE();
        bytes32 adminRole = UpgradeExecutor(expectedL2UpgExecutorAddress).ADMIN_ROLE();

        assertEq(
            UpgradeExecutor(expectedL2UpgExecutorAddress).hasRole(
                executorRole, aliasedL1UpgradeExecutor
            ),
            true,
            "Wrong executor role"
        );
        assertEq(
            UpgradeExecutor(expectedL2UpgExecutorAddress).hasRole(executorRole, rollupOwner),
            true,
            "Wrong executor role"
        );
        assertEq(
            UpgradeExecutor(expectedL2UpgExecutorAddress).hasRole(
                adminRole, expectedL2UpgExecutorAddress
            ),
            true,
            "Wrong admin role"
        );

        // logic
        address expectedL2UpgExecutorLogicAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2E"), block.chainid, address(this))),
            keccak256(CreationCodeHelper.getCreationCodeFor(runtimeCode.upgradeExecutor)),
            address(l2Factory)
        );
        assertEq(
            UpgradeExecutor(expectedL2UpgExecutorLogicAddress).hasRole(adminRole, ADDRESS_DEAD),
            true,
            "Wrong admin role"
        );
    }

    function test_deployL2Contracts_checkMulticall() public {
        _deployL2Contracts();

        address expectedMulticallAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2MC"), block.chainid, address(this))),
            keccak256(type(ArbMulticall2).creationCode),
            address(l2Factory)
        );

        assertGt(expectedMulticallAddress.code.length, uint256(0), "Multicall code is empty");
    }

    function test_deployL2Contracts_checkProxyAdmin() public {
        _deployL2Contracts();

        address expectedProxyAdminAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L2PA"), block.chainid, address(this))),
            keccak256(type(ProxyAdmin).creationCode),
            address(l2Factory)
        );

        address expectedL2UpgExecutorAddress = _computeAddress(
            keccak256(abi.encodePacked(bytes("L2E"), block.chainid, address(this))),
            expectedProxyAdminAddress
        );

        assertGt(expectedProxyAdminAddress.code.length, uint256(0), "ProxyAdmin code is empty");
        assertEq(
            ProxyAdmin(expectedProxyAdminAddress).owner(),
            expectedL2UpgExecutorAddress,
            "Wrong owner"
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
