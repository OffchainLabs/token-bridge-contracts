// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {
    L2AtomicTokenBridgeFactory,
    L2RuntimeCode
} from "contracts/tokenbridge/arbitrum/L2AtomicTokenBridgeFactory.sol";
import {L2GatewayRouter} from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import {L2ERC20Gateway} from "contracts/tokenbridge/arbitrum/gateway/L2ERC20Gateway.sol";
import {L2CustomGateway} from "contracts/tokenbridge/arbitrum/gateway/L2CustomGateway.sol";
import {L2WethGateway} from "contracts/tokenbridge/arbitrum/gateway/L2WethGateway.sol";
import {aeWETH} from "contracts/tokenbridge/libraries/aeWETH.sol";
import {UpgradeExecutor} from "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import {ArbMulticall2} from "contracts/rpc-utils/MulticallV2.sol";

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
    }

    /* solhint-disable func-name-mixedcase */
    function test_deployL2Contracts() public {
        address l1Router = makeAddr("l1Router");
        address l1StandardGateway = makeAddr("l1StandardGateway");
        address l1CustomGateway = makeAddr("l1CustomGateway");
        address l1WethGateway = makeAddr("l1WethGateway");
        address l1Weth = makeAddr("l1Weth");

        address l2StandardGatewayCanonicalAddress = makeAddr("l2StandardGatewayCanonicalAddress");
        address rollupOwner = makeAddr("rollupOwner");
        address aliasedL1UpgradeExecutor = makeAddr("aliasedL1UpgradeExecutor");

        L2RuntimeCode memory runtimeCode = L2RuntimeCode(
            router.code,
            standardGateway.code,
            customGateway.code,
            wethGateway.code,
            weth.code,
            upgradeExecutor.code,
            multicall.code
        );

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

        ////TODO state checks
    }

    function test_deployL2Contracts_revert_AlreadyExists() public {
        address l1Router = makeAddr("l1Router");
        address l1StandardGateway = makeAddr("l1StandardGateway");
        address l1CustomGateway = makeAddr("l1CustomGateway");
        address l1WethGateway = makeAddr("l1WethGateway");
        address l1Weth = makeAddr("l1Weth");

        address l2StandardGatewayCanonicalAddress = makeAddr("l2StandardGatewayCanonicalAddress");
        address rollupOwner = makeAddr("rollupOwner");
        address aliasedL1UpgradeExecutor = makeAddr("aliasedL1UpgradeExecutor");

        L2RuntimeCode memory runtimeCode = L2RuntimeCode(
            router.code,
            standardGateway.code,
            customGateway.code,
            wethGateway.code,
            weth.code,
            upgradeExecutor.code,
            multicall.code
        );

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
            l2StandardGatewayCanonicalAddress,
            rollupOwner,
            aliasedL1UpgradeExecutor
        );
    }
}
