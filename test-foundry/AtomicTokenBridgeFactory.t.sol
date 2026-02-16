// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../contracts/tokenbridge/ethereum/L1AtomicTokenBridgeCreator.sol";
import "../contracts/tokenbridge/arbitrum/L2AtomicTokenBridgeFactory.sol";
import "../contracts/tokenbridge/libraries/AddressAliasHelper.sol";
import {L1ERC20Gateway} from "../contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol";
import {L1CustomGateway} from "../contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol";
import {L1WethGateway} from "../contracts/tokenbridge/ethereum/gateway/L1WethGateway.sol";
import {
    L1OrbitERC20Gateway
} from "../contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol";
import {
    L1OrbitCustomGateway
} from "../contracts/tokenbridge/ethereum/gateway/L1OrbitCustomGateway.sol";
import {L1YbbERC20Gateway} from "../contracts/tokenbridge/ethereum/gateway/L1YbbERC20Gateway.sol";
import {L1YbbCustomGateway} from "../contracts/tokenbridge/ethereum/gateway/L1YbbCustomGateway.sol";
import {MasterVaultFactory} from "../contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {MasterVault} from "../contracts/tokenbridge/libraries/vault/MasterVault.sol";

import {
    L1TokenBridgeRetryableSender
} from "../contracts/tokenbridge/ethereum/L1TokenBridgeRetryableSender.sol";
import {TestWETH9} from "../contracts/tokenbridge/test/TestWETH9.sol";
import {Multicall2} from "../contracts/rpc-utils/MulticallV2.sol";

import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// // Check that the rollupOwner account has EXECUTOR role
// // on the upgrade executor which is the owner of the rollup
// address upgradeExecutor = IInbox(inbox).bridge().rollup().owner();
// if (
//     !IAccessControlUpgradeable(upgradeExecutor).hasRole(
//         UpgradeExecutor(upgradeExecutor).EXECUTOR_ROLE(), rollupOwner
//     )
// ) {
//     revert L1AtomicTokenBridgeCreator_RollupOwnershipMisconfig();
// }

/// @dev This inbox mock is used to bypass sanity checks in the L1AtomicTokenBridgeCreator
contract MockInbox is Test {
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    address public constant nativeToken = address(0);
    uint256 public immutable chainId;
    uint256 public mode;

    constructor(uint256 _mode) {
        chainId = block.chainid;
        mode = _mode;
    }

    function setMode(uint256 _mode) external {
        mode = _mode;
    }

    function bridge() external view returns (address) {
        return address(this);
    }

    function rollup() external view returns (address) {
        return address(this);
    }

    function owner() external view returns (address) {
        return address(this);
    }

    function hasRole(bytes32, address) external view returns (bool) {
        return true;
    }

    function getProxyAdmin() external view returns (address) {
        return address(this);
    }

    function calculateRetryableSubmissionFee(uint256, uint256) external view returns (uint256) {
        return 0;
    }

    function createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256,
        address,
        address,
        uint256,
        uint256 maxFeePerGas,
        bytes memory data
    ) external payable returns (uint256) {
        if (mode == 1) {
            // mode 1: frontrun the call
            if (to != address(0)) {
                (bool success,) = to.call{value: l2CallValue}(data);
                if (!success) {
                    revert("frontrun failed");
                }
            }
        }
        vm.startPrank(AddressAliasHelper.applyL1ToL2Alias(msg.sender));
        if (to == address(0)) {
            if (mode == 2) {
                // mode 2: fail the deployment
                vm.stopPrank();
                return 0;
            }
            address addr;
            assembly {
                addr := create(0, add(data, 0x20), mload(data))
                if iszero(extcodesize(addr)) { revert(0, 0) }
            }
        } else {
            (bool success,) = to.call{value: l2CallValue}(data);
            if (!success) {
                revert();
            }
        }
        vm.stopPrank();
    }
}

