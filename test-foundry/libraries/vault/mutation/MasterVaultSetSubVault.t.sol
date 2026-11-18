// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest} from "../MasterVaultCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MockSubVault} from "../../../../contracts/tokenbridge/test/MockSubVault.sol";
import {TestERC20} from "../../../../contracts/tokenbridge/test/TestERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract MasterVaultSetSubVaultTest is MasterVaultCoreTest {
    function test_setSubVault_nonWhitelisted_reverts() public {
        MockSubVault newSv = new MockSubVault(IERC20(address(token)), "New", "NEW");
        vm.prank(generalManager);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.SubVaultNotWhitelisted.selector, address(newSv))
        );
        vault.setSubVault(IERC4626(address(newSv)));
    }

    function test_setSubVault_wrongAsset_reverts() public {
        TestERC20 otherToken = new TestERC20();
        MockSubVault wrongAssetSv = new MockSubVault(IERC20(address(otherToken)), "Wrong", "WRG");
        vault.setSubVaultWhitelist(address(wrongAssetSv), true);
        vm.prank(generalManager);
        vm.expectRevert(MasterVault.SubVaultAssetMismatch.selector);
        vault.setSubVault(IERC4626(address(wrongAssetSv)));
    }

    function test_setSubVault_nonZeroAllocation_reverts() public {
        MockSubVault newSv = new MockSubVault(IERC20(address(token)), "New", "NEW");
        vault.setSubVaultWhitelist(address(newSv), true);
        vault.setTargetAllocationWad(5e17);
        vm.prank(generalManager);
        vm.expectRevert(abi.encodeWithSelector(MasterVault.NonZeroTargetAllocation.selector, 5e17));
        vault.setSubVault(IERC4626(address(newSv)));
    }

    function test_setSubVault_nonZeroShares_reverts() public {
        _setupWithAllocation(1e18, 5e17);
        // allocation is 50%, so there are subvault shares. Set allocation to 0 first.
        vault.setTargetAllocationWad(0);
        // subvault still has shares even though allocation is 0
        assertTrue(vault.subVault().balanceOf(address(vault)) > 0, "should have subvault shares");
        MockSubVault newSv = new MockSubVault(IERC20(address(token)), "New", "NEW");
        vault.setSubVaultWhitelist(address(newSv), true);
        uint256 shares = vault.subVault().balanceOf(address(vault));
        vm.prank(generalManager);
        vm.expectRevert(abi.encodeWithSelector(MasterVault.NonZeroSubVaultShares.selector, shares));
        vault.setSubVault(IERC4626(address(newSv)));
    }
}
