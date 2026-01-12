// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "./MasterVaultCore.t.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import { MockSubVault } from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    MathUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract MasterVaultFeeTest is MasterVaultCoreTest {
    address public beneficiaryAddress = address(0x9999);

    function test_setBeneficiary() public {
        assertEq(vault.beneficiary(), address(0), "Beneficiary should be zero address by default");

        vault.setBeneficiary(beneficiaryAddress);

        assertEq(vault.beneficiary(), beneficiaryAddress, "Beneficiary should be updated");
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

    function test_deposit_updatesTotalPrincipal() public {
        assertEq(vault.totalPrincipal(), 0, "Total principal should be zero initially");

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 100;
        token.approve(address(vault), depositAmount);

        vault.deposit(depositAmount, user);

        assertEq(
            vault.totalPrincipal(),
            (depositAmount),
            "Total principal should equal deposit amount"
        );

        vm.stopPrank();
    }

    function test_mint_updatesTotalPrincipal() public {
        assertEq(vault.totalPrincipal(), 0, "Total principal should be zero initially");

        vm.startPrank(user);
        token.mint();
        uint256 shares = 100;
        token.approve(address(vault), shares);

        uint256 assets = vault.mint(shares, user);

        assertEq(vault.totalPrincipal(), assets, "Total principal should equal assets deposited");

        vm.stopPrank();
    }

    function test_withdraw_updatesTotalPrincipal() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 200;
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);

        assertEq(
            vault.totalPrincipal(),
            depositAmount,
            "Total principal should equal deposit amount"
        );

        uint256 withdrawAmount = 100;
        vault.withdraw(withdrawAmount, user, user);

        assertEq(
            vault.totalPrincipal(),
            depositAmount - withdrawAmount,
            "Total principal should decrease by withdraw amount"
        );

        vm.stopPrank();
    }

    function test_redeem_updatesTotalPrincipal() public {
        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = 200;
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);

        assertEq(
            vault.totalPrincipal(),
            depositAmount,
            "Total principal should equal deposit amount"
        );

        uint256 sharesToRedeem = shares / 2;
        uint256 assetsReceived = vault.redeem(sharesToRedeem, user, user);

        assertEq(
            vault.totalPrincipal(),
            depositAmount - assetsReceived,
            "Total principal should decrease by redeemed assets"
        );

        vm.stopPrank();
    }

    function test_withdrawPerformanceFees_revert_BeneficiaryNotSet() public {
        vm.expectRevert(MasterVault.BeneficiaryNotSet.selector);
        vault.distributePerformanceFee();
    }

    function test_withdrawPerformanceFees_VaultDoubleInAssets_Fuzz(uint256 allocationWad) public {
        IERC4626 _subvault = vault.subVault();

        vm.assume(allocationWad <= 1e18);

        if (vault.targetAllocationWad() != allocationWad) {
            vault.setTargetAllocationWad(allocationWad);
        }

        vault.setBeneficiary(beneficiaryAddress);

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        vault.rebalance();

        assertEq(vault.totalPrincipal(), depositAmount, "Total principal should equal deposit");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should equal deposit");
        assertEq(
            vault.totalProfit(MathUpgradeable.Rounding.Up),
            0,
            "Should have no profit initially"
        );

        uint256 subVaultAssets = _subvault.totalAssets();
        uint256 idleAssets = token.balanceOf(address(vault));

        if (subVaultAssets > 0) {
            vm.prank(address(_subvault));
            token.mint(subVaultAssets);
        }

        if (idleAssets > 0) {
            vm.prank(address(vault));
            token.mint(idleAssets);
        }

        assertEq(vault.totalAssets(), depositAmount * 2, "Total assets should be doubled");
        assertEq(
            vault.totalProfit(MathUpgradeable.Rounding.Down),
            depositAmount,
            "Profit should equal initial deposit amount"
        );

        uint256 beneficiaryBalanceBefore = token.balanceOf(beneficiaryAddress);

        uint256 expectedProfit = depositAmount;
        if (expectedProfit > 0) {
            uint256 vaultBalance = token.balanceOf(address(vault));
            uint256 expectedTransferred = MathUpgradeable.min(vaultBalance, expectedProfit);
            vm.expectEmit(true, true, true, true);
            emit PerformanceFeesWithdrawn(
                beneficiaryAddress,
                expectedTransferred,
                expectedProfit - expectedTransferred
            );
        }
        vault.distributePerformanceFee();

        assertEq(
            token.balanceOf(beneficiaryAddress),
            beneficiaryBalanceBefore + depositAmount,
            "Beneficiary should receive profit"
        );
        assertEq(
            vault.totalAssets(),
            depositAmount,
            "Vault assets should decrease by profit amount"
        );
    }

    function test_withdrawPerformanceFees_SubVaultDoubleInAssets_Fuzz(
        uint256 allocationWad
    ) public {
        IERC4626 _subvault = vault.subVault();

        vm.assume(allocationWad <= 1e18);

        if (vault.targetAllocationWad() != allocationWad) {
            vault.setTargetAllocationWad(allocationWad);
        }

        vault.setBeneficiary(beneficiaryAddress);

        vm.startPrank(user);
        token.mint();
        uint256 depositAmount = token.balanceOf(user);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        vault.rebalance();

        assertEq(vault.totalPrincipal(), depositAmount, "Total principal should equal deposit");
        assertEq(vault.totalAssets(), depositAmount, "Total assets should equal deposit");
        assertEq(
            vault.totalProfit(MathUpgradeable.Rounding.Up),
            0,
            "Should have no profit initially"
        );

        uint256 subVaultAssets = _subvault.totalAssets();
        uint256 vaultAssetsInSubVault = vault.totalAssets() - token.balanceOf(address(vault));

        if (subVaultAssets > 0) {
            vm.prank(address(_subvault));
            token.mint(subVaultAssets);
        }

        uint256 expectedProfit = vaultAssetsInSubVault;

        assertEq(
            vault.totalAssets(),
            depositAmount + expectedProfit,
            "Total assets should increase by subvault profit"
        );
        assertEq(
            vault.totalProfit(MathUpgradeable.Rounding.Down),
            expectedProfit,
            "Profit should equal subvault profit"
        );

        uint256 beneficiaryBalanceBefore = token.balanceOf(beneficiaryAddress);

        if (expectedProfit > 0) {
            uint256 vaultBalance = token.balanceOf(address(vault));
            uint256 expectedTransferred = MathUpgradeable.min(vaultBalance, expectedProfit);
            vm.expectEmit(true, true, true, true);
            emit PerformanceFeesWithdrawn(
                beneficiaryAddress,
                expectedTransferred,
                expectedProfit - expectedTransferred
            );
        }
        vault.distributePerformanceFee();

        assertEq(
            token.balanceOf(beneficiaryAddress),
            beneficiaryBalanceBefore + expectedProfit,
            "Beneficiary should receive profit"
        );
        assertApproxEqAbs(
            vault.totalAssets(),
            depositAmount,
            1,
            "Vault assets should decrease by profit amount"
        );
    }

    event PerformanceFeeToggled(bool enabled);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event PerformanceFeesWithdrawn(
        address indexed beneficiary,
        uint256 amountTransferred,
        uint256 amountWithdrawn
    );
}

contract MasterVaultFeeTestWithSubvaultFresh is MasterVaultFeeTest {
    function setUp() public override {
        super.setUp();
        MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
        vault.setSubVault(IERC4626(address(_subvault)));
    }
}

// contract MasterVaultFeeTestWithSubvaultHoldingAssets is MasterVaultFeeTest {
//     function setUp() public override {
//         super.setUp();

//         MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
//         uint256 _initAmount = 97659744;
//         token.mint(_initAmount);
//         token.approve(address(_subvault), _initAmount);
//         _subvault.deposit(_initAmount, address(this));
//         assertEq(
//             _initAmount,
//             _subvault.totalAssets(),
//             "subvault should be initiated with assets = _initAmount"
//         );
//         assertEq(
//             _initAmount,
//             _subvault.totalSupply(),
//             "subvault should be initiated with shares = _initAmount"
//         );

//         vault.setSubVault(IERC4626(address(_subvault)));
//     }
// }