contract AtomicTokenBridgeCreatorTest is Test {
    L1AtomicTokenBridgeCreator.L1Templates public l1Templates;

    address public l2TokenBridgeFactoryTemplate;
    address public l2RouterTemplate;
    address public l2StandardGatewayTemplate;
    address public l2CustomGatewayTemplate;
    address public l2WethGatewayTemplate;
    address public l2WethTemplate;
    address public l2MulticallTemplate;

    address public l1Weth;
    address public l1MultiCall;

    L1AtomicTokenBridgeCreator public factory;

    uint256 public constant MAX_DEPLOYMENT_GAS = 30 * 1024 * 16; // 30 bytes, 16 gas per byte
    address public constant PROXY_ADMIN = address(111);

    receive() external payable {}

    function setUp() public {
        l1Templates = L1AtomicTokenBridgeCreator.L1Templates(
            L1GatewayRouter(address(new L1GatewayRouter())),
            address(new L1ERC20Gateway()),
            address(new L1CustomGateway()),
            address(new L1WethGateway()),
            L1OrbitGatewayRouter(address(new L1OrbitGatewayRouter())),
            address(new L1OrbitERC20Gateway()),
            address(new L1OrbitCustomGateway()),
            IUpgradeExecutor(address(new UpgradeExecutor())),
            address(new L1YbbERC20Gateway()),
            address(new L1YbbCustomGateway()),
            address(new MasterVaultFactory()),
            address(new MasterVault())
        );
        l2TokenBridgeFactoryTemplate = address(new L2AtomicTokenBridgeFactory());
        l2RouterTemplate = address(new L2GatewayRouter());
        l2StandardGatewayTemplate = address(new L2ERC20Gateway());
        l2CustomGatewayTemplate = address(new L2CustomGateway());
        l2WethGatewayTemplate = address(new L2WethGateway());
        l2WethTemplate = address(new aeWETH());
        l2MulticallTemplate = address(new ArbMulticall2());

        l1Weth = address(new TestWETH9("wethl1", "wl1"));
        l1MultiCall = address(new Multicall2());

        L1TokenBridgeRetryableSender sender = new L1TokenBridgeRetryableSender();
        address factorylogic = address(new L1AtomicTokenBridgeCreator());
        factory = L1AtomicTokenBridgeCreator(
            address(new TransparentUpgradeableProxy(factorylogic, PROXY_ADMIN, ""))
        );
        factory.initialize(sender);
        factory.setTemplates(
            l1Templates,
            l2TokenBridgeFactoryTemplate,
            l2RouterTemplate,
            l2StandardGatewayTemplate,
            l2CustomGatewayTemplate,
            l2WethGatewayTemplate,
            l2WethTemplate,
            l2MulticallTemplate,
            l1Weth,
            l1MultiCall,
            MAX_DEPLOYMENT_GAS
        );
    }

    function testDeployment() public {
        MockInbox inbox = new MockInbox(0);
        _testDeployment(address(inbox));
    }

    function testDeploymentFrontrun() public {
        MockInbox inbox = new MockInbox(1);
        _testDeployment(address(inbox));
    }

    function testDeploymentFailDeploy() public {
        // although the deployment must have enough gas to deploy it can still fail due to gas price
        // in such case the 2 retryable can be executed out-of-order
        // Mode 2 simulate this case where the deployment fails and the call is executed first
        MockInbox inbox = new MockInbox(2);
        factory.createTokenBridge({
            inbox: address(inbox), rollupOwner: address(this), maxGasForContracts: 0, gasPriceBid: 0
        });

        // L2 Factory is not deployed in this case
        address l2factory = factory.canonicalL2FactoryAddress();
        assertEq(l2factory, 0xFb5E2D64dbA2141edFF01dD1e66bD76D11fC3f62);
        assertEq(l2factory.code.length, 0);

        inbox.setMode(0); // set back to normal mode
        _testDeployment(address(inbox));
    }

    function _testDeployment(address inbox) internal {
        factory.createTokenBridge({
            inbox: address(inbox), rollupOwner: address(this), maxGasForContracts: 0, gasPriceBid: 0
        });
        {
            address l2factory = factory.canonicalL2FactoryAddress();
            assertTrue(l2factory != address(0), "l2factory should be non-zero");
            assertTrue(l2factory.code.length > 0, "l2factory should have code");
        }

        {
            (address l1r, address l1sgw, address l1cgw, address l1wgw, address l1w) =
                factory.inboxToL1Deployment(address(inbox));
            assertTrue(l1r != address(0), "l1r should be non-zero");
            assertTrue(l1r.code.length > 0, "l1r code");
            assertTrue(l1sgw != address(0), "l1sgw should be non-zero");
            assertTrue(l1sgw.code.length > 0, "l1sgw code");
            assertTrue(l1cgw != address(0), "l1cgw should be non-zero");
            assertTrue(l1cgw.code.length > 0, "l1cgw code");
            assertTrue(l1wgw != address(0), "l1wgw should be non-zero");
            assertTrue(l1wgw.code.length > 0, "l1wgw code");
            assertTrue(l1w != address(0), "l1w should be non-zero");
            assertTrue(l1w.code.length > 0, "l1w code");
        }
        {
            (
                address l2r,
                address l2sgw,
                address l2cgw,
                address l2wgw,
                address l2w,
                address l2pa,
                address l2bpf,
                address l2ue,
                address l2mc
            ) = factory.inboxToL2Deployment(address(inbox));

            assertTrue(l2r != address(0), "l2r should be non-zero");
            assertTrue(l2r.code.length > 0, "l2r code");
            assertTrue(l2sgw != address(0), "l2sgw should be non-zero");
            assertTrue(l2sgw.code.length > 0, "l2sgw code");
            assertTrue(l2cgw != address(0), "l2cgw should be non-zero");
            assertTrue(l2cgw.code.length > 0, "l2cgw code");
            assertTrue(l2wgw != address(0), "l2wgw should be non-zero");
            assertTrue(l2wgw.code.length > 0, "l2wgw code");
            assertTrue(l2w != address(0), "l2w should be non-zero");
            assertTrue(l2w.code.length > 0, "l2w code");
            assertTrue(l2pa != address(0), "l2pa should be non-zero");
            assertTrue(l2pa.code.length > 0, "l2pa code");
            assertTrue(l2bpf != address(0), "l2bpf should be non-zero");
            assertTrue(l2bpf.code.length > 0, "l2bpf code");
            assertTrue(l2ue != address(0), "l2ue should be non-zero");
            assertTrue(l2ue.code.length > 0, "l2ue code");
            assertTrue(l2mc != address(0), "l2mc should be non-zero");
            assertTrue(l2mc.code.length > 0, "l2mc code");
        }
    }
}
