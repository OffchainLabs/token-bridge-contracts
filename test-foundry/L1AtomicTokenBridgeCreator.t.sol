// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {
    L1AtomicTokenBridgeCreator,
    L1DeploymentAddresses,
    L2DeploymentAddresses,
    TransparentUpgradeableProxy,
    ProxyAdmin,
    ClonableBeaconProxy,
    BeaconProxyFactory
} from "contracts/tokenbridge/ethereum/L1AtomicTokenBridgeCreator.sol";
import {L1TokenBridgeRetryableSender} from
    "contracts/tokenbridge/ethereum/L1TokenBridgeRetryableSender.sol";
import {TestUtil} from "./util/TestUtil.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";
import {L1GatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import {L1ERC20Gateway} from "contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol";
import {L1CustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol";
import {L1WethGateway} from "contracts/tokenbridge/ethereum/gateway/L1WethGateway.sol";
import {L1OrbitGatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1OrbitGatewayRouter.sol";
import {L1OrbitERC20Gateway} from "contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol";
import {L1OrbitCustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1OrbitCustomGateway.sol";
import {
    IUpgradeExecutor,
    UpgradeExecutor
} from "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import {Inbox, IInboxBase} from "lib/nitro-contracts/src/bridge/Inbox.sol";
import {ERC20Inbox} from "lib/nitro-contracts/src/bridge/ERC20Inbox.sol";
import {IOutbox} from "lib/nitro-contracts/src/bridge/IOutbox.sol";
import {Bridge, IBridge, IOwnable} from "lib/nitro-contracts/src/bridge/Bridge.sol";
import {ERC20Bridge} from "lib/nitro-contracts/src/bridge/ERC20Bridge.sol";
import {
    RollupProxy,
    IRollupUser,
    IOutbox,
    IRollupEventInbox,
    IChallengeManager
} from "lib/nitro-contracts/src/rollup/RollupProxy.sol";
import {RollupAdminLogic} from "lib/nitro-contracts/src/rollup/RollupAdminLogic.sol";
import {RollupUserLogic} from "lib/nitro-contracts/src/rollup/RollupUserLogic.sol";
import {Config, ContractDependencies} from "lib/nitro-contracts/src/rollup/Config.sol";
import {ISequencerInbox} from "lib/nitro-contracts/src/bridge/ISequencerInbox.sol";
import {ERC20PresetMinterPauser} from
    "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract L1AtomicTokenBridgeCreatorTest is Test {
    L1AtomicTokenBridgeCreator public l1Creator;
    address public deployer = makeAddr("deployer");

    function setUp() public {
        l1Creator = L1AtomicTokenBridgeCreator(
            TestUtil.deployProxy(address(new L1AtomicTokenBridgeCreator()))
        );
        L1TokenBridgeRetryableSender sender = L1TokenBridgeRetryableSender(
            TestUtil.deployProxy(address(new L1TokenBridgeRetryableSender()))
        );

        vm.deal(deployer, 10 ether);
        vm.prank(deployer);
        l1Creator.initialize(sender);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public {
        L1AtomicTokenBridgeCreator _creator = L1AtomicTokenBridgeCreator(
            TestUtil.deployProxy(address(new L1AtomicTokenBridgeCreator()))
        );
        L1TokenBridgeRetryableSender _sender = L1TokenBridgeRetryableSender(
            TestUtil.deployProxy(address(new L1TokenBridgeRetryableSender()))
        );

        vm.prank(deployer);
        _creator.initialize(_sender);

        assertEq(_creator.owner(), deployer, "Wrong owner");
        assertEq(address(_creator.retryableSender()), address(_sender), "Wrong sender");
        assertEq(uint256(vm.load(address(_sender), 0)), 1, "Wrong init state");

        address exepectedL2Factory = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xd6),
                            bytes1(0x94),
                            AddressAliasHelper.applyL1ToL2Alias(address(_creator)),
                            bytes1(0x80)
                        )
                    )
                )
            )
        );
        assertEq(
            address(_creator.canonicalL2FactoryAddress()),
            exepectedL2Factory,
            "Wrong canonicalL2FactoryAddress"
        );
    }

    function test_initialize_revert_AlreadyInit() public {
        L1AtomicTokenBridgeCreator _creator = L1AtomicTokenBridgeCreator(
            TestUtil.deployProxy(address(new L1AtomicTokenBridgeCreator()))
        );
        L1TokenBridgeRetryableSender _sender = new L1TokenBridgeRetryableSender();
        _creator.initialize(_sender);

        vm.expectRevert("Initializable: contract is already initialized");
        _creator.initialize(_sender);
    }

    function test_initialize_revert_CantInitLogic() public {
        L1AtomicTokenBridgeCreator _creator = new L1AtomicTokenBridgeCreator();

        vm.expectRevert("Initializable: contract is already initialized");
        _creator.initialize(L1TokenBridgeRetryableSender(address(100)));
    }

    function test_createTokenBridge_checkL1Router() public {
        // prepare
        _setTemplates();
        (RollupProxy rollup, Inbox inbox, ProxyAdmin pa, UpgradeExecutor upgExecutor) =
            _createRollup();
        _createTokenBridge(rollup, inbox, upgExecutor);

        /// check state
        (address l1RouterAddress, address standardGatewayAddress,,,) =
            l1Creator.inboxToL1Deployment(address(inbox));

        (L1GatewayRouter routerTemplate,,,,,,,) = l1Creator.l1Templates();

        address expectedL1RouterAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L1R"), address(inbox))),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(address(routerTemplate), pa, bytes(""))
                )
            ),
            address(l1Creator)
        );
        assertEq(l1RouterAddress, expectedL1RouterAddress, "Wrong l1Router address");
        assertTrue(l1RouterAddress.code.length > 0, "Wrong l1Router code");

        L1GatewayRouter l1Router = L1GatewayRouter(l1RouterAddress);
        assertEq(l1Router.owner(), address(upgExecutor), "Wrong l1Router owner");
        assertEq(l1Router.defaultGateway(), standardGatewayAddress, "Wrong l1Router defaultGateway");
        assertEq(l1Router.whitelist(), address(0), "Wrong l1Router whitelist");

        (address l2Router,,,,,,,,) = l1Creator.inboxToL2Deployment(address(inbox));
        assertEq(l1Router.counterpartGateway(), l2Router, "Wrong l1Router counterpartGateway");
        assertEq(l1Router.inbox(), address(inbox), "Wrong l1Router inbox");
    }

    function test_createTokenBridge_checkL1StandardGateway() public {
        // prepare
        _setTemplates();
        (RollupProxy rollup, Inbox inbox, ProxyAdmin pa, UpgradeExecutor upgExecutor) =
            _createRollup();
        _createTokenBridge(rollup, inbox, upgExecutor);

        /// check state
        (address l1RouterAddress, address l1StandardGatewayAddress,,,) =
            l1Creator.inboxToL1Deployment(address(inbox));

        (, L1ERC20Gateway standardGatewayTemplate,,,,,,) = l1Creator.l1Templates();

        address expectedL1StandardGatewayAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L1SGW"), address(inbox))),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(address(standardGatewayTemplate), pa, bytes(""))
                )
            ),
            address(l1Creator)
        );
        assertEq(
            l1StandardGatewayAddress,
            expectedL1StandardGatewayAddress,
            "Wrong l1StandardGateway address"
        );
        assertTrue(l1StandardGatewayAddress.code.length > 0, "Wrong l1StandardGateway code");

        L1ERC20Gateway l1StandardGateway = L1ERC20Gateway(l1StandardGatewayAddress);
        (, address l2StandardGateway,,,,,,,) = l1Creator.inboxToL2Deployment(address(inbox));
        assertEq(
            l1StandardGateway.counterpartGateway(),
            l2StandardGateway,
            "Wrong l1StandardGateway counterpartGateway"
        );
        assertEq(l1StandardGateway.router(), l1RouterAddress, "Wrong l1StandardGateway router");
        assertEq(l1StandardGateway.inbox(), address(inbox), "Wrong l1StandardGateway inbox");
        assertEq(
            l1StandardGateway.cloneableProxyHash(),
            keccak256(type(ClonableBeaconProxy).creationCode),
            "Wrong l1StandardGateway cloneableProxyHash"
        );

        address expectedL2BeaconProxyFactoryAddress = Create2.computeAddress(
            keccak256(
                abi.encodePacked(
                    bytes("L2BPF"),
                    uint256(2000),
                    AddressAliasHelper.applyL1ToL2Alias(address(l1Creator.retryableSender()))
                )
            ),
            keccak256(type(BeaconProxyFactory).creationCode),
            l1Creator.canonicalL2FactoryAddress()
        );
        assertEq(
            l1StandardGateway.l2BeaconProxyFactory(),
            expectedL2BeaconProxyFactoryAddress,
            "Wrong l1StandardGateway l2BeaconProxyFactory"
        );
    }

    function test_createTokenBridge_checkL1CustomGateway() public {
        // prepare
        _setTemplates();
        (RollupProxy rollup, Inbox inbox, ProxyAdmin pa, UpgradeExecutor upgExecutor) =
            _createRollup();
        _createTokenBridge(rollup, inbox, upgExecutor);

        /// check state
        (address l1RouterAddress,, address l1CustomGatewayAddress,,) =
            l1Creator.inboxToL1Deployment(address(inbox));

        (,, L1CustomGateway customGatewayTemplate,,,,,) = l1Creator.l1Templates();

        address expectedL1CustomGatewayAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L1CGW"), address(inbox))),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(address(customGatewayTemplate), pa, bytes(""))
                )
            ),
            address(l1Creator)
        );
        assertEq(
            l1CustomGatewayAddress,
            expectedL1CustomGatewayAddress,
            "Wrong l1StandardGateway address"
        );
        assertTrue(l1CustomGatewayAddress.code.length > 0, "Wrong l1CustomGatewayAddress code");

        L1CustomGateway l1CustomGateway = L1CustomGateway(l1CustomGatewayAddress);
        (,, address l2CustomGateway,,,,,,) = l1Creator.inboxToL2Deployment(address(inbox));
        assertEq(
            l1CustomGateway.counterpartGateway(),
            l2CustomGateway,
            "Wrong l1CustomGateway counterpartGateway"
        );
        assertEq(l1CustomGateway.router(), l1RouterAddress, "Wrong l1CustomGateway router");
        assertEq(l1CustomGateway.inbox(), address(inbox), "Wrong l1CustomGateway inbox");
        assertEq(l1CustomGateway.owner(), address(upgExecutor), "Wrong l1CustomGateway owner");
    }

    function test_createTokenBridge_checkL1WethGateway() public {
        // prepare
        _setTemplates();
        (RollupProxy rollup, Inbox inbox, ProxyAdmin pa, UpgradeExecutor upgExecutor) =
            _createRollup();
        _createTokenBridge(rollup, inbox, upgExecutor);

        /// check state
        (address l1RouterAddress,,, address l1WethGatewayAddress,) =
            l1Creator.inboxToL1Deployment(address(inbox));

        (,,, L1WethGateway wethGatewayTemplate,,,,) = l1Creator.l1Templates();

        address expectedL1WethGatewayAddress = Create2.computeAddress(
            keccak256(abi.encodePacked(bytes("L1WGW"), address(inbox))),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(address(wethGatewayTemplate), pa, bytes(""))
                )
            ),
            address(l1Creator)
        );
        assertEq(l1WethGatewayAddress, expectedL1WethGatewayAddress, "Wrong l1WethGatewayAddresss");
        assertTrue(l1WethGatewayAddress.code.length > 0, "Wrong l1WethGatewayAddress code");

        L1WethGateway l1WethGateway = L1WethGateway(payable(l1WethGatewayAddress));
        (,,, address l2WethGateway, address l2Weth,,,,) =
            l1Creator.inboxToL2Deployment(address(inbox));
        assertEq(
            l1WethGateway.counterpartGateway(),
            l2WethGateway,
            "Wrong l1WethGateway counterpartGateway"
        );
        assertEq(l1WethGateway.router(), l1RouterAddress, "Wrong l1WethGateway router");
        assertEq(l1WethGateway.inbox(), address(inbox), "Wrong l1WethGateway inbox");
        assertEq(l1WethGateway.l1Weth(), l1Creator.l1Weth(), "Wrong l1WethGateway l1Weth");
        assertEq(l1WethGateway.l2Weth(), l2Weth, "Wrong l1WethGateway l2Weth");
    }

    function test_createTokenBridge_DeployerIsRefunded() public {
        // prepare
        _setTemplates();
        (RollupProxy rollup, Inbox inbox, ProxyAdmin pa, UpgradeExecutor upgExecutor) =
            _createRollup();

        uint256 deployerBalanceBefore = deployer.balance;

        _createTokenBridge(rollup, inbox, upgExecutor);

        uint256 deployerBalanceAfter = deployer.balance;

        assertGt(deployerBalanceAfter, deployerBalanceBefore - 1 ether, "Refund not received");
    }

    function test_createTokenBridge_ERC20Chain() public {
        // prepare
        _setTemplates();
        (RollupProxy rollup, ERC20Inbox inbox,, UpgradeExecutor upgExecutor, ERC20 nativeToken) =
            _createERC20Rollup();

        {
            // mock owner() => upgExecutor
            vm.mockCall(
                address(rollup),
                abi.encodeWithSignature("owner()"),
                abi.encode(address(upgExecutor))
            );

            // mock rollupOwner is executor on upgExecutor
            vm.mockCall(
                address(upgExecutor),
                abi.encodeWithSignature(
                    "hasRole(bytes32,address)", upgExecutor.EXECUTOR_ROLE(), deployer
                ),
                abi.encode(true)
            );

            // mock chain id
            uint256 mockChainId = 2000;
            vm.mockCall(
                address(rollup), abi.encodeWithSignature("chainId()"), abi.encode(mockChainId)
            );
        }

        /// do it
        vm.deal(deployer, 1 ether);
        vm.startPrank(deployer);
        nativeToken.approve(address(l1Creator), 10 ether);
        l1Creator.createTokenBridge(address(inbox), deployer, 100, 200);

        /// check state
        {
            (
                address l1Router,
                address l1StandardGateway,
                address l1CustomGateway,
                address l1WethGateway,
                address l1Weth
            ) = l1Creator.inboxToL1Deployment(address(inbox));
            assertTrue(l1Router != address(0), "Wrong l1Router");
            assertTrue(l1StandardGateway != address(0), "Wrong l1StandardGateway");
            assertTrue(l1CustomGateway != address(0), "Wrong l1CustomGateway");
            assertTrue(l1WethGateway == address(0), "Wrong l1WethGateway");
            assertTrue(l1Weth == address(0), "Wrong l1Weth");
        }

        {
            (
                address l2Router,
                address l2StandardGateway,
                address l2CustomGateway,
                address l2WethGateway,
                address l2Weth,
                address l2ProxyAdmin,
                address l2BeaconProxyFactory,
                address l2UpgradeExecutor,
                address l2Multicall
            ) = l1Creator.inboxToL2Deployment(address(inbox));
            assertTrue(l2Router != address(0), "Wrong l2Router");
            assertTrue(l2StandardGateway != address(0), "Wrong l2StandardGateway");
            assertTrue(l2CustomGateway != address(0), "Wrong l2CustomGateway");
            assertTrue(l2WethGateway == address(0), "Wrong l2WethGateway");
            assertTrue(l2Weth == address(0), "Wrong l2Weth");
            assertTrue(l2ProxyAdmin != address(0), "Wrong l2ProxyAdmin");
            assertTrue(l2BeaconProxyFactory != address(0), "Wrong l2BeaconProxyFactory");
            assertTrue(l2UpgradeExecutor != address(0), "Wrong l2UpgradeExecutor");
            assertTrue(l2Multicall != address(0), "Wrong l2Multicall");
        }
    }

    function test_createTokenBridge_revert_TemplatesNotSet() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                L1AtomicTokenBridgeCreator.L1AtomicTokenBridgeCreator_TemplatesNotSet.selector
            )
        );
        l1Creator.createTokenBridge(address(100), address(101), 100, 200);
    }

    function test_createTokenBridge_revert_RollupOwnershipMisconfig() public {
        // prepare
        _setTemplates();
        (RollupProxy rollup, Inbox inbox,, UpgradeExecutor upgExecutor) = _createRollup();

        // mock owner() => upgExecutor
        vm.mockCall(
            address(rollup), abi.encodeWithSignature("owner()"), abi.encode(address(upgExecutor))
        );

        // expect revert when creating bridge
        vm.expectRevert(
            abi.encodeWithSelector(
                L1AtomicTokenBridgeCreator
                    .L1AtomicTokenBridgeCreator_RollupOwnershipMisconfig
                    .selector
            )
        );
        l1Creator.createTokenBridge(address(inbox), deployer, 100, 200);
    }

    function test_getRouter_NonExistent() public {
        assertEq(l1Creator.getRouter(makeAddr("non-existent")), address(0), "Should be empty");
    }

    function test_getRouter() public {
        // prepare
        _setTemplates();
        (RollupProxy rollup, Inbox inbox,, UpgradeExecutor upgExecutor) = _createRollup();

        {
            // mock owner() => upgExecutor
            vm.mockCall(
                address(rollup),
                abi.encodeWithSignature("owner()"),
                abi.encode(address(upgExecutor))
            );

            // mock rollupOwner is executor on upgExecutor
            vm.mockCall(
                address(upgExecutor),
                abi.encodeWithSignature(
                    "hasRole(bytes32,address)", upgExecutor.EXECUTOR_ROLE(), deployer
                ),
                abi.encode(true)
            );

            // mock chain id
            uint256 mockChainId = 2000;
            vm.mockCall(
                address(rollup), abi.encodeWithSignature("chainId()"), abi.encode(mockChainId)
            );
        }

        /// do it
        vm.deal(deployer, 10 ether);
        vm.prank(deployer);
        l1Creator.createTokenBridge{value: 1 ether}(address(inbox), deployer, 100, 200);

        /// state check
        (address expectedRouter,,,,) = l1Creator.inboxToL1Deployment(address(inbox));
        assertEq(l1Creator.getRouter(address(inbox)), expectedRouter, "Wrong router");
    }

    function test_setDeployment() public {
        (RollupProxy rollup, Inbox inbox,, UpgradeExecutor upgExecutor) = _createRollup();

        // mock owner() => upgExecutor
        vm.mockCall(
            address(rollup), abi.encodeWithSignature("owner()"), abi.encode(address(upgExecutor))
        );

        L1DeploymentAddresses memory l1 = L1DeploymentAddresses(
            makeAddr("l1Router"),
            makeAddr("l1StandardGateway"),
            makeAddr("l1CustomGateway"),
            makeAddr("l1WethGateway"),
            makeAddr("l1Weth")
        );

        L2DeploymentAddresses memory l2 = L2DeploymentAddresses(
            makeAddr("l2Router"),
            makeAddr("l2StandardGateway"),
            makeAddr("l2CustomGateway"),
            makeAddr("l2WethGateway"),
            makeAddr("l2Weth"),
            makeAddr("l2ProxyAdmin"),
            makeAddr("l2BeaconProxyFactory"),
            makeAddr("l2UpgradeExecutor"),
            makeAddr("l2Multicall")
        );

        /// expect event
        vm.expectEmit(true, true, true, true);
        emit OrbitTokenBridgeDeploymentSet(address(inbox), l1, l2);

        /// do it
        vm.prank(address(upgExecutor));
        l1Creator.setDeployment(address(inbox), l1, l2);

        /// check state
        {
            (
                address l1Router,
                address l1StandardGateway,
                address l1CustomGateway,
                address l1WethGateway,
                address l1Weth
            ) = l1Creator.inboxToL1Deployment(address(inbox));
            assertEq(l1Router, l1.router, "Wrong l1Router");
            assertEq(l1StandardGateway, l1.standardGateway, "Wrong l1StandardGateway");
            assertEq(l1CustomGateway, l1.customGateway, "Wrong l1CustomGateway");
            assertEq(l1WethGateway, l1.wethGateway, "Wrong l1WethGateway");
            assertEq(l1Weth, l1.weth, "Wrong l1Weth");
        }

        {
            (
                address l2Router,
                address l2StandardGateway,
                address l2CustomGateway,
                address l2WethGateway,
                address l2Weth,
                address l2ProxyAdmin,
                address l2BeaconProxyFactory,
                address l2UpgradeExecutor,
                address l2Multicall
            ) = l1Creator.inboxToL2Deployment(address(inbox));
            assertEq(l2Router, l2.router, "Wrong l2Router");
            assertEq(l2StandardGateway, l2.standardGateway, "Wrong l2StandardGateway");
            assertEq(l2CustomGateway, l2.customGateway, "Wrong l2CustomGateway");
            assertEq(l2WethGateway, l2.wethGateway, "Wrong l2WethGateway");
            assertEq(l2Weth, l2.weth, "Wrong l2Weth");
            assertEq(l2ProxyAdmin, l2.proxyAdmin, "Wrong l2ProxyAdmin");
            assertEq(l2Weth, l2.weth, "Wrong l2Weth");
            assertEq(l2BeaconProxyFactory, l2.beaconProxyFactory, "Wrong l2BeaconProxyFactory");
            assertEq(l2UpgradeExecutor, l2.upgradeExecutor, "Wrong l2UpgradeExecutor");
            assertEq(l2Multicall, l2.multicall, "Wrong l2Multicall");
        }
    }

    function test_setDeployment_revert_OnlyRollupOwner() public {
        (RollupProxy rollup, Inbox inbox,, UpgradeExecutor upgExecutor) = _createRollup();

        // mock owner() => upgExecutor
        vm.mockCall(
            address(rollup), abi.encodeWithSignature("owner()"), abi.encode(address(upgExecutor))
        );

        L1DeploymentAddresses memory l1 = L1DeploymentAddresses(
            makeAddr("l1Router"),
            makeAddr("l1StandardGateway"),
            makeAddr("l1CustomGateway"),
            makeAddr("l1WethGateway"),
            makeAddr("l1Weth")
        );

        L2DeploymentAddresses memory l2 = L2DeploymentAddresses(
            makeAddr("l2Router"),
            makeAddr("l2StandardGateway"),
            makeAddr("l2CustomGateway"),
            makeAddr("l2WethGateway"),
            makeAddr("l2Weth"),
            makeAddr("l2ProxyAdmin"),
            makeAddr("l2BeaconProxyFactory"),
            makeAddr("l2UpgradeExecutor"),
            makeAddr("l2Multicall")
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                L1AtomicTokenBridgeCreator.L1AtomicTokenBridgeCreator_OnlyRollupOwner.selector
            )
        );
        l1Creator.setDeployment(address(inbox), l1, l2);
    }

    function test_setTemplates() public {
        L1AtomicTokenBridgeCreator.L1Templates memory _l1Templates = L1AtomicTokenBridgeCreator
            .L1Templates(
            new L1GatewayRouter(),
            new L1ERC20Gateway(),
            new L1CustomGateway(),
            new L1WethGateway(),
            new L1OrbitGatewayRouter(),
            new L1OrbitERC20Gateway(),
            new L1OrbitCustomGateway(),
            new UpgradeExecutor()
        );

        vm.expectEmit(true, true, true, true);
        emit OrbitTokenBridgeTemplatesUpdated();

        vm.prank(deployer);
        l1Creator.setTemplates(
            _l1Templates,
            makeAddr("_l2TokenBridgeFactoryTemplate"),
            makeAddr("_l2RouterTemplate"),
            makeAddr("_l2StandardGatewayTemplate"),
            makeAddr("_l2CustomGatewayTemplate"),
            makeAddr("_l2WethGatewayTemplate"),
            makeAddr("_l2WethTemplate"),
            makeAddr("_l2MulticallTemplate"),
            makeAddr("_l1Weth"),
            makeAddr("_l1Multicall"),
            1000
        );

        (
            L1GatewayRouter router,
            L1ERC20Gateway gw,
            L1CustomGateway customGw,
            L1WethGateway wGw,
            L1OrbitGatewayRouter oRouter,
            L1OrbitERC20Gateway oGw,
            L1OrbitCustomGateway oCustomGw,
            IUpgradeExecutor executor
        ) = l1Creator.l1Templates();
        assertEq(address(router), address(_l1Templates.routerTemplate), "Wrong templates");
        assertEq(address(gw), address(_l1Templates.standardGatewayTemplate), "Wrong templates");
        assertEq(address(customGw), address(_l1Templates.customGatewayTemplate), "Wrong templates");
        assertEq(address(wGw), address(_l1Templates.wethGatewayTemplate), "Wrong templates");
        assertEq(address(oRouter), address(_l1Templates.feeTokenBasedRouterTemplate), "Wrong temp");
        assertEq(
            address(oGw), address(_l1Templates.feeTokenBasedStandardGatewayTemplate), "Wrong gw"
        );
        assertEq(
            address(oCustomGw), address(_l1Templates.feeTokenBasedCustomGatewayTemplate), "Wrong gw"
        );
        assertEq(address(executor), address(_l1Templates.upgradeExecutor), "Wrong executor");

        assertEq(
            l1Creator.l2TokenBridgeFactoryTemplate(),
            makeAddr("_l2TokenBridgeFactoryTemplate"),
            "Wrong ref"
        );
        assertEq(l1Creator.l2RouterTemplate(), makeAddr("_l2RouterTemplate"), "Wrong ref");
        assertEq(
            l1Creator.l2StandardGatewayTemplate(),
            makeAddr("_l2StandardGatewayTemplate"),
            "Wrong ref"
        );
        assertEq(
            l1Creator.l2CustomGatewayTemplate(), makeAddr("_l2CustomGatewayTemplate"), "Wrong ref"
        );
        assertEq(l1Creator.l2WethGatewayTemplate(), makeAddr("_l2WethGatewayTemplate"), "Wrong ref");
        assertEq(l1Creator.l2WethTemplate(), makeAddr("_l2WethTemplate"), "Wrong ref");
        assertEq(l1Creator.l2MulticallTemplate(), makeAddr("_l2MulticallTemplate"), "Wrong ref");
        assertEq(l1Creator.l1Weth(), makeAddr("_l1Weth"), "Wrong ref");
        assertEq(l1Creator.l1Multicall(), makeAddr("_l1Multicall"), "Wrong ref");
        assertEq(l1Creator.gasLimitForL2FactoryDeployment(), 1000, "Wrong ref");
    }

    function test_setTemplates_revert_OnlyOwner() public {
        L1AtomicTokenBridgeCreator.L1Templates memory _l1Templates = L1AtomicTokenBridgeCreator
            .L1Templates(
            new L1GatewayRouter(),
            new L1ERC20Gateway(),
            new L1CustomGateway(),
            new L1WethGateway(),
            new L1OrbitGatewayRouter(),
            new L1OrbitERC20Gateway(),
            new L1OrbitCustomGateway(),
            new UpgradeExecutor()
        );

        vm.expectRevert("Ownable: caller is not the owner");
        l1Creator.setTemplates(
            _l1Templates,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            1000
        );
    }

    function test_setTemplates_revert_L2FactoryCannotBeChanged() public {
        L1AtomicTokenBridgeCreator.L1Templates memory _l1Templates = L1AtomicTokenBridgeCreator
            .L1Templates(
            new L1GatewayRouter(),
            new L1ERC20Gateway(),
            new L1CustomGateway(),
            new L1WethGateway(),
            new L1OrbitGatewayRouter(),
            new L1OrbitERC20Gateway(),
            new L1OrbitCustomGateway(),
            new UpgradeExecutor()
        );

        address originalL2Factory = makeAddr("originalL2Factory");

        vm.prank(deployer);
        l1Creator.setTemplates(
            _l1Templates,
            originalL2Factory,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            1000
        );

        address newL2FactoryTemplate = makeAddr("newL2FactoryTemplate");
        vm.expectRevert(
            abi.encodeWithSelector(
                L1AtomicTokenBridgeCreator
                    .L1AtomicTokenBridgeCreator_L2FactoryCannotBeChanged
                    .selector
            )
        );
        vm.prank(deployer);
        l1Creator.setTemplates(
            _l1Templates,
            newL2FactoryTemplate,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            1000
        );
    }

    function _createRollup()
        internal
        returns (RollupProxy rollup, Inbox inbox, ProxyAdmin pa, UpgradeExecutor upgExecutor)
    {
        pa = new ProxyAdmin();
        rollup = new RollupProxy();
        upgExecutor = new UpgradeExecutor();

        Bridge bridge =
            Bridge(address(new TransparentUpgradeableProxy(address(new Bridge()), address(pa), "")));
        inbox = Inbox(
            address(new TransparentUpgradeableProxy(address(new Inbox(104_857)), address(pa), ""))
        );

        inbox.initialize(IBridge(address(bridge)), ISequencerInbox(makeAddr("sequencerInbox")));
        bridge.initialize(IOwnable(address(rollup)));

        vm.mockCall(address(rollup), abi.encodeWithSignature("owner()"), abi.encode(address(this)));
        bridge.setDelayedInbox(address(inbox), true);
    }

    function _createERC20Rollup()
        internal
        returns (
            RollupProxy rollup,
            ERC20Inbox inbox,
            ProxyAdmin pa,
            UpgradeExecutor upgExecutor,
            ERC20 nativeToken
        )
    {
        pa = new ProxyAdmin();
        rollup = new RollupProxy();
        upgExecutor = new UpgradeExecutor();

        ERC20Bridge bridge = ERC20Bridge(
            address(new TransparentUpgradeableProxy(address(new ERC20Bridge()), address(pa), ""))
        );
        inbox = ERC20Inbox(
            address(
                new TransparentUpgradeableProxy(address(new ERC20Inbox(104_857)), address(pa), "")
            )
        );

        nativeToken = ERC20(address(new ERC20PresetMinterPauser("X", "Y")));
        ERC20PresetMinterPauser(address(nativeToken)).mint(deployer, 10 ether);

        bridge.initialize(IOwnable(address(rollup)), address(nativeToken));
        inbox.initialize(IBridge(address(bridge)), ISequencerInbox(makeAddr("sequencerInbox")));

        vm.mockCall(address(rollup), abi.encodeWithSignature("owner()"), abi.encode(address(this)));
        bridge.setDelayedInbox(address(inbox), true);
    }

    function _createTokenBridge(RollupProxy rollup, Inbox inbox, UpgradeExecutor upgExecutor)
        internal
    {
        // mock owner() => upgExecutor
        vm.mockCall(
            address(rollup), abi.encodeWithSignature("owner()"), abi.encode(address(upgExecutor))
        );

        // mock rollupOwner is executor on upgExecutor
        vm.mockCall(
            address(upgExecutor),
            abi.encodeWithSignature(
                "hasRole(bytes32,address)", upgExecutor.EXECUTOR_ROLE(), deployer
            ),
            abi.encode(true)
        );

        // mock chain id
        uint256 mockChainId = 2000;
        vm.mockCall(address(rollup), abi.encodeWithSignature("chainId()"), abi.encode(mockChainId));

        // create token bridge
        vm.prank(deployer);
        l1Creator.createTokenBridge{value: 1 ether}(address(inbox), deployer, 100, 200);
    }

    function _setTemplates() internal {
        L1AtomicTokenBridgeCreator.L1Templates memory _l1Templates = L1AtomicTokenBridgeCreator
            .L1Templates(
            new L1GatewayRouter(),
            new L1ERC20Gateway(),
            new L1CustomGateway(),
            new L1WethGateway(),
            new L1OrbitGatewayRouter(),
            new L1OrbitERC20Gateway(),
            new L1OrbitCustomGateway(),
            new UpgradeExecutor()
        );

        vm.prank(deployer);
        l1Creator.setTemplates(
            _l1Templates,
            makeAddr("_l2TokenBridgeFactoryTemplate"),
            makeAddr("_l2RouterTemplate"),
            makeAddr("_l2StandardGatewayTemplate"),
            makeAddr("_l2CustomGatewayTemplate"),
            makeAddr("_l2WethGatewayTemplate"),
            makeAddr("_l2WethTemplate"),
            makeAddr("_l2MulticallTemplate"),
            makeAddr("_l1Weth"),
            makeAddr("_l1Multicall"),
            1000
        );
    }

    ////
    // Event declarations
    ////
    event OrbitTokenBridgeCreated(
        address indexed inbox,
        address indexed owner,
        L1DeploymentAddresses l1Deployment,
        L2DeploymentAddresses l2Deployment,
        address proxyAdmin,
        address upgradeExecutor
    );
    event OrbitTokenBridgeTemplatesUpdated();
    event OrbitTokenBridgeDeploymentSet(
        address indexed inbox, L1DeploymentAddresses l1, L2DeploymentAddresses l2
    );
}
