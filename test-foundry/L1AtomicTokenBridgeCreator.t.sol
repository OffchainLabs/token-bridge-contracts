// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "contracts/tokenbridge/ethereum/L1AtomicTokenBridgeCreator.sol";
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
