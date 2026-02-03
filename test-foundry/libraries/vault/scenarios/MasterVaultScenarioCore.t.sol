// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "../MasterVaultCore.t.sol";

contract MasterVaultScenarioCoreTest is MasterVaultCoreTest {
    address public userA = address(0xA);
    address public userB = address(0xB);
    address public beneficiaryAddress = address(0x9999);
    uint256 public userAInitialBalance;
    uint256 public userBInitialBalance;

    function setUp() public virtual override {
        super.setUp();
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.rolesRegistry().grantRole(vault.FEE_MANAGER_ROLE(), address(this));
        vault.rolesRegistry().grantRole(vault.KEEPER_ROLE(), address(this));
        vault.setMinimumRebalanceAmount(1);
        vault.setBeneficiary(beneficiaryAddress);
    }

    function _mintTokens(address _user, uint256 _amount) internal {
        vm.prank(_user);
        token.mint(_amount);
        if (_user == userA) userAInitialBalance = token.balanceOf(userA);
        if (_user == userB) userBInitialBalance = token.balanceOf(userB);
    }

    function _deposit(address _user, uint256 _amount) internal returns (uint256) {
        vm.prank(_user);
        token.transfer(user, _amount);

        vm.startPrank(user);
        token.approve(address(vault), _amount);
        uint256 shares = vault.deposit(_amount);
        vault.transfer(_user, shares);
        vm.stopPrank();

        return shares;
    }

    function _redeem(address _user, uint256 _shares) internal returns (uint256) {
        vm.prank(_user);
        vault.transfer(user, _shares);

        vm.startPrank(user);
        uint256 assets = vault.redeem(_shares, 0);
        token.transfer(_user, assets);
        vm.stopPrank();

        return assets;
    }

    function _simulateProfit(uint256 _amount) internal {
        token.mint(_amount);
        if (vault.targetAllocationWad() > 0) {
            token.transfer(address(vault.subVault()), _amount);
        } else {
            token.transfer(address(vault), _amount);
        }
    }

    function _simulateLoss(uint256 _amount) internal {
        if (vault.targetAllocationWad() > 0) {
            vm.prank(address(vault.subVault()));
        } else {
            vm.prank(address(vault));
        }
        token.transfer(address(0xdead), _amount);
    }

    function _distributePerformanceFee() internal {
        vault.distributePerformanceFee();
    }

    function _checkHoldings(
        uint256 _expectedA,
        uint256 _expectedB,
        uint256 _expectedBeneficiary
    ) internal {
        assertEq(token.balanceOf(userA), _expectedA, "User A balance mismatch");
        assertEq(token.balanceOf(userB), _expectedB, "User B balance mismatch");
        assertEq(
            token.balanceOf(beneficiaryAddress),
            _expectedBeneficiary,
            "Beneficiary balance mismatch"
        );
    }
}
