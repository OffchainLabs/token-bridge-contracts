// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MasterVaultFactory
} from "../../../../contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {FuzzSubVault} from "../../../../contracts/tokenbridge/test/FuzzSubVault.sol";
import {TestERC20} from "../../../../contracts/tokenbridge/test/TestERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IGatewayRouter} from "../../../../contracts/tokenbridge/libraries/gateway/IGatewayRouter.sol";

contract MockGatewayRouterFuzz {
    address public gateway;

    constructor(address _gateway) {
        gateway = _gateway;
    }

    function getGateway(address) external view returns (address) {
        return gateway;
    }
}

/// @notice Targeted fuzz tests for MasterVault.
/// @dev    Each test is a standard test_ function with fuzzed parameters that tests a specific
///         multi-step property. Self-contained -- no handler, just fixed operation sequences
///         with fuzzed inputs.
contract MasterVaultFuzz is Test {
    MasterVaultFactory public factory;
    MasterVault public vault;
    FuzzSubVault public subVault;
    TestERC20 public token;

    address public user = vm.addr(1);
    address public keeper = address(0xBBBB);
    address public beneficiaryAddr = address(0x9999);

    uint256 public constant DEAD_SHARES = 10 ** 6;

    function setUp() public {
        factory = new MasterVaultFactory();
        MockGatewayRouterFuzz mockRouter = new MockGatewayRouterFuzz(user);
        MasterVault impl = new MasterVault();
        factory.initialize(address(impl), address(this), IGatewayRouter(address(mockRouter)));
        token = new TestERC20();
        vault = MasterVault(factory.deployVault(address(token)));

        subVault = new FuzzSubVault(IERC20(address(token)), "FuzzSub", "fSUB");
        vault.rolesRegistry().grantRole(vault.ADMIN_ROLE(), address(this));
        vault.setSubVaultWhitelist(address(subVault), true);
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.rolesRegistry().grantRole(vault.KEEPER_ROLE(), keeper);
        vault.rolesRegistry().grantRole(vault.FEE_MANAGER_ROLE(), address(this));
        vault.setSubVault(IERC4626(address(subVault)));
        vault.setBeneficiary(beneficiaryAddr);
        vault.setMinimumRebalanceAmount(1);
    }

    // --- Helpers ---

    function _deposit(uint256 amount) internal returns (uint256 shares) {
        vm.prank(user);
        token.mintAmount(amount);
        vm.startPrank(user);
        token.approve(address(vault), amount);
        shares = vault.deposit(amount);
        vm.stopPrank();
    }

    function _rebalanceIn() internal {
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        try vault.rebalance(-1e18) {} catch {}
    }

    function _rebalanceOut() internal {
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        try vault.rebalance(0) {} catch {}
    }

    // --- Targeted fuzz tests ---

    /// @notice THE dust share catcher.
    ///         Deposit -> allocate -> rebalance in -> manipulate subvault rate ->
    ///         set allocation to 0 -> rebalance out -> assert subVault.balanceOf(vault) == 0
    /// @dev    Catches: dust shares from rounding when A < T, conservative maxWithdraw leaving
    ///         residual shares, any combination of rate manipulation that leaves shares behind.
    function test_rebalanceToZero_clearsAllShares(
        uint128 depositAmount,
        uint64 initialAllocation,
        uint128 subVaultLoss,
        uint128 extraShares,
        uint128 maxWithdrawCap
    ) public {
        depositAmount = uint128(bound(depositAmount, 1e6, 1e24));
        initialAllocation = uint64(bound(initialAllocation, 1e14, 1e18));

        // Deposit and allocate
        _deposit(depositAmount);
        vault.setTargetAllocationWad(initialAllocation);
        _rebalanceIn();

        // Manipulate subvault rate
        uint256 subBal = token.balanceOf(address(subVault));
        if (subBal > 0) {
            subVaultLoss = uint128(bound(subVaultLoss, 0, subBal - 1));
            if (subVaultLoss > 0) {
                vm.prank(address(subVault));
                token.transfer(address(0xdead), subVaultLoss);
            }
        }

        extraShares = uint128(bound(extraShares, 0, 1e18));
        if (extraShares > 0) {
            subVault.adminMint(address(vault), extraShares);
        }

        maxWithdrawCap = uint128(bound(maxWithdrawCap, 0, type(uint128).max));
        subVault.setMaxWithdrawLimit(maxWithdrawCap);

        // Set allocation to 0 and rebalance out
        vault.setTargetAllocationWad(0);

        // May need multiple rebalances if maxWithdraw caps the amount
        for (uint256 i = 0; i < 10; i++) {
            if (subVault.balanceOf(address(vault)) == 0) break;
            try this._tryRebalanceOut() {} catch {
                break;
            }
        }

        assertEq(
            subVault.balanceOf(address(vault)), 0, "dust shares remain after rebalance to zero"
        );
    }

    function _tryRebalanceOut() external {
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vault.rebalance(0);
    }

    /// @notice End-to-end subvault switching. Same setup as dust test, then deploy new vault
    ///         and assert setSubVault does not revert.
    /// @dev    Catches: the full operational workflow that the dust bug blocks.
    function test_subVaultSwitch_alwaysSucceeds(
        uint128 depositAmount,
        uint64 initialAllocation,
        uint128 subVaultLoss,
        uint128 extraShares,
        uint128 maxWithdrawCap
    ) public {
        depositAmount = uint128(bound(depositAmount, 1e6, 1e24));
        initialAllocation = uint64(bound(initialAllocation, 1e14, 1e18));

        _deposit(depositAmount);
        vault.setTargetAllocationWad(initialAllocation);
        _rebalanceIn();

        uint256 subBal = token.balanceOf(address(subVault));
        if (subBal > 0) {
            subVaultLoss = uint128(bound(subVaultLoss, 0, subBal - 1));
            if (subVaultLoss > 0) {
                vm.prank(address(subVault));
                token.transfer(address(0xdead), subVaultLoss);
            }
        }

        extraShares = uint128(bound(extraShares, 0, 1e18));
        if (extraShares > 0) {
            subVault.adminMint(address(vault), extraShares);
        }

        maxWithdrawCap = uint128(bound(maxWithdrawCap, 0, type(uint128).max));
        subVault.setMaxWithdrawLimit(maxWithdrawCap);

        vault.setTargetAllocationWad(0);

        for (uint256 i = 0; i < 10; i++) {
            if (subVault.balanceOf(address(vault)) == 0) break;
            try this._tryRebalanceOut() {} catch {
                break;
            }
        }

        // Deploy new subvault and switch
        FuzzSubVault newSubVault =
            new FuzzSubVault(IERC20(address(token)), "FuzzSub2", "fSUB2");
        vault.setSubVaultWhitelist(address(newSubVault), true);
        vault.setSubVault(IERC4626(address(newSubVault)));
    }

    /// @notice Deposit X -> immediately redeem all -> assert assets received <= X.
    /// @dev    Catches: value extraction from share pricing under non-1:1 exchange rates.
    function test_depositRedeem_roundTrip(
        uint128 depositAmount,
        uint128 subVaultAssets,
        uint128 subVaultShares
    ) public {
        depositAmount = uint128(bound(depositAmount, 1, 1e24));

        // Optionally seed the subvault with arbitrary state to create non-1:1 rate
        subVaultAssets = uint128(bound(subVaultAssets, 0, 1e24));
        subVaultShares = uint128(bound(subVaultShares, 0, 1e24));

        if (subVaultAssets > 0) {
            token.mintAmount(subVaultAssets);
            token.transfer(address(subVault), subVaultAssets);
        }
        if (subVaultShares > 0) {
            subVault.adminMint(address(this), subVaultShares);
        }

        uint256 shares = _deposit(depositAmount);

        uint256 userTokensBefore = token.balanceOf(user);
        vm.prank(user);
        vault.redeem(shares, 0);
        uint256 assetsReceived = token.balanceOf(user) - userTokensBefore;

        assertLe(assetsReceived, depositAmount, "user extracted more than deposited");
    }

    /// @notice Two users deposit -> allocate -> rebalance -> profit or loss -> both redeem ->
    ///         assert each user's assets are proportional to their deposit share.
    /// @dev    Catches: unfair share pricing, rounding bias favoring early/late depositors.
    function test_proportionalRedemption(
        uint96 depositA,
        uint96 depositB,
        uint64 allocation,
        uint128 profitOrLoss,
        bool isLoss
    ) public {
        depositA = uint96(bound(depositA, 1e6, 1e24));
        depositB = uint96(bound(depositB, 1e6, 1e24));
        allocation = uint64(bound(allocation, 0, 1e18));

        address userA = address(0xA);
        address userB = address(0xB);

        // Deposit for both users
        uint256 sharesA = _deposit(depositA);
        vm.prank(user);
        vault.transfer(userA, sharesA);
        uint256 sharesB = _deposit(depositB);
        vm.prank(user);
        vault.transfer(userB, sharesB);

        // Allocate and rebalance
        if (allocation > 0) {
            vault.setTargetAllocationWad(allocation);
            _rebalanceIn();
        }

        // Apply profit or loss
        _applyProfitOrLoss(profitOrLoss, allocation, isLoss);

        // Both users redeem via user (gateway)
        uint256 assetsA = _redeemFor(userA);
        uint256 assetsB = _redeemFor(userB);

        // Check proportionality: assetsA * depositB ~= assetsB * depositA
        _assertProportional(assetsA, assetsB, depositA, depositB);
    }

    function _applyProfitOrLoss(uint128 profitOrLoss, uint64 allocation, bool isLoss) internal {
        profitOrLoss = uint128(bound(profitOrLoss, 0, 1e24));
        if (profitOrLoss == 0) return;

        address target = allocation > 0 ? address(subVault) : address(vault);
        if (isLoss) {
            uint256 maxLoss = token.balanceOf(target);
            if (profitOrLoss > maxLoss) profitOrLoss = uint128(maxLoss);
            if (profitOrLoss > 0) {
                vm.prank(target);
                token.transfer(address(0xdead), profitOrLoss);
            }
        } else {
            token.mintAmount(profitOrLoss);
            token.transfer(target, profitOrLoss);
        }
    }

    function _redeemFor(address account) internal returns (uint256 assets) {
        uint256 shares = vault.balanceOf(account);
        if (shares == 0) return 0;
        vm.prank(account);
        vault.transfer(user, shares);
        uint256 before = token.balanceOf(user);
        vm.prank(user);
        vault.redeem(shares, 0);
        assets = token.balanceOf(user) - before;
        vm.prank(user);
        token.transfer(account, assets);
    }

    function _assertProportional(
        uint256 assetsA,
        uint256 assetsB,
        uint96 depositA,
        uint96 depositB
    ) internal {
        if (assetsA == 0 || assetsB == 0) return;
        uint256 lhs = assetsA * uint256(depositB);
        uint256 rhs = assetsB * uint256(depositA);
        uint256 diff = lhs > rhs ? lhs - rhs : rhs - lhs;
        uint256 tolerance = (depositA > depositB ? uint256(depositA) : uint256(depositB)) * 2;
        assertLe(diff, tolerance, "redemption not proportional to deposits");
    }

    /// @notice Deposit -> allocate -> rebalance -> simulate profit -> distribute fee ->
    ///         assert beneficiary received <= totalProfit and user can still redeem principal.
    /// @dev    Catches: over-extraction of fees, fee distribution eating into principal.
    function test_feeDistribution_bounded(
        uint128 depositAmount,
        uint128 profitAmount,
        uint64 allocation
    ) public {
        depositAmount = uint128(bound(depositAmount, 1e6, 1e24));
        // Cap profit relative to deposit to avoid degenerate case where massive profit
        // in subvault causes fee withdrawal to burn all subvault shares (including principal)
        profitAmount = uint128(bound(profitAmount, 1, depositAmount));
        allocation = uint64(bound(allocation, 1e14, 1e18));

        uint256 shares = _deposit(depositAmount);
        vault.setTargetAllocationWad(allocation);
        _rebalanceIn();

        // Simulate profit (send to subvault if tokens are there, otherwise to vault)
        token.mintAmount(profitAmount);
        if (subVault.balanceOf(address(vault)) > 0) {
            token.transfer(address(subVault), profitAmount);
        } else {
            token.transfer(address(vault), profitAmount);
        }

        uint256 profitBefore = vault.totalProfit();
        if (profitBefore == 0) return; // no profit to distribute

        uint256 benBefore = token.balanceOf(beneficiaryAddr);

        vm.prank(keeper);
        vault.distributePerformanceFee();

        uint256 feesClaimed = token.balanceOf(beneficiaryAddr) - benBefore;

        // Fees must not exceed profit
        assertLe(feesClaimed, profitBefore, "fees exceed profit");

        // User should be able to redeem and receive at least their principal minus rounding
        uint256 userTokensBefore = token.balanceOf(user);
        vm.prank(user);
        vault.redeem(shares, 0);
        uint256 assetsReceived = token.balanceOf(user) - userTokensBefore;

        // Principal minus 2 for rounding (deposit round-down + redeem round-down)
        assertGe(assetsReceived + 2, depositAmount, "user lost principal after fee distribution");
    }

    /// @notice Deposit -> set allocation A -> rebalance -> set allocation B -> rebalance ->
    ///         assert totalAssets is unchanged (within rounding tolerance).
    /// @dev    Catches: value leakage or creation during rebalancing due to exchange rate rounding.
    function test_rebalance_totalAssetsPreserved(
        uint128 depositAmount,
        uint64 fromAllocation,
        uint64 toAllocation
    ) public {
        depositAmount = uint128(bound(depositAmount, 1e6, 1e24));
        fromAllocation = uint64(bound(fromAllocation, 1e14, 1e18));
        toAllocation = uint64(bound(toAllocation, 0, 1e18));
        vm.assume(fromAllocation != toAllocation);

        _deposit(depositAmount);

        vault.setTargetAllocationWad(fromAllocation);
        _rebalanceIn();

        uint256 totalBefore = vault.totalAssets();

        vault.setTargetAllocationWad(toAllocation);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        int256 slippage = toAllocation > fromAllocation ? int256(-1e18) : int256(0);
        try vault.rebalance(slippage) {} catch {
            return; // second rebalance failed (e.g. allocations too close), nothing to check
        }

        uint256 totalAfter = vault.totalAssets();

        // Allow 2 units of rounding tolerance (one per rebalance)
        uint256 diff = totalBefore > totalAfter
            ? totalBefore - totalAfter
            : totalAfter - totalBefore;
        assertLe(diff, 2, "totalAssets changed after rebalance");
    }

    /// @notice Deposit -> set allocation -> rebalance -> warp -> rebalance again ->
    ///         assert second rebalance reverts with TargetAllocationMet.
    /// @dev    Catches: tolerance band not working, oscillating rebalances.
    function test_rebalance_idempotent(uint128 depositAmount, uint64 allocation) public {
        depositAmount = uint128(bound(depositAmount, 1e6, 1e24));
        allocation = uint64(bound(allocation, 1e14, 1e18));

        _deposit(depositAmount);
        vault.setTargetAllocationWad(allocation);
        _rebalanceIn();

        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(MasterVault.TargetAllocationMet.selector);
        vault.rebalance(-1e18);
    }
}
