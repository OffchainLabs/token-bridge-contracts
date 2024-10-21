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

    function hasRole(bytes32, address) external pure returns (bool) {
        return true;
    }

    function getProxyAdmin() external view returns (address) {
        return address(this);
    }

    function calculateRetryableSubmissionFee(uint256, uint256) external pure returns (uint256) {
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
        return 0;
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
            _deployUpgradeExecutor()
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
            assertEq(l1r, 0xb458B5E13BEf3ca7C4a87bF7368D3Fe9E7a631DE, "l1r");
            assertTrue(l1r.code.length > 0, "l1r code");
            assertEq(l1sgw, 0x75b043aA7C73F9c3eC8D3A1A635a39b30E93cf2f, "l1sgw");
            assertTrue(l1sgw.code.length > 0, "l1sgw code");
            assertEq(l1cgw, 0x5Edd3097a2a1fE878E61efB2F3FFA41BDD58803E, "l1cgw");
            assertTrue(l1cgw.code.length > 0, "l1cgw code");
            assertEq(l1wgw, 0x9062A6901a9E0285dcd67d14046412be48db143f, "l1wgw");
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

            assertEq(l2r, 0xcf35298BFB982476a85201Eb144F7099761744Ee, "l2r");
            assertTrue(l2r.code.length > 0, "l2r code");
            assertEq(l2sgw, 0x48d1FE88d96c0Cb40B0ddD660a0dd7edE13517C9, "l2sgw");
            assertTrue(l2sgw.code.length > 0, "l2sgw code");
            assertEq(l2cgw, 0x7C8118742fB20e0A786C5C21cbf7c59c412130bD, "l2cgw");
            assertTrue(l2cgw.code.length > 0, "l2cgw code");
            assertEq(l2wgw, 0x05d35724540FD8E4149933065f53431dfDcF4e80, "l2wgw");
            assertTrue(l2wgw.code.length > 0, "l2wgw code");
            assertEq(l2w, 0x9bd4C8C3D644D8036a09726A5044d09cB33a1E3e, "l2w");
            assertTrue(l2w.code.length > 0, "l2w code");
            assertEq(l2pa, 0x5C8fEE06019d8E1E1EF424C867f8A40885214aFB, "l2pa");
            assertTrue(l2pa.code.length > 0, "l2pa code");
            assertEq(l2bpf, 0xa744250a6CA35F6DB35B001AC5aa1E76A7D312CE, "l2bpf");
            assertTrue(l2bpf.code.length > 0, "l2bpf code");
            assertEq(l2ue, 0x297eA477216C8E118278cB1D91D2A1dE761460f6, "l2ue");
            assertTrue(l2ue.code.length > 0, "l2ue code");
            assertEq(l2mc, 0x0313A116ef65CBc0342AeE389EB10dAC28b48804, "l2mc");
            assertTrue(l2mc.code.length > 0, "l2mc code");
        }
    }

    function _deployUpgradeExecutor() internal returns (IUpgradeExecutor executor) {
        bytes memory bytecode = _getBytecode(
            "/node_modules/@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json"
        );

        address addr;
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(addr != address(0), "bytecode deployment failed");

        executor = IUpgradeExecutor(addr);
    }

    function _getBytecode(bytes memory path) internal returns (bytes memory) {
        string memory readerBytecodeFilePath = string(abi.encodePacked(vm.projectRoot(), path));
        string memory json = vm.readFile(readerBytecodeFilePath);
        try vm.parseJsonBytes(json, ".bytecode.object") returns (bytes memory bytecode) {
            return bytecode;
        } catch {
            return vm.parseJsonBytes(json, ".bytecode");
        }
    }
}
