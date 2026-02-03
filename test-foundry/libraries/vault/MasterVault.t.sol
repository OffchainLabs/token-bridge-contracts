// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest} from "./MasterVaultCore.t.sol";
import {MockSubVault} from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MasterVaultFirstDepositTest is MasterVaultCoreTest {
    using Math for uint256;

    // first deposit
    function test_deposit(uint96 _depositAmount) public {
        uint256 depositAmount = _depositAmount;
        vm.startPrank(user);
        token.mint(depositAmount);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount);
        vm.stopPrank();
        _checkState(
            State({
                userShares: depositAmount * DEAD_SHARES,
                masterVaultTotalAssets: depositAmount + 1,
                masterVaultTotalSupply: (1 + depositAmount) * DEAD_SHARES,
                masterVaultTokenBalance: depositAmount,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        assertEq(shares, depositAmount * DEAD_SHARES, "shares mismatch deposit return value");
    }

    function test_redeem(uint96 _firstDeposit, uint96 _redeemAmount) public {
        uint256 firstDeposit = _firstDeposit;
        uint256 redeemAmount = _redeemAmount;
        vm.assume(redeemAmount <= firstDeposit * DEAD_SHARES);
        test_deposit(_firstDeposit);
        State memory beforeState = _getState();
        vm.startPrank(user);
        uint256 assets = vault.redeem(redeemAmount, 0);
        uint256 expectedAssets = (beforeState.masterVaultTotalAssets * redeemAmount)
            / (beforeState.masterVaultTotalSupply);
        vm.stopPrank();
        _checkState(
            State({
                userShares: beforeState.userShares - redeemAmount,
                masterVaultTotalAssets: beforeState.masterVaultTotalAssets - expectedAssets,
                masterVaultTotalSupply: beforeState.masterVaultTotalSupply - redeemAmount,
                masterVaultTokenBalance: beforeState.masterVaultTokenBalance - expectedAssets,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        assertEq(assets, expectedAssets, "assets mismatch redeem return value");
    }
}

contract MasterVaultTestWithSubvaultFresh is MasterVaultFirstDepositTest {
    function setUp() public override {
        super.setUp();
        MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");

        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.setSubVaultWhitelist(address(_subvault), true);
        vault.setSubVault(IERC4626(address(_subvault)));
    }
}

contract MasterVaultTestWithSubvaultHoldingAssets is MasterVaultFirstDepositTest {
    function _setupSubvaultWithAssets(uint256 _initAmount) internal {
        MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
        token.mint(_initAmount);
        token.approve(address(_subvault), _initAmount);
        _subvault.deposit(_initAmount, address(this));
        assertEq(
            _initAmount,
            _subvault.totalAssets(),
            "subvault should be initiated with assets = _initAmount"
        );
        assertEq(
            _initAmount,
            _subvault.totalSupply(),
            "subvault should be initiated with shares = _initAmount"
        );

        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.setSubVaultWhitelist(address(_subvault), true);
        vault.setSubVault(IERC4626(address(_subvault)));
    }

    function test_deposit(uint96 _depositAmount, uint96 _initAmount) public {
        uint256 depositAmount = _depositAmount;
        uint256 initAmount = _initAmount;
        _setupSubvaultWithAssets(initAmount);

        vm.startPrank(user);
        token.mint(depositAmount);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount);
        vm.stopPrank();
        _checkState(
            State({
                userShares: depositAmount * DEAD_SHARES,
                masterVaultTotalAssets: depositAmount + 1,
                masterVaultTotalSupply: (1 + depositAmount) * DEAD_SHARES,
                masterVaultTokenBalance: depositAmount,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: initAmount,
                subVaultTotalSupply: initAmount,
                subVaultTokenBalance: initAmount
            })
        );
        assertEq(shares, depositAmount * DEAD_SHARES, "shares mismatch deposit return value");
    }

    function test_redeem(uint96 _firstDeposit, uint96 _redeemAmount, uint96 _initAmount) public {
        uint256 firstDeposit = _firstDeposit;
        uint256 redeemAmount = _redeemAmount;
        vm.assume(redeemAmount <= firstDeposit * DEAD_SHARES);
        test_deposit(_firstDeposit, _initAmount);
        State memory beforeState = _getState();
        vm.startPrank(user);
        uint256 assets = vault.redeem(redeemAmount, 0);
        uint256 expectedAssets = (beforeState.masterVaultTotalAssets * redeemAmount)
            / (beforeState.masterVaultTotalSupply);
        vm.stopPrank();
        _checkState(
            State({
                userShares: beforeState.userShares - redeemAmount,
                masterVaultTotalAssets: beforeState.masterVaultTotalAssets - expectedAssets,
                masterVaultTotalSupply: beforeState.masterVaultTotalSupply - redeemAmount,
                masterVaultTokenBalance: beforeState.masterVaultTokenBalance - expectedAssets,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: beforeState.subVaultTotalAssets,
                subVaultTotalSupply: beforeState.subVaultTotalSupply,
                subVaultTokenBalance: beforeState.subVaultTokenBalance
            })
        );
        assertEq(assets, expectedAssets, "assets mismatch redeem return value");
    }
}
