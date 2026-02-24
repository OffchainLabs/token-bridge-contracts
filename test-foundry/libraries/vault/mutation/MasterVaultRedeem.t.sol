// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultMutationBase} from "./MasterVaultMutationBase.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultRedeemTest is MasterVaultMutationBase {
    function test_redeem_minAssets_reverts() public {
        uint256 shares = _depositAs(1e18);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.InsufficientAssets.selector, 1e18, 2e18)
        );
        vault.redeem(shares, 2e18);
    }

    // /// TARGETS MUTANT #38 in MasterVault.sol
    // function test_redeem_minAssets_swapArgs_gt0() public {
    //     uint256 shares = _depositAs(1e18);
    //     vm.prank(user);
    //     // minAssets=1 should pass since assets >= 1
    //     vault.redeem(shares, 1);
    // }

    // /// TARGETS MUTANT #39 in MasterVault.sol
    // function test_redeem_minAssets_swapedComparison() public {
    //     uint256 shares = _depositAs(1e18);
    //     // Request minAssets just above what we'd get
    //     vm.prank(user);
    //     vm.expectRevert();
    //     vault.redeem(shares, 1e18 + 1);
    // }
}
