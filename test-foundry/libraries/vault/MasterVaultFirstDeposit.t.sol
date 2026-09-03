// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest} from "./MasterVaultCore.t.sol";

contract MasterVaultFirstDepositTest is MasterVaultCoreTest {
    function testCannotRugFirstDepositWithDonationAttack(uint128 attackerDepositAmount, uint128 attackerDonationAmount, uint128 userDepositAmount) public {
        uint256 snapshot = vm.snapshot();
        uint256 sharesRecvBefore = _depositAs(userDepositAmount);
        vm.revertTo(snapshot);

        // attacker deposit
        _depositAs(attackerDepositAmount);

        // attacker donate
        vm.prank(address(vault));
        token.mintAmount(attackerDonationAmount);

        // user deposit
        uint256 sharesRecvAfter = _depositAs(userDepositAmount);

        // make sure user does not lose
        assertGe(sharesRecvAfter, sharesRecvBefore, "user received fewer shares after attacker donation");
    }
}
