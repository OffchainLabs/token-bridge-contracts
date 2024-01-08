// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../contracts/tokenbridge/ethereum/L1AtomicTokenBridgeCreator.sol";
import "../contracts/tokenbridge/arbitrum/L2AtomicTokenBridgeFactory.sol";
import "../contracts/tokenbridge/libraries/AddressAliasHelper.sol";

import {L1TokenBridgeRetryableSender} from
    "../contracts/tokenbridge/ethereum/L1TokenBridgeRetryableSender.sol";
import {TestWETH9} from "../contracts/tokenbridge/test/TestWETH9.sol";
import {Multicall2} from "../contracts/rpc-utils/MulticallV2.sol";

import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

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
            L1ERC20Gateway(address(new L1ERC20Gateway())),
            L1CustomGateway(address(new L1CustomGateway())),
            L1WethGateway(payable(new L1WethGateway())),
            L1OrbitGatewayRouter(address(new L1OrbitGatewayRouter())),
            L1OrbitERC20Gateway(address(new L1OrbitERC20Gateway())),
            L1OrbitCustomGateway(address(new L1OrbitCustomGateway())),
            IUpgradeExecutor(address(new UpgradeExecutor()))
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
            inbox: address(inbox),
            rollupOwner: address(this),
            maxGasForContracts: 0,
            gasPriceBid: 0
        });

        // L2 Factory is not deployed in this case
        address l2factory = factory.canonicalL2FactoryAddress();
        assertEq(l2factory, 0x20011A455c9eBBeD73CA307539D3e9Baff600fBD);
        assertEq(l2factory.code.length, 0);

        inbox.setMode(0); // set back to normal mode
        _testDeployment(address(inbox));
    }

    function _testDeployment(address inbox) internal {
        factory.createTokenBridge({
            inbox: address(inbox),
            rollupOwner: address(this),
            maxGasForContracts: 0,
            gasPriceBid: 0
        });
        {
            address l2factory = factory.canonicalL2FactoryAddress();
            assertEq(l2factory, 0x20011A455c9eBBeD73CA307539D3e9Baff600fBD);
            assertTrue(l2factory.code.length > 0);
        }

        {
            (address l1r, address l1sgw, address l1cgw, address l1wgw, address l1w) =
                factory.inboxToL1Deployment(address(inbox));
            assertEq(l1r, 0xcB37BCa7042A10FfA75Ff95Ad8B361A13bbAA63A, "l1r");
            assertTrue(l1r.code.length > 0, "l1r code");
            assertEq(l1sgw, 0x013b54d88f76fb9D05b8382747beb1B4Df313507, "l1sgw");
            assertTrue(l1sgw.code.length > 0, "l1sgw code");
            assertEq(l1cgw, 0xf8663294698E0623de82B9791906454A2036575F, "l1cgw");
            assertTrue(l1cgw.code.length > 0, "l1cgw code");
            assertEq(l1wgw, 0x79eF26bE05C5643D5AdC81B8c7e49b0898A74428, "l1wgw");
            assertTrue(l1wgw.code.length > 0, "l1wgw code");
            assertEq(l1w, 0x96d3F6c20EEd2697647F543fE6C08bC2Fbf39758, "l1w");
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

            assertEq(l2r, 0xdB4050B663976d45E810B7C0E3B8B25564bD620d, "l2r");
            assertTrue(l2r.code.length > 0, "l2r code");
            assertEq(l2sgw, 0x25F753b06E1e092292e6773E119D00BEe5A1b8D4, "l2sgw");
            assertTrue(l2sgw.code.length > 0, "l2sgw code");
            assertEq(l2cgw, 0x4Ca25428D90D0813EC134b5160eb6301909B4A9B, "l2cgw");
            assertTrue(l2cgw.code.length > 0, "l2cgw code");
            assertEq(l2wgw, 0x29B1Fa62Af163E550Cb4173BE58787fa2d6456fF, "l2wgw");
            assertTrue(l2wgw.code.length > 0, "l2wgw code");
            assertEq(l2w, 0x7C9c18AE0EeA13600496D1222E8Ec22738b29C61, "l2w");
            assertTrue(l2w.code.length > 0, "l2w code");
            assertEq(l2pa, 0xf789F48Bc2c9ee6E98E564E6383B394ba6F9378c, "l2pa");
            assertTrue(l2pa.code.length > 0, "l2pa code");
            assertEq(l2bpf, 0x9446B15B1128aD326Ccf310a68F2FFB652D31934, "l2bpf");
            assertTrue(l2bpf.code.length > 0, "l2bpf code");
            assertEq(l2ue, 0xC85c71251E9354Cd6a8992BC02d968B04F4b55e6, "l2ue");
            assertTrue(l2ue.code.length > 0, "l2ue code");
            assertEq(l2mc, 0x4572E7101b8A6d889680dA7CC35D6076e651e9fC, "l2mc");
            assertTrue(l2mc.code.length > 0, "l2mc code");
        }
    }
}
