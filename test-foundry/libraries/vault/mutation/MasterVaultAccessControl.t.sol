// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest} from "../MasterVaultCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultAccessControlTest is MasterVaultCoreTest {
    function test_onlyGateway_rejectsNonGateway() public {
        address notGateway = address(0x1234);
        vm.prank(notGateway);
        token.mintAmount(1e18);
        vm.startPrank(notGateway);
        token.approve(address(vault), 1e18);
        vm.expectRevert(abi.encodeWithSelector(MasterVault.NotGateway.selector, notGateway));
        vault.deposit(1e18);
        vm.stopPrank();
    }

    function test_onlyKeeper_rejectsNonKeeper() public {
        _depositAs(1e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        address notKeeper = address(0x7777);
        vm.prank(notKeeper);
        vm.expectRevert(MasterVault.NotKeeper.selector);
        vault.rebalance(-1e18);
    }
}
