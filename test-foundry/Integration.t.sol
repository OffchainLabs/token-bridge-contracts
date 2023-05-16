// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { L1GatewayRouterTest } from "./L1GatewayRouter.t.sol";
import { ERC20InboxMock } from "contracts/tokenbridge/test/InboxMock.sol";
import { L1OrbitERC20Gateway } from "contracts/tokenbridge/ethereum/gateway/L1OrbitERC20Gateway.sol";
import { L1OrbitGatewayRouter } from "contracts/tokenbridge/ethereum/gateway/L1OrbitGatewayRouter.sol";
import { L2GatewayRouter } from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import { L1GatewayRouter } from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import { L1OrbitCustomGateway } from "contracts/tokenbridge/ethereum/gateway/L1OrbitCustomGateway.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { TestERC20 } from "contracts/tokenbridge/test/TestERC20.sol";

import { ERC20Inbox } from "lib/nitro-contracts/contracts/src/bridge/ERC20Inbox.sol";
import { ERC20Bridge } from "lib/nitro-contracts/contracts/src/bridge/ERC20Bridge.sol";
import { ERC20PresetFixedSupply } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import { IOwnable } from "lib/nitro-contracts/contracts/src/bridge/IOwnable.sol";
import { ISequencerInbox } from "lib/nitro-contracts/contracts/src/bridge/ISequencerInbox.sol";
import "./util/TestUtil.sol";

contract IntegrationTest is Test {
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public counterpartGateway = makeAddr("counterpartGateway");
    address public rollup = makeAddr("rollup");
    address public seqInbox = makeAddr("seqInbox");
    address public l2Gateway = makeAddr("l2Gateway");
    bytes32 public cloneableProxyHash = bytes32("123");
    address public l2BeaconProxyFactory = makeAddr("l2BeaconProxyFactory");

    ERC20PresetFixedSupply public nativeToken;
    ERC20Inbox public inbox;
    ERC20Bridge public bridge;
    L1OrbitERC20Gateway public defaultGateway;
    L1OrbitGatewayRouter public router;
    IERC20 public token;

    function setUp() public {
        // deploy token, bridge and inbox
        nativeToken = new ERC20PresetFixedSupply("Appchain Token", "App", 100000000, address(this));
        inbox = ERC20Inbox(TestUtil.deployProxy(address(new ERC20Inbox())));
        bridge = ERC20Bridge(TestUtil.deployProxy(address(new ERC20Bridge())));

        // init bridge and inbox
        bridge.initialize(IOwnable(rollup), address(nativeToken));
        inbox.initialize(bridge, ISequencerInbox(seqInbox));
        vm.prank(rollup);
        bridge.setDelayedInbox(address(inbox), true);

        // create default gateway and router
        defaultGateway = L1OrbitERC20Gateway(
            TestUtil.deployProxy(address(new L1OrbitERC20Gateway()))
        );
        router = L1OrbitGatewayRouter(TestUtil.deployProxy(address(new L1OrbitGatewayRouter())));
        router.initialize(
            owner,
            address(defaultGateway),
            address(0),
            counterpartGateway,
            address(inbox)
        );
        defaultGateway.initialize(
            l2Gateway,
            address(router),
            address(inbox),
            cloneableProxyHash,
            l2BeaconProxyFactory
        );

        // token to bridge
        token = IERC20(address(new TestERC20()));

        // fund accounts
        nativeToken.transfer(user, 1_000_000);
        nativeToken.transfer(owner, 1_000_000);
        vm.prank(user);
        TestERC20(address(token)).mint();
        // vm.deal(owner, 100 ether);
        // vm.deal(user, 100 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_depositNative() public {
        uint256 depositAmount = 140;
        vm.prank(user);
        nativeToken.approve(address(bridge), 140);

        vm.prank(user);
        inbox.depositERC20(depositAmount);
    }

    function test_depositToken() public {
        uint256 tokenDepositAmount = 250;
        uint256 maxSubmissionCost = 0;
        uint256 maxGas = 100000;
        uint256 gasPriceBid = 3;
        uint256 nativeTokenTotalFee = maxGas * gasPriceBid;

        /// set default gateway
        vm.startPrank(owner);
        nativeToken.approve(address(router), nativeTokenTotalFee);
        router.setDefaultGateway(
            address(defaultGateway),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            nativeTokenTotalFee
        );
        assertEq(router.defaultGateway(), address(defaultGateway), "Invalid defaultGateway");
        vm.stopPrank();

        // snapshot state before
        uint256 userTokenBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(defaultGateway));
        uint256 userNativeTokenBalanceBefore = nativeToken.balanceOf(user);
        uint256 bridgeNativeTokenBalanceBefore = nativeToken.balanceOf(address(bridge));

        {
            /// do token deposit
            vm.startPrank(user);

            token.approve(address(defaultGateway), tokenDepositAmount);

            nativeToken.approve(address(defaultGateway), nativeTokenTotalFee);

            address refundTo = user;
            bytes memory userEncodedData = abi.encode(maxSubmissionCost, "", nativeTokenTotalFee);
            router.outboundTransferCustomRefund(
                address(token),
                refundTo,
                user,
                tokenDepositAmount,
                maxGas,
                gasPriceBid,
                userEncodedData
            );

            vm.stopPrank();
        }

        /// checks
        {
            uint256 userTokenBalanceAfter = token.balanceOf(user);
            uint256 l1GatewayBalanceAfter = token.balanceOf(address(defaultGateway));
            uint256 userNativeTokenBalanceAfter = nativeToken.balanceOf(user);
            uint256 bridgeNativeTokenBalanceAfter = nativeToken.balanceOf(address(bridge));

            assertEq(
                userTokenBalanceBefore - userTokenBalanceAfter,
                tokenDepositAmount,
                "Invalid user token balance"
            );

            assertEq(
                l1GatewayBalanceAfter - l1GatewayBalanceBefore,
                tokenDepositAmount,
                "Invalid default gateway token balance"
            );

            assertEq(
                userNativeTokenBalanceBefore - userNativeTokenBalanceAfter,
                nativeTokenTotalFee,
                "Invalid user native token balance"
            );

            assertEq(
                bridgeNativeTokenBalanceAfter - bridgeNativeTokenBalanceBefore,
                nativeTokenTotalFee,
                "Invalid user native token balance"
            );
        }
    }
}
