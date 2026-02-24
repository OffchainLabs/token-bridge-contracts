// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest} from "../MasterVaultCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultRedeemTest is MasterVaultCoreTest {
    function test_redeem_minAssets_reverts() public {
        uint256 shares = _depositAs(1e18);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.InsufficientAssets.selector, 1e18, 2e18)
        );
        vault.redeem(shares, 2e18);
    }
}
