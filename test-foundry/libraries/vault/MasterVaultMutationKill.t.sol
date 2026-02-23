// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest, MockGatewayRouter} from "./MasterVaultCore.t.sol";
import {MasterVault} from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MasterVaultRoles
} from "../../../contracts/tokenbridge/libraries/vault/MasterVaultRoles.sol";
import {
    DefaultSubVault,
    MasterVaultFactory
} from "../../../contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {MockSubVault} from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import {TestERC20} from "../../../contracts/tokenbridge/test/TestERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IGatewayRouter} from "../../../contracts/tokenbridge/libraries/gateway/IGatewayRouter.sol";
import {Test, Vm} from "forge-std/Test.sol";

contract MasterVaultMutationKillTest is MasterVaultCoreTest {
    address public keeper = address(0xBBBB);
    address public beneficiaryAddr = address(0x9999);
    address public generalManager = address(0xAAAA);
    address public pauser = address(0xCCCC);

    function setUp() public override {
        super.setUp();
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), generalManager);
        vault.rolesRegistry().grantRole(vault.KEEPER_ROLE(), keeper);
        vault.rolesRegistry().grantRole(vault.FEE_MANAGER_ROLE(), address(this));
        vault.rolesRegistry().grantRole(vault.PAUSER_ROLE(), pauser);
        vault.setBeneficiary(beneficiaryAddr);
        vault.setMinimumRebalanceAmount(1);
    }

    function _depositAs(uint256 amount) internal returns (uint256) {
        vm.prank(user);
        token.mintAmount(amount);
        vm.startPrank(user);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount);
        vm.stopPrank();
        return shares;
    }

    function _setupWithAllocation(uint256 depositAmount, uint64 allocationWad) internal {
        _depositAs(depositAmount);
        vault.setTargetAllocationWad(allocationWad);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vault.rebalance(-1e18);
    }

    // ====== MasterVaultRoles.sol ======

    /// TARGETS MUTANT #6 in MasterVaultRoles.sol
    function test_initRoles_accessControlEnumerableInit() public {
        assertTrue(vault.supportsInterface(type(IAccessControlUpgradeable).interfaceId));
    }

    // ====== MasterVaultFactory.sol (DefaultSubVault) ======

    /// TARGETS MUTANT #5 in MasterVaultFactory.sol
    function test_defaultSubVault_withdraw_onlyMasterVault() public {
        DefaultSubVault dsv = DefaultSubVault(address(vault.subVault()));
        address attacker = address(0xdead);
        vm.prank(attacker);
        vm.expectRevert("ONLY_MASTER_VAULT");
        dsv.withdraw(1, attacker, attacker);
    }

    /// TARGETS MUTANT #6 in MasterVaultFactory.sol
    function test_defaultSubVault_withdraw_requireTrue_onlyMasterVault() public {
        DefaultSubVault dsv = DefaultSubVault(address(vault.subVault()));
        vm.prank(address(vault));
        // should not revert when called by masterVault (with 0 amount)
        dsv.withdraw(0, address(vault), address(vault));
    }

    /// TARGETS MUTANT #8 in MasterVaultFactory.sol
    function test_defaultSubVault_mint_reverts() public {
        DefaultSubVault dsv = DefaultSubVault(address(vault.subVault()));
        vm.expectRevert("UNSUPPORTED");
        dsv.mint(1, address(this));
    }

    /// TARGETS MUTANT #9 in MasterVaultFactory.sol
    function test_defaultSubVault_redeem_reverts() public {
        DefaultSubVault dsv = DefaultSubVault(address(vault.subVault()));
        vm.expectRevert("UNSUPPORTED");
        dsv.redeem(1, address(this), address(this));
    }

    // ====== MasterVault.sol - initialize ======

    /// TARGETS MUTANT #1 in MasterVault.sol
    function test_initialize_setsERC20Name() public {
        string memory n = vault.name();
        assertTrue(bytes(n).length > 0, "name should be set");
    }

    /// TARGETS MUTANT #4 in MasterVault.sol
    function test_initialize_callsDecimals() public {
        assertEq(vault.decimals(), 18 + 6, "decimals should be underlying + EXTRA_DECIMALS");
    }

    /// TARGETS MUTANT #5 in MasterVault.sol
    function test_initialize_reentrancyGuard() public {
        // Deposit involves nonReentrant; if guard wasn't initialized, it would be in wrong state
        _depositAs(1e18);
    }

    /// TARGETS MUTANT #6 in MasterVault.sol
    function test_initialize_pausableInit() public {
        assertFalse(vault.paused(), "vault should not be paused initially");
        vm.prank(pauser);
        vault.pause();
        assertTrue(vault.paused(), "vault should be paused after pause()");
    }

    /// TARGETS MUTANT #17 in MasterVault.sol
    function test_initialize_setsSubVaultWhitelist() public {
        assertTrue(
            vault.isSubVaultWhitelisted(address(vault.subVault())),
            "initial subVault should be whitelisted"
        );
    }

    /// TARGETS MUTANT #18 in MasterVault.sol
    function test_initialize_minimumRebalanceAmount() public {
        assertEq(
            vault.minimumRebalanceAmount(),
            1, // we set it to 1 in setUp, but let's check on a fresh vault
            "minimumRebalanceAmount after setUp"
        );
        // Deploy a fresh vault to check default
        MasterVault freshVault = MasterVault(factory.deployVault(address(new TestERC20())));
        assertEq(
            freshVault.minimumRebalanceAmount(),
            freshVault.DEFAULT_MIN_REBALANCE_AMOUNT(),
            "default minimumRebalanceAmount"
        );
    }

    /// TARGETS MUTANT #19 in MasterVault.sol
    function test_initialize_minimumRebalanceAmount_notZero() public {
        MasterVault freshVault = MasterVault(factory.deployVault(address(new TestERC20())));
        assertTrue(freshVault.minimumRebalanceAmount() > 0, "minimumRebalanceAmount should not be 0");
    }

    /// TARGETS MUTANT #20 in MasterVault.sol
    function test_initialize_minimumRebalanceAmount_notOne() public {
        MasterVault freshVault = MasterVault(factory.deployVault(address(new TestERC20())));
        assertEq(freshVault.minimumRebalanceAmount(), 1e6, "minimumRebalanceAmount should be 1e6");
    }

    /// TARGETS MUTANT #21 in MasterVault.sol
    function test_initialize_rebalanceCooldown() public {
        MasterVault freshVault = MasterVault(factory.deployVault(address(new TestERC20())));
        assertEq(
            freshVault.rebalanceCooldown(),
            freshVault.MIN_REBALANCE_COOLDOWN(),
            "default rebalanceCooldown"
        );
    }

    /// TARGETS MUTANT #22 in MasterVault.sol
    function test_initialize_rebalanceCooldown_notZero() public {
        MasterVault freshVault = MasterVault(factory.deployVault(address(new TestERC20())));
        assertTrue(freshVault.rebalanceCooldown() > 0, "rebalanceCooldown should not be 0");
    }

    /// TARGETS MUTANT #23 in MasterVault.sol
    function test_initialize_rebalanceCooldown_equalsMinCooldown() public {
        MasterVault freshVault = MasterVault(factory.deployVault(address(new TestERC20())));
        assertEq(freshVault.rebalanceCooldown(), 1, "rebalanceCooldown should be MIN_REBALANCE_COOLDOWN = 1");
    }

    // ====== redeem minAssets slippage ======

    /// TARGETS MUTANT #37 in MasterVault.sol
    function test_redeem_minAssets_reverts() public {
        uint256 shares = _depositAs(1e18);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.InsufficientAssets.selector, 1e18, 2e18)
        );
        vault.redeem(shares, 2e18);
    }

    /// TARGETS MUTANT #38 in MasterVault.sol
    function test_redeem_minAssets_swapArgs_gt0() public {
        uint256 shares = _depositAs(1e18);
        vm.prank(user);
        // minAssets=1 should pass since assets >= 1
        vault.redeem(shares, 1);
    }

    /// TARGETS MUTANT #39 in MasterVault.sol
    function test_redeem_minAssets_swapedComparison() public {
        uint256 shares = _depositAs(1e18);
        // Request minAssets just above what we'd get
        vm.prank(user);
        vm.expectRevert();
        vault.redeem(shares, 1e18 + 1);
    }

    // ====== rebalance cooldown ======

    /// TARGETS MUTANT #52, #56 in MasterVault.sol
    function test_rebalance_cooldownMath() public {
        _depositAs(10e18);
        vault.setTargetAllocationWad(3e17); // 30% allocation
        vault.setRebalanceCooldown(10);
        // Rebalance at t=100 (deposits ~30% of assets to subvault)
        vm.warp(100);
        vm.prank(keeper);
        vault.rebalance(-1e18);
        // Increase allocation so there's more to deposit
        vault.setTargetAllocationWad(8e17);
        // Warp only 5s (less than 10s cooldown)
        vm.warp(105);
        // With mutant #52 (+): timeSinceLastRebalance = 105+100=205 >= 10, no cooldown revert
        // With correct code (-): timeSinceLastRebalance = 105-100=5 < 10, cooldown revert
        vm.prank(keeper);
        vm.expectRevert();
        vault.rebalance(-1e18);
    }

    /// TARGETS MUTANT #59 in MasterVault.sol
    function test_rebalance_cooldownEnforced() public {
        _depositAs(10e18);
        vault.setTargetAllocationWad(3e17); // 30%
        vault.setRebalanceCooldown(100);
        vm.warp(block.timestamp + 101);
        vm.prank(keeper);
        vault.rebalance(-1e18);
        // Increase allocation so second rebalance is also a deposit
        vault.setTargetAllocationWad(8e17);
        // Warp only 50s (less than 100 cooldown)
        vm.warp(block.timestamp + 50);
        vm.prank(keeper);
        vm.expectRevert();
        vault.rebalance(-1e18);
    }

    // ====== rebalance TargetAllocationMet ======

    /// TARGETS MUTANT #74 in MasterVault.sol
    function test_rebalance_targetAllocationMet_reverts() public {
        _setupWithAllocation(1e18, 5e17);
        // Rebalance again with same allocation - should be met now
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(MasterVault.TargetAllocationMet.selector);
        vault.rebalance(0);
    }

    // ====== rebalance exchRate wrong sign (withdraw path) ======

    /// TARGETS MUTANT #102 in MasterVault.sol
    function test_rebalance_withdraw_negativeExchRate_reverts() public {
        _setupWithAllocation(10e18, 8e17);
        vault.setTargetAllocationWad(2e17);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.RebalanceExchRateWrongSign.selector, int256(-1))
        );
        vault.rebalance(-1);
    }

    /// TARGETS MUTANT #103 in MasterVault.sol
    function test_rebalance_withdraw_zeroExchRate_succeeds() public {
        _setupWithAllocation(10e18, 8e17);
        vault.setTargetAllocationWad(2e17);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vault.rebalance(0);
    }

    // ====== rebalance withdraw desiredWithdraw math ======

    /// TARGETS MUTANT #104, #105 in MasterVault.sol
    function test_rebalance_withdraw_correctAmount() public {
        _setupWithAllocation(10e18, 8e17); // 80% to subvault

        uint256 idleBefore = token.balanceOf(address(vault));
        uint256 totalAssetsBefore = vault.totalAssets();

        vault.setTargetAllocationWad(2e17); // 20% to subvault, want more idle
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vault.rebalance(0);

        uint256 idleAfter = token.balanceOf(address(vault));
        // idle should be approximately 80% of total assets now
        // With mutant #104 (+), desiredWithdraw would be idleTarget + idle (huge), capped by maxWithdrawable
        // With mutant #105 (*), desiredWithdraw would be idleTarget * idle (huge), capped by maxWithdrawable
        // Both would withdraw too much, leaving much more idle than expected
        uint256 idleTarget80pct = totalAssetsBefore * 80 / 100;
        assertTrue(idleAfter <= idleTarget80pct + 1, "idle should be near 80% of total, not more");
    }

    // ====== rebalance withdraw minimumRebalanceAmount ======

    /// TARGETS MUTANT #112 in MasterVault.sol
    function test_rebalance_withdraw_tooSmall_reverts() public {
        _setupWithAllocation(10e18, 5e17);

        vault.setMinimumRebalanceAmount(100e18); // huge minimum
        vault.setTargetAllocationWad(49e16); // tiny change to trigger small withdraw
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert();
        vault.rebalance(0);
    }

    // ====== rebalance withdraw exchRate check ======

    /// TARGETS MUTANT #115 in MasterVault.sol
    function test_rebalance_withdraw_exchRateTooLow_reverts() public {
        _setupWithAllocation(10e18, 8e17);
        vault.setTargetAllocationWad(2e17);
        vm.warp(block.timestamp + 2);
        // Pass a very high minExchRateWad so the exchange rate check fails
        vm.prank(keeper);
        vm.expectRevert();
        vault.rebalance(int256(100e18));
    }

    // ====== rebalance deposit exchRate wrong sign ======

    /// TARGETS MUTANT #81 in MasterVault.sol
    function test_rebalance_deposit_positiveExchRate_reverts() public {
        _depositAs(1e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.RebalanceExchRateWrongSign.selector, int256(1))
        );
        vault.rebalance(1);
    }

    // ====== rebalance deposit minimumRebalanceAmount ======

    /// TARGETS MUTANT #91 in MasterVault.sol
    function test_rebalance_deposit_tooSmall_reverts() public {
        _depositAs(10e18);
        vault.setMinimumRebalanceAmount(100e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vm.expectRevert();
        vault.rebalance(-1e18);
    }

    // ====== rebalance deposit exchRate check ======

    /// TARGETS MUTANT #95, #97, #98, #99, #100 in MasterVault.sol
    function test_rebalance_deposit_exchRatePasses() public {
        _depositAs(10e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        // -1e18 means 1:1 exchange rate tolerance. For a 1:1 subvault this should pass.
        // With #97 (++minExchRateWad): -(-1e18+1) = 999999999999999999, actualRate=1e18 > 999999999999999999 → reverts
        // With #100 (~minExchRateWad): ~(-1e18) = 1e18-1, actualRate=1e18 > 1e18-1 → reverts
        vm.prank(keeper);
        vault.rebalance(-1e18);
    }

    /// TARGETS MUTANT #95 in MasterVault.sol
    function test_rebalance_deposit_exchRate_tooStrict_reverts() public {
        _depositAs(10e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        // Pass -1 (tolerance of 1 wei per share) - actual rate is 1e18, so 1e18 > 1 reverts
        vm.prank(keeper);
        vm.expectRevert();
        vault.rebalance(-1);
    }

    /// TARGETS MUTANT #100 in MasterVault.sol — verify exact revert args for deposit exchRate
    function test_rebalance_deposit_exchRate_revertExactArgs() public {
        _depositAs(10e18);
        vault.setTargetAllocationWad(5e17);
        vm.warp(block.timestamp + 2);
        // Use -2 so uint256(-(-2)) = 2. actualExchRate=1e18 > 2, should revert.
        // Replicate the contract's exact math to predict depositAmount:
        uint256 idleBalance = token.balanceOf(address(vault));
        // totalAssetsUp uses Rounding.Up for previewMint (subvault has 0 shares so it's just 1+idle)
        uint256 totalAssetsUp = 1 + idleBalance; // no subvault shares yet
        uint64 alloc = vault.targetAllocationWad();
        uint256 idleTargetUp = (totalAssetsUp * (1e18 - alloc) + 1e18 - 1) / 1e18; // round up
        uint256 desiredDeposit = idleBalance - idleTargetUp;
        uint256 maxDepositable = vault.subVault().maxDeposit(address(vault));
        uint256 depositAmount = desiredDeposit < maxDepositable ? desiredDeposit : maxDepositable;
        // Normal: RebalanceExchRateTooLow(-2, -int256(depositAmount), depositAmount)
        // Mutant #100: ~int256(depositAmount) = -(depositAmount+1) instead of -depositAmount
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                MasterVault.RebalanceExchRateTooLow.selector,
                int256(-2),
                -int256(depositAmount),
                depositAmount
            )
        );
        vault.rebalance(-2);
    }

    // ====== lastRebalanceTime ======

    /// TARGETS MUTANT #117, #118, #119 in MasterVault.sol
    function test_rebalance_updatesLastRebalanceTime() public {
        _depositAs(1e18);
        vault.setTargetAllocationWad(5e17);
        uint256 rebalanceTime = block.timestamp + 100;
        vm.warp(rebalanceTime);
        vm.prank(keeper);
        vault.rebalance(-1e18);
        assertEq(vault.lastRebalanceTime(), rebalanceTime, "lastRebalanceTime should be updated");
    }

    // ====== setSubVault ======

    /// TARGETS MUTANT #122 in MasterVault.sol
    function test_setSubVault_nonWhitelisted_reverts() public {
        MockSubVault newSv = new MockSubVault(IERC20(address(token)), "New", "NEW");
        vm.prank(generalManager);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.SubVaultNotWhitelisted.selector, address(newSv))
        );
        vault.setSubVault(IERC4626(address(newSv)));
    }

    /// TARGETS MUTANT #124 in MasterVault.sol
    function test_setSubVault_wrongAsset_reverts() public {
        TestERC20 otherToken = new TestERC20();
        MockSubVault wrongAssetSv = new MockSubVault(IERC20(address(otherToken)), "Wrong", "WRG");
        vault.setSubVaultWhitelist(address(wrongAssetSv), true);
        vm.prank(generalManager);
        vm.expectRevert(MasterVault.SubVaultAssetMismatch.selector);
        vault.setSubVault(IERC4626(address(wrongAssetSv)));
    }

    /// TARGETS MUTANT #126 in MasterVault.sol
    function test_setSubVault_nonZeroAllocation_reverts() public {
        MockSubVault newSv = new MockSubVault(IERC20(address(token)), "New", "NEW");
        vault.setSubVaultWhitelist(address(newSv), true);
        vault.setTargetAllocationWad(5e17);
        vm.prank(generalManager);
        vm.expectRevert();
        vault.setSubVault(IERC4626(address(newSv)));
    }

    /// TARGETS MUTANT #128 in MasterVault.sol
    function test_setSubVault_nonZeroShares_reverts() public {
        _setupWithAllocation(1e18, 5e17);
        // allocation is 50%, so there are subvault shares. Set allocation to 0 first.
        vault.setTargetAllocationWad(0);
        // subvault still has shares even though allocation is 0
        assertTrue(vault.subVault().balanceOf(address(vault)) > 0, "should have subvault shares");
        MockSubVault newSv = new MockSubVault(IERC20(address(token)), "New", "NEW");
        vault.setSubVaultWhitelist(address(newSv), true);
        vm.prank(generalManager);
        vm.expectRevert();
        vault.setSubVault(IERC4626(address(newSv)));
    }

    // ====== setTargetAllocationWad ======

    /// TARGETS MUTANT #130, #131 in MasterVault.sol
    function test_setTargetAllocationWad_over100_reverts() public {
        vm.prank(generalManager);
        vm.expectRevert("Target allocation must be <= 100%");
        vault.setTargetAllocationWad(1e18 + 1);
    }

    /// TARGETS MUTANT #134, #135 in MasterVault.sol
    function test_setTargetAllocationWad_unchanged_reverts() public {
        vault.setTargetAllocationWad(5e17);
        vm.prank(generalManager);
        vm.expectRevert("Allocation unchanged");
        vault.setTargetAllocationWad(5e17);
    }

    // ====== setMinimumRebalanceAmount ======

    /// TARGETS MUTANT #141, #142 in MasterVault.sol
    function test_setMinimumRebalanceAmount_setsValue() public {
        vault.setMinimumRebalanceAmount(42);
        assertEq(vault.minimumRebalanceAmount(), 42, "minimumRebalanceAmount should be 42");
    }

    // ====== setRebalanceCooldown ======

    /// TARGETS MUTANT #143 in MasterVault.sol
    function test_setRebalanceCooldown_atMinimum_succeeds() public {
        vault.setRebalanceCooldown(vault.MIN_REBALANCE_COOLDOWN());
        assertEq(vault.rebalanceCooldown(), vault.MIN_REBALANCE_COOLDOWN());
    }

    /// TARGETS MUTANT #144 in MasterVault.sol
    function test_setRebalanceCooldown_belowMinimum_reverts() public {
        vm.prank(generalManager);
        vm.expectRevert();
        vault.setRebalanceCooldown(0);
    }

    /// TARGETS MUTANT #145 in MasterVault.sol
    function test_setRebalanceCooldown_swapArgs() public {
        // If swap args, values above MIN would revert and at MIN would not
        // Test that a value above MIN succeeds
        vault.setRebalanceCooldown(100);
        assertEq(vault.rebalanceCooldown(), 100);
    }

    /// TARGETS MUTANT #146, #147, #148 in MasterVault.sol
    function test_setRebalanceCooldown_setsValue() public {
        vault.setRebalanceCooldown(500);
        assertEq(vault.rebalanceCooldown(), 500, "rebalanceCooldown should be 500");
    }

    // ====== pause / unpause ======

    /// TARGETS MUTANT #151 in MasterVault.sol
    function test_pause_works() public {
        vm.prank(pauser);
        vault.pause();
        assertTrue(vault.paused(), "should be paused");
    }

    /// TARGETS MUTANT #152 in MasterVault.sol
    function test_unpause_works() public {
        vm.prank(pauser);
        vault.pause();
        assertTrue(vault.paused());
        vm.prank(pauser);
        vault.unpause();
        assertFalse(vault.paused(), "should be unpaused");
    }

    // ====== totalProfit ======

    /// TARGETS MUTANT #162 in MasterVault.sol
    function test_totalProfit_correctMath() public {
        // Use a scenario where profit > principal, so % gives different result than -
        // Deposit 10e18, simulate 20e18 profit → totalAssets ≈ 30e18, principal ≈ 10e18
        // With -: profit = 30e18 - 10e18 = 20e18
        // With %: profit = 30e18 % 10e18 = 0 (since 30 is divisible by 10)
        _depositAs(10e18);
        token.mintAmount(20e18);
        token.transfer(address(vault), 20e18);
        uint256 profit = vault.totalProfit();
        assertEq(profit, 20e18, "profit should be 20e18");
    }

    // ====== _distributePerformanceFee ======

    /// TARGETS MUTANT #166 in MasterVault.sol
    function test_distributePerformanceFee_noBeneficiary_reverts() public {
        MasterVault freshVault = MasterVault(factory.deployVault(address(new TestERC20())));
        freshVault.rolesRegistry().grantRole(freshVault.KEEPER_ROLE(), address(this));
        vm.expectRevert(MasterVault.BeneficiaryNotSet.selector);
        freshVault.distributePerformanceFee();
    }

    /// TARGETS MUTANT #168 in MasterVault.sol
    function test_distributePerformanceFee_zeroProfit_noEvent() public {
        // No profit → early return, should NOT emit PerformanceFeesWithdrawn
        // If mutant removes early return, the event would still be emitted with (beneficiary, 0, 0)
        vm.prank(keeper);
        vm.recordLogs();
        vault.distributePerformanceFee();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics[0] != keccak256("PerformanceFeesWithdrawn(address,uint256,uint256)"),
                "should not emit PerformanceFeesWithdrawn when profit is zero"
            );
        }
    }

    /// TARGETS MUTANT #176 in MasterVault.sol
    function test_distributePerformanceFee_transfersIdleProfit() public {
        _depositAs(100e18);
        token.mintAmount(10e18);
        token.transfer(address(vault), 10e18);
        uint256 vaultBalBefore = token.balanceOf(address(vault));
        vm.prank(keeper);
        vault.distributePerformanceFee();
        uint256 vaultBalAfter = token.balanceOf(address(vault));
        assertEq(token.balanceOf(beneficiaryAddr), 10e18, "beneficiary should receive profit");
        assertEq(vaultBalBefore - vaultBalAfter, 10e18, "vault should lose exactly the profit amount");
    }

    /// TARGETS MUTANT #180 in MasterVault.sol
    function test_distributePerformanceFee_withdrawsFromSubVault() public {
        // Put nearly everything into subvault so idle is very small
        _setupWithAllocation(100e18, 99e16); // 99% to subvault
        uint256 idleBeforeProfit = token.balanceOf(address(vault));
        // Simulate profit LARGER than idle, forcing withdrawal from subvault
        uint256 profitAmount = idleBeforeProfit + 5e18;
        token.mintAmount(profitAmount);
        token.transfer(address(vault.subVault()), profitAmount);
        uint256 profit = vault.totalProfit();
        assertTrue(profit > idleBeforeProfit, "profit exceeds idle");
        uint256 subVaultBalBefore = token.balanceOf(address(vault.subVault()));
        vm.prank(keeper);
        vault.distributePerformanceFee();
        uint256 subVaultBalAfter = token.balanceOf(address(vault.subVault()));
        assertEq(token.balanceOf(beneficiaryAddr), profit, "beneficiary should receive all profit");
        assertTrue(subVaultBalBefore > subVaultBalAfter, "subvault balance should decrease");
    }

    /// TARGETS MUTANT #176 in MasterVault.sol — zero idle, all profit in subvault
    function test_distributePerformanceFee_allProfitInSubVault() public {
        _setupWithAllocation(100e18, 99e16); // 99% to subvault
        // Simulate profit in subvault
        token.mintAmount(5e18);
        token.transfer(address(vault.subVault()), 5e18);
        uint256 idleBefore = token.balanceOf(address(vault));
        uint256 profit = vault.totalProfit();
        assertTrue(profit > 0);
        vm.prank(keeper);
        vault.distributePerformanceFee();
        // If mutant #176 makes `if(true)`, it calls safeTransfer(beneficiary, 0) when idle profit is 0.
        // This would still succeed, so this is more about ensuring overall correctness.
        assertEq(token.balanceOf(beneficiaryAddr), profit, "beneficiary receives full profit");
    }

    /// TARGETS MUTANT #180 in MasterVault.sol — all profit idle, nothing in subvault
    function test_distributePerformanceFee_allProfitIdle_noSubVaultWithdraw() public {
        _depositAs(100e18);
        // Profit is all idle (no allocation to subvault)
        token.mintAmount(5e18);
        token.transfer(address(vault), 5e18);
        uint256 subVaultSharesBefore = vault.subVault().balanceOf(address(vault));
        vm.prank(keeper);
        vault.distributePerformanceFee();
        uint256 subVaultSharesAfter = vault.subVault().balanceOf(address(vault));
        assertEq(subVaultSharesBefore, subVaultSharesAfter, "no subvault shares should change");
        assertEq(token.balanceOf(beneficiaryAddr), 5e18, "beneficiary gets idle profit");
    }
}

import {IAccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
