// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { MasterVaultCoreTest } from "./MasterVaultCore.t.sol";
import { MockSubVault } from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract MasterVaultFirstDepositTest is MasterVaultCoreTest {
    using Math for uint256;

    uint256 constant DEAD_SHARES = 10 ** 18;

    // first deposit
    function test_deposit(uint96 _depositAmount) public {
        uint256 depositAmount = _depositAmount;
        vm.startPrank(user);
        token.mint(depositAmount);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();
        _checkState(
            State({
                userShares: depositAmount * DEAD_SHARES,
                masterVaultTotalAssets: depositAmount,
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

    function test_mint(uint96 _mintAmount) public {
        uint256 mintAmount = _mintAmount;
        vm.startPrank(user);
        token.mint(mintAmount);
        token.approve(address(vault), mintAmount);
        uint256 assets = vault.mint(mintAmount, user);
        vm.stopPrank();
        _checkState(
            State({
                userShares: mintAmount,
                masterVaultTotalAssets: mintAmount.ceilDiv(1e18),
                masterVaultTotalSupply: mintAmount + DEAD_SHARES,
                masterVaultTokenBalance: mintAmount.ceilDiv(1e18),
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        assertEq(assets, mintAmount.ceilDiv(1e18), "assets mismatch mint return value");
    }

    function test_withdraw(uint96 _firstDeposit, uint96 _withdrawAmount) public {
        uint256 firstDeposit = _firstDeposit;
        uint256 withdrawAmount = _withdrawAmount;
        vm.assume(withdrawAmount <= firstDeposit);
        test_deposit(_firstDeposit);
        vm.startPrank(user);
        uint256 sharesRedeemed = vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();
        _checkState(
            State({
                userShares: (firstDeposit - withdrawAmount) * DEAD_SHARES,
                masterVaultTotalAssets: firstDeposit - withdrawAmount,
                masterVaultTotalSupply: (1 + firstDeposit - withdrawAmount) * DEAD_SHARES,
                masterVaultTokenBalance: firstDeposit - withdrawAmount,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        assertEq(
            sharesRedeemed,
            withdrawAmount * DEAD_SHARES,
            "sharesRedeemed mismatch withdraw return value"
        );
    }

    function test_redeem(uint96 _firstMint, uint96 _redeemAmount) public {
        uint256 firstMint = _firstMint;
        uint256 redeemAmount = _redeemAmount;
        vm.assume(redeemAmount <= firstMint);
        test_mint(_firstMint);
        State memory beforeState = _getState();
        vm.startPrank(user);
        uint256 assets = vault.redeem(redeemAmount, user, user);
        uint256 expectedAssets = ((1 + beforeState.masterVaultTotalAssets) * redeemAmount) /
            (beforeState.masterVaultTotalSupply);
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

// contract MasterVaultTestWithSubvaultFresh is MasterVaultFirstDepositTest {
//     function setUp() public override {
//         super.setUp();
//         MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
//         vault.setSubVault(IERC4626(address(_subvault)));
//     }
// }

// contract MasterVaultTestWithSubvaultHoldingAssets is MasterVaultFirstDepositTest {
//     function setUp() public override {
//         super.setUp();

//         MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
//         uint256 _initAmount = 97659743;
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
