// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import { MasterVaultTest } from "./MasterVault.t.sol";
import { MockSubVault } from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract MasterVaultTestWithSubvaultFresh is MasterVaultTest {
    function setUp() public override {
        super.setUp();
        MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
        vault.setSubVault(IERC4626(address(_subvault)), 0);
    }
}

contract AttackTest is MasterVaultTestWithSubvaultFresh {
    function _calculateStolenAmount(
        uint128 initialSubVaultTotalAssets,
        uint128 initialSubVaultTotalSupply,
        uint128 vaultInitialDepositAmount,
        uint128 vaultAttackDepositAmount
    ) public returns (uint256) {
        console2.log("initialSubVaultTotalAssets:", initialSubVaultTotalAssets);
        console2.log("initialSubVaultTotalSupply:", initialSubVaultTotalSupply);
        console2.log("vaultInitialDepositAmount:", vaultInitialDepositAmount);
        console2.log("vaultAttackDepositAmount:", vaultAttackDepositAmount);

        MockSubVault(address(vault.subVault())).adminMint(address(this), initialSubVaultTotalSupply);
        token.mint(initialSubVaultTotalAssets);
        token.transfer(address(vault.subVault()), initialSubVaultTotalAssets);

        assertEq(
            vault.subVault().totalAssets(),
            initialSubVaultTotalAssets,
            "subvault total assets should be correct"
        );
        assertEq(
            vault.subVault().totalSupply(),
            initialSubVaultTotalSupply,
            "subvault total supply should be correct"
        );

        vm.startPrank(user);
        token.mint(vaultInitialDepositAmount);
        token.approve(address(vault), vaultInitialDepositAmount);
        vault.deposit(vaultInitialDepositAmount, user);
        vm.stopPrank();

        address attacker = address(0xBEEF);
        vm.startPrank(attacker);
        token.mint(vaultAttackDepositAmount);
        token.approve(address(vault), vaultAttackDepositAmount);
        uint256 sharesBack = vault.deposit(vaultAttackDepositAmount, attacker);
        // vm.assume(sharesBack < vault.maxRedeem(attacker));
        uint256 assetsBack = vault.redeem(sharesBack, attacker, attacker);
        vm.stopPrank();

        uint256 stolenAmount = assetsBack > vaultAttackDepositAmount
            ? assetsBack - vaultAttackDepositAmount
            : 0;

        console2.log("stolenAmount:", stolenAmount);

        return stolenAmount;
    }

    function testFindCombo(
        uint120 initialSubVaultTotalAssets,
        int8 initialSubVaultTotalSupplyWiggle,
        uint128 vaultInitialDepositAmount,
        uint128 vaultAttackDepositAmount
    ) public {
        if(initialSubVaultTotalAssets < 1e18) {
            initialSubVaultTotalAssets += 1e18;
        }
        if(vaultInitialDepositAmount < 1e18) {
            vaultInitialDepositAmount += 1e18;
        }

        uint128 initialSubVaultTotalSupply = uint128(int128(int120(initialSubVaultTotalAssets)) + int128(initialSubVaultTotalSupplyWiggle));
        uint256 stolenAmt = _calculateStolenAmount(
            initialSubVaultTotalAssets,
            initialSubVaultTotalSupply,
            vaultInitialDepositAmount,
            vaultAttackDepositAmount
        );
        require(
            stolenAmt == 0,
            "theft occurred with these parameters"
        );
    }
}
