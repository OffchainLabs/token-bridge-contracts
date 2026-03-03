// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import {MasterVaultCoreTest} from "./MasterVaultCore.t.sol";
import {MasterVault} from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MockSubVault} from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice Fuzz tests that prove donation attacks cannot cause user fund loss.
///         Exercises sequences: deposit → donate → rebalance → fee dist → redeem.
contract PoCDonationFuzz is MasterVaultCoreTest {
    address attacker = address(0xBEEF);
    address victim = address(0xCAFE);
    MockSubVault subvault;

    function setUp() public override {
        super.setUp();
        subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.setSubVaultWhitelist(address(subvault), true);
        vault.setSubVault(IERC4626(address(subvault)));
    }

    /// @dev Deposit via gateway (user is gateway)
    function _depositVia(address depositor, uint256 amount) internal returns (uint256 shares) {
        vm.prank(depositor);
        token.mintAmount(amount);
        vm.startPrank(depositor);
        token.transfer(user, amount);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), amount);
        shares = vault.deposit(amount);
        vault.transfer(depositor, shares);
        vm.stopPrank();
    }

    /// @dev Donate tokens directly to the vault
    function _donate(address donor, uint256 amount) internal {
        vm.prank(donor);
        token.mintAmount(amount);
        vm.prank(donor);
        token.transfer(address(vault), amount);
    }

    /// @dev Redeem shares via the gateway
    function _redeemVia(address redeemer, uint256 shares) internal returns (uint256 assets) {
        vm.prank(redeemer);
        vault.transfer(user, shares);
        vm.startPrank(user);
        assets = vault.redeem(shares, 0);
        token.transfer(redeemer, assets);
        vm.stopPrank();
    }

    /// @dev Rebalance with keeper
    function _rebalance() internal {
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        try vault.rebalance(-1e18) {} catch {}
    }

    /// @dev Distribute performance fees
    function _distributeFees() internal {
        vm.prank(keeper);
        try vault.distributePerformanceFee() {} catch {}
    }

    // ================================================================
    //  FUZZ: Victim deposits, attacker donates, victim redeems.
    //  Victim must never lose funds regardless of donation amount.
    // ================================================================
    function testFuzz_donateAfterDeposit_victimNoLoss(
        uint128 victimDeposit,
        uint128 donationAmount
    ) public {
        vm.assume(victimDeposit >= 1 && victimDeposit <= 1e30);
        vm.assume(donationAmount >= 1 && donationAmount <= 1e30);

        uint256 victimShares = _depositVia(victim, victimDeposit);

        _donate(attacker, donationAmount);

        uint256 victimAssetsBack = _redeemVia(victim, victimShares);
        assertGe(victimAssetsBack, victimDeposit, "Victim lost funds after donation");
    }

    // ================================================================
    //  FUZZ: Donate → rebalance → fee distribution → victim deposit → redeem.
    //  Tests whether fee distribution after donation affects new depositors.
    // ================================================================
    function testFuzz_donateRebalanceFeesThenDeposit_victimNoLoss(
        uint128 seedDeposit,
        uint128 donationAmount,
        uint128 victimDeposit
    ) public {
        vm.assume(seedDeposit >= 1e6 && seedDeposit <= 1e30);
        vm.assume(donationAmount >= 1 && donationAmount <= 1e30);
        vm.assume(victimDeposit >= 1 && victimDeposit <= 1e30);

        // Seed the vault
        _depositVia(attacker, seedDeposit);

        // Set allocation and rebalance to move some tokens to subvault
        vault.setTargetAllocationWad(5e17); // 50%
        _rebalance();

        // Donation
        _donate(attacker, donationAmount);

        // Rebalance again (moves donated tokens to subvault)
        _rebalance();

        // Fee distribution
        _distributeFees();

        // Now victim deposits
        uint256 victimShares = _depositVia(victim, victimDeposit);

        // Victim redeems immediately
        uint256 victimAssetsBack = _redeemVia(victim, victimShares);
        assertGe(victimAssetsBack, victimDeposit, "Victim lost funds after donate-rebalance-fees cycle");
    }

    // ================================================================
    //  FUZZ: Full attack sequence:
    //  seed → allocation → rebalance → donate → rebalance → fees → deposit → redeem
    //  Tests whether subvault rounding after fee dist from subvault causes loss.
    // ================================================================
    function testFuzz_fullDonationCycle_victimNoLoss(
        uint128 seedDeposit,
        uint128 donationAmount,
        uint128 victimDeposit,
        uint64 allocationWad
    ) public {
        vm.assume(seedDeposit >= 1e6 && seedDeposit <= 1e30);
        vm.assume(donationAmount >= 1e6 && donationAmount <= 1e30);
        vm.assume(victimDeposit >= 1 && victimDeposit <= 1e30);
        allocationWad = uint64(bound(allocationWad, 1e16, 1e18)); // 1%-100%

        // Seed
        _depositVia(address(0xAAAA), seedDeposit);

        // Configure allocation
        vault.setTargetAllocationWad(allocationWad);
        _rebalance();

        // Donate to vault
        _donate(attacker, donationAmount);

        // Rebalance (moves donated tokens based on allocation)
        _rebalance();

        // Distribute fees
        _distributeFees();

        // Check vault solvency
        bool haveLoss = vault.totalAssets() < vault.totalSupply();

        // Victim deposits
        uint256 victimShares = _depositVia(victim, victimDeposit);

        // Victim redeems
        uint256 victimAssetsBack = _redeemVia(victim, victimShares);

        assertGe(
            victimAssetsBack,
            victimDeposit,
            string(
                abi.encodePacked(
                    "Victim lost funds. haveLoss=",
                    haveLoss ? "true" : "false",
                    " totalAssets=",
                    vm.toString(vault.totalAssets()),
                    " totalSupply=",
                    vm.toString(vault.totalSupply())
                )
            )
        );
    }

    // ================================================================
    //  FUZZ: Multiple donations between deposits. Tests accumulation.
    // ================================================================
    function testFuzz_repeatedDonations_victimNoLoss(
        uint128 victimDeposit,
        uint128 donationAmount
    ) public {
        vm.assume(victimDeposit >= 1e6 && victimDeposit <= 1e28);
        vm.assume(donationAmount >= 1 && donationAmount <= 1e28);

        vault.setTargetAllocationWad(5e17);

        uint256 totalVictimShares = 0;
        uint256 totalVictimDeposited = 0;

        // 5 rounds of donate → deposit
        for (uint256 i = 0; i < 5; i++) {
            _donate(attacker, donationAmount);
            _rebalance();
            _distributeFees();

            uint256 shares = _depositVia(victim, victimDeposit);
            totalVictimShares += shares;
            totalVictimDeposited += victimDeposit;
        }

        // Redeem all
        uint256 totalRedeemed = _redeemVia(victim, totalVictimShares);
        assertGe(totalRedeemed, totalVictimDeposited, "Victim lost funds across repeated donations");
    }

    // ================================================================
    //  FUZZ: Attacker tries to profit from deposit-donate-redeem cycle.
    //  Attacker must never profit.
    // ================================================================
    function testFuzz_attackerCannotProfit(
        uint128 attackerDeposit,
        uint128 donationAmount
    ) public {
        vm.assume(attackerDeposit >= 1 && attackerDeposit <= 1e30);
        vm.assume(donationAmount >= 1 && donationAmount <= 1e30);

        uint256 attackerShares = _depositVia(attacker, attackerDeposit);

        _donate(attacker, donationAmount);

        uint256 attackerAssetsBack = _redeemVia(attacker, attackerShares);

        // Attacker should get at most what they deposited (donation is lost to beneficiary)
        assertLe(
            attackerAssetsBack,
            uint256(attackerDeposit),
            "Attacker profited from deposit-donate-redeem"
        );
    }

    // ================================================================
    //  FUZZ: Loss mode → deposit → donation flips solvency → 1:1 redeem.
    //  Tests whether inflated loss-mode shares can be redeemed at 1:1
    //  after donation restores solvency.
    // ================================================================
    function testFuzz_lossModeDepositThenDonateToSolvency(
        uint128 initialDeposit,
        uint128 lossAmount,
        uint128 attackerDeposit,
        uint128 donationAmount
    ) public {
        vm.assume(initialDeposit >= 1e6 && initialDeposit <= 1e30);
        vm.assume(lossAmount >= 1 && lossAmount < initialDeposit);
        vm.assume(attackerDeposit >= 1 && attackerDeposit <= 1e30);
        vm.assume(donationAmount >= 1 && donationAmount <= 1e30);

        // Setup: deposit and allocate to subvault
        uint256 aliceShares = _depositVia(victim, initialDeposit);
        vault.setTargetAllocationWad(5e17);
        _rebalance();

        // Simulate subvault loss by removing tokens
        uint256 subBal = token.balanceOf(address(subvault));
        uint256 actualLoss = lossAmount > subBal ? subBal : lossAmount;
        if (actualLoss > 0) {
            vm.prank(address(subvault));
            token.transfer(address(0xdead), actualLoss);
        }

        // Verify we're in loss mode
        bool inLoss = vault.totalAssets() < vault.totalSupply();
        if (!inLoss) return; // skip if not in loss mode (loss was too small)

        // Attacker deposits during loss mode (gets inflated shares)
        uint256 attackerShares = _depositVia(attacker, attackerDeposit);

        // Attacker donates to try to restore solvency
        _donate(attacker, donationAmount);

        // Check if solvency was restored
        bool stillInLoss = vault.totalAssets() < vault.totalSupply();

        if (!stillInLoss) {
            // Solvency restored! Now redeem at 1:1

            // Attacker total cost vs return
            uint256 attackerAssetsBack = _redeemVia(attacker, attackerShares);
            uint256 attackerTotalSpent = uint256(attackerDeposit) + uint256(donationAmount);

            // Attacker must not profit from the entire sequence
            assertLe(
                attackerAssetsBack,
                attackerTotalSpent,
                "Attacker profited from loss-mode-deposit + donation + 1:1 redeem"
            );

            // Alice should get her full deposit back (if possible)
            uint256 aliceAssetsBack = _redeemVia(victim, aliceShares);
            // Alice might lose due to the original subvault loss, but should not
            // lose MORE than the original loss
            assertGe(
                aliceAssetsBack + actualLoss + 2, // +2 for rounding tolerance
                initialDeposit,
                "Alice lost more than the subvault loss"
            );
        }
    }

    // ================================================================
    //  INVARIANT-STYLE: Deposit-redeem round-trip after donation
    //  should never extract value (assetsOut <= assetsIn).
    // ================================================================
    function testFuzz_depositRedeemRoundTrip_afterDonation(
        uint128 donationAmount,
        uint128 depositAmount
    ) public {
        vm.assume(donationAmount >= 0 && donationAmount <= 1e30);
        vm.assume(depositAmount >= 1 && depositAmount <= 1e30);

        // Donate first (manipulate totalAssets)
        if (donationAmount > 0) {
            _donate(attacker, donationAmount);
        }

        // Round-trip deposit → redeem
        uint256 shares = _depositVia(victim, depositAmount);
        uint256 assetsBack = _redeemVia(victim, shares);

        assertLe(
            assetsBack,
            uint256(depositAmount),
            "Round-trip extracted value after donation"
        );
    }

    // ================================================================
    //  FUZZ: Fee distribution after donation must not push vault
    //  into loss mode when there's no subvault interaction.
    // ================================================================
    function testFuzz_feeDistAfterDonation_noLossMode(
        uint128 depositAmount,
        uint128 donationAmount
    ) public {
        vm.assume(depositAmount >= 1 && depositAmount <= 1e30);
        vm.assume(donationAmount >= 1 && donationAmount <= 1e30);

        _depositVia(victim, depositAmount);

        // No allocation — all tokens idle (no subvault rounding possible)
        _donate(attacker, donationAmount);

        // Distribute fees
        _distributeFees();

        // Vault should never enter loss mode from idle-only fee distribution
        assertGe(
            vault.totalAssets(),
            vault.totalSupply(),
            "Fee distribution from idle pushed vault into loss mode"
        );
    }

    // ================================================================
    //  FUZZ: Fee distribution after donation WITH subvault interaction.
    //  Tests whether subvault withdrawal rounding during fee distribution
    //  can push the vault into loss mode.
    // ================================================================
    function testFuzz_feeDistFromSubvault_afterDonation(
        uint128 depositAmount,
        uint128 donationAmount,
        uint64 allocationWad
    ) public {
        vm.assume(depositAmount >= 1e6 && depositAmount <= 1e28);
        vm.assume(donationAmount >= 1e6 && donationAmount <= 1e28);
        allocationWad = uint64(bound(allocationWad, 5e17, 99e16)); // 50-99%

        _depositVia(victim, depositAmount);

        // Set high allocation to subvault
        vault.setTargetAllocationWad(allocationWad);
        _rebalance();

        // Donate to vault
        _donate(attacker, donationAmount);

        // Rebalance to move donated tokens to subvault
        _rebalance();

        // Record state before fee distribution
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Distribute fees (may need to withdraw from subvault)
        _distributeFees();

        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();

        // If vault was solvent before, check if fee distribution pushed it into loss
        if (totalAssetsBefore >= totalSupplyBefore) {
            // After fee distribution, vault MUST remain solvent
            // (fee distribution should only extract profit, not principal)
            assertGe(
                totalAssetsAfter,
                totalSupplyAfter,
                string(
                    abi.encodePacked(
                        "Fee dist pushed vault into loss! ",
                        "before: assets=",
                        vm.toString(totalAssetsBefore),
                        " supply=",
                        vm.toString(totalSupplyBefore),
                        " after: assets=",
                        vm.toString(totalAssetsAfter),
                        " supply=",
                        vm.toString(totalSupplyAfter)
                    )
                )
            );
        }
    }
}
