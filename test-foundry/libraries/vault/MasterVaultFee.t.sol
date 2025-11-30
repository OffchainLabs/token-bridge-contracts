// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "./MasterVaultCore.t.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";

contract MasterVaultFeeTest is MasterVaultCoreTest {
    address public beneficiaryAddress = address(0x9999);

    function test_setPerformanceFee_enable() public {
        assertFalse(vault.enablePerformanceFee(), "Performance fee should be disabled by default");

        vault.setPerformanceFee(true);

        assertTrue(vault.enablePerformanceFee(), "Performance fee should be enabled");
    }

    function test_setPerformanceFee_disable() public {
        vault.setPerformanceFee(true);
        assertTrue(vault.enablePerformanceFee(), "Performance fee should be enabled");

        vault.setPerformanceFee(false);

        assertFalse(vault.enablePerformanceFee(), "Performance fee should be disabled");
    }

    function test_setPerformanceFee_revert_NotVaultManager() public {
        vm.prank(user);
        vm.expectRevert();
        vault.setPerformanceFee(true);
    }

    function test_setPerformanceFee_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit PerformanceFeeToggled(true);
        vault.setPerformanceFee(true);

        vm.expectEmit(true, true, true, true);
        emit PerformanceFeeToggled(false);
        vault.setPerformanceFee(false);
    }

    function test_setBeneficiary() public {
        assertEq(vault.beneficiary(), address(0), "Beneficiary should be zero address by default");

        vault.setBeneficiary(beneficiaryAddress);

        assertEq(vault.beneficiary(), beneficiaryAddress, "Beneficiary should be updated");
    }

    function test_setBeneficiary_revert_ZeroAddress() public {
        vm.expectRevert(MasterVault.ZeroAddress.selector);
        vault.setBeneficiary(address(0));
    }

    function test_setBeneficiary_revert_NotFeeManager() public {
        vm.prank(user);
        vm.expectRevert();
        vault.setBeneficiary(beneficiaryAddress);
    }

    function test_setBeneficiary_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit BeneficiaryUpdated(address(0), beneficiaryAddress);
        vault.setBeneficiary(beneficiaryAddress);

        address newBeneficiary = address(0x8888);
        vm.expectEmit(true, true, true, true);
        emit BeneficiaryUpdated(beneficiaryAddress, newBeneficiary);
        vault.setBeneficiary(newBeneficiary);
    }

    function test_setPerformanceFee_withVaultManagerRole() public {
        address vaultManager = address(0x7777);
        vault.grantRole(vault.VAULT_MANAGER_ROLE(), vaultManager);

        vm.prank(vaultManager);
        vault.setPerformanceFee(true);

        assertTrue(vault.enablePerformanceFee(), "Vault manager should be able to set performance fee");
    }

    function test_setBeneficiary_withFeeManagerRole() public {
        address feeManager = address(0x6666);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), feeManager);

        vm.prank(feeManager);
        vault.setBeneficiary(beneficiaryAddress);

        assertEq(vault.beneficiary(), beneficiaryAddress, "Fee manager should be able to set beneficiary");
    }

    function test_deposit_updatesTotalPrincipal() public {
        assertEq(vault.totalPrincipal(), 0, "Total principal should be zero initially");

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 100;
        token.approve(address(vault), depositAmount);

        vault.deposit(depositAmount, user);

        assertEq(vault.totalPrincipal(), int256(depositAmount), "Total principal should equal deposit amount");

        vm.stopPrank();
    }

    function test_mint_updatesTotalPrincipal() public {
        assertEq(vault.totalPrincipal(), 0, "Total principal should be zero initially");

        vm.startPrank(user);
        token.mint();
        uint256 shares = 100;
        token.approve(address(vault), shares);

        uint256 assets = vault.mint(shares, user);

        assertEq(vault.totalPrincipal(), int256(assets), "Total principal should equal assets deposited");

        vm.stopPrank();
    }

    function test_withdraw_updatesTotalPrincipal() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 200;
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

        assertEq(vault.totalPrincipal(), int256(depositAmount), "Total principal should equal deposit amount");

        uint256 withdrawAmount = 100;
        vault.withdraw(withdrawAmount, user, user);

        assertEq(vault.totalPrincipal(), int256(depositAmount - withdrawAmount), "Total principal should decrease by withdraw amount");

        vm.stopPrank();
    }

    function test_redeem_updatesTotalPrincipal() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 200;
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);

        assertEq(vault.totalPrincipal(), int256(depositAmount), "Total principal should equal deposit amount");

        uint256 sharesToRedeem = shares / 2;
        uint256 assetsReceived = vault.redeem(sharesToRedeem, user, user);

        assertEq(vault.totalPrincipal(), int256(depositAmount - assetsReceived), "Total principal should decrease by redeemed assets");

        vm.stopPrank();
    }

    function test_withdrawPerformanceFees_revert_PerformanceFeeDisabled() public {
        vault.setBeneficiary(beneficiaryAddress);

        vm.expectRevert(MasterVault.PerformanceFeeDisabled.selector);
        vault.withdrawPerformanceFees();
    }

    function test_withdrawPerformanceFees_revert_BeneficiaryNotSet() public {
        vault.setPerformanceFee(true);

        vm.expectRevert(MasterVault.BeneficiaryNotSet.selector);
        vault.withdrawPerformanceFees();
    }

    function test_withdrawPerformanceFees_VaultDoubleInAssets() public {
        vault.setPerformanceFee(true);
        vault.setBeneficiary(beneficiaryAddress);

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        assertEq(vault.totalPrincipal(), int256(depositAmount), "Total principal should equal deposit");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should equal deposit");
        assertEq(vault.totalProfit(), 0, "Should have no profit initially");

        vm.prank(address(vault));
        token.mint();

        assertEq(vault.totalAssets(), depositAmount * 2, "Total assets should be doubled");
        assertEq(vault.totalProfit(), int256(depositAmount), "Profit should equal initial deposit amount");

        uint256 beneficiaryBalanceBefore = token.balanceOf(beneficiaryAddress);

        vm.expectEmit(true, true, true, true);
        emit PerformanceFeesWithdrawn(beneficiaryAddress, depositAmount);
        vault.withdrawPerformanceFees();

        assertEq(token.balanceOf(beneficiaryAddress), beneficiaryBalanceBefore + depositAmount, "Beneficiary should receive profit");
        assertEq(vault.totalAssets(), depositAmount, "Vault assets should decrease by profit amount");
    }

    event PerformanceFeeToggled(bool enabled);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event PerformanceFeesWithdrawn(address indexed beneficiary, uint256 amount);
}
