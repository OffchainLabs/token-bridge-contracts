// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import {MasterVaultCoreTest} from "./MasterVaultCore.t.sol";
import {MasterVault} from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MockSubVault} from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice PoC: attempt to exploit MasterVault via donation (inflation) attack
///         after EXTRA_DECIMALS removal. Tests multiple attack vectors.
contract PoCDonationAttack is MasterVaultCoreTest {
    address attacker = address(0xBEEF);
    address victim = address(0xCAFE);

    function setUp() public override {
        super.setUp();
        // set up a mock subvault so rebalance works
        MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.setSubVaultWhitelist(address(_subvault), true);
        vault.setSubVault(IERC4626(address(_subvault)));
    }

    /// ---------------------------------------------------------------
    /// Helper: deposit via the gateway (user is the mock gateway)
    /// ---------------------------------------------------------------
    function _depositVia(address depositor, uint256 amount) internal returns (uint256 shares) {
        vm.prank(depositor);
        token.mintAmount(amount);
        vm.startPrank(depositor);
        // transfer tokens to the gateway (user) who calls deposit
        token.transfer(user, amount);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), amount);
        shares = vault.deposit(amount);
        // transfer shares to the actual depositor
        vault.transfer(depositor, shares);
        vm.stopPrank();
    }

    /// @dev Donate tokens directly to the vault (not through deposit)
    function _donate(uint256 amount) internal {
        vm.prank(attacker);
        token.mintAmount(amount);
        vm.prank(attacker);
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

    // ================================================================
    //  ATTACK 1: Classic first-depositor inflation attack
    //
    //  1. Attacker front-runs and deposits 1 wei
    //  2. Attacker donates a huge amount directly to vault
    //  3. Victim deposits, hoping donation inflated share price
    //     so victim gets 0 shares (rounding down)
    //  4. Attacker redeems to steal victim's deposit
    // ================================================================
    function test_classicInflationAttack_fails() public {
        uint256 attackerDeposit = 1;
        uint256 donationAmount = 1_000_000e18;
        uint256 victimDeposit = 500_000e18;

        console2.log("=== Classic Inflation Attack ===");
        console2.log("Initial state:");
        console2.log("  totalSupply:", vault.totalSupply());
        console2.log("  totalAssets:", vault.totalAssets());

        // Step 1: Attacker deposits 1 wei to get shares
        uint256 attackerShares = _depositVia(attacker, attackerDeposit);
        console2.log("\nAfter attacker deposits 1 wei:");
        console2.log("  attackerShares:", attackerShares);
        console2.log("  totalSupply:", vault.totalSupply());
        console2.log("  totalAssets:", vault.totalAssets());

        // Step 2: Attacker donates huge amount directly
        _donate(donationAmount);
        console2.log("\nAfter donation of", donationAmount);
        console2.log("  totalSupply:", vault.totalSupply());
        console2.log("  totalAssets:", vault.totalAssets());
        console2.log(
            "  _haveLoss? totalAssets < totalSupply:", vault.totalAssets() < vault.totalSupply()
        );

        // Step 3: Victim deposits
        uint256 victimShares = _depositVia(victim, victimDeposit);
        console2.log("\nAfter victim deposits", victimDeposit);
        console2.log("  victimShares:", victimShares);
        console2.log("  totalSupply:", vault.totalSupply());
        console2.log("  totalAssets:", vault.totalAssets());

        // KEY: victim gets full shares because 1:1 ratio is used (vault is solvent)
        assertEq(victimShares, victimDeposit, "Victim should get 1:1 shares (attack blocked)");
        assertTrue(victimShares > 0, "Victim must NOT get 0 shares");

        // Step 4: Attacker redeems
        uint256 attackerAssetsBack = _redeemVia(attacker, attackerShares);
        console2.log("\nAttacker redeems:");
        console2.log("  attackerAssetsBack:", attackerAssetsBack);

        // Attacker gets back at most what they deposited (1 wei)
        assertLe(attackerAssetsBack, attackerDeposit, "Attacker must not profit");

        // Victim redeems and gets back their full deposit
        uint256 victimAssetsBack = _redeemVia(victim, victimShares);
        console2.log("  victimAssetsBack:", victimAssetsBack);
        assertEq(victimAssetsBack, victimDeposit, "Victim should recover full deposit");

        uint256 victimLoss = victimDeposit > victimAssetsBack ? victimDeposit - victimAssetsBack : 0;
        console2.log("\n  Victim loss:", victimLoss);
        assertEq(victimLoss, 0, "Victim should have zero loss");
    }

    // ================================================================
    //  ATTACK 2: Donation before any user deposits
    //
    //  Attacker donates directly to the vault before anyone deposits,
    //  trying to manipulate the share price from the start.
    // ================================================================
    function test_donationBeforeAnyDeposit_fails() public {
        uint256 donationAmount = 1_000_000e18;
        uint256 victimDeposit = 100e18;

        console2.log("=== Donation Before Any Deposit ===");
        console2.log("Initial state (only dead shares):");
        console2.log("  totalSupply:", vault.totalSupply());
        console2.log("  totalAssets:", vault.totalAssets());

        // Donate directly before anyone deposits
        _donate(donationAmount);
        console2.log("\nAfter donation:");
        console2.log("  totalSupply:", vault.totalSupply());
        console2.log("  totalAssets:", vault.totalAssets());

        // Victim deposits
        uint256 victimShares = _depositVia(victim, victimDeposit);
        console2.log("\nVictim deposits", victimDeposit);
        console2.log("  victimShares:", victimShares);

        // 1:1 ratio used because vault is solvent (totalAssets >> totalSupply)
        assertEq(victimShares, victimDeposit, "Victim gets 1:1 shares");

        // Victim redeems immediately
        uint256 victimAssetsBack = _redeemVia(victim, victimShares);
        console2.log("  victimAssetsBack:", victimAssetsBack);
        assertEq(victimAssetsBack, victimDeposit, "Victim recovers full deposit");
    }

    // ================================================================
    //  ATTACK 3: Large donation ratio (extreme case)
    //
    //  Donation is orders of magnitude larger than victim's deposit.
    //  In a naive ERC4626, even 1 dead share wouldn't help here.
    // ================================================================
    function test_extremeDonationRatio_fails() public {
        uint256 donationAmount = type(uint128).max; // ~3.4e38
        uint256 victimDeposit = 1; // just 1 wei

        console2.log("=== Extreme Donation Ratio ===");

        // Attacker deposits 1 wei
        uint256 attackerShares = _depositVia(attacker, 1);

        // Massive donation
        _donate(donationAmount);
        console2.log("After massive donation:");
        console2.log("  totalAssets:", vault.totalAssets());
        console2.log("  totalSupply:", vault.totalSupply());

        // Victim deposits just 1 wei
        uint256 victimShares = _depositVia(victim, victimDeposit);
        console2.log("  victimShares:", victimShares);

        // Even with 1 wei deposit, victim still gets 1 share (1:1 ratio)
        assertEq(victimShares, 1, "Victim gets 1 share for 1 wei");

        // Victim redeems
        uint256 victimAssetsBack = _redeemVia(victim, victimShares);
        assertEq(victimAssetsBack, victimDeposit, "Victim recovers 1 wei");

        // Attacker gets back only what they deposited
        uint256 attackerAssetsBack = _redeemVia(attacker, attackerShares);
        assertLe(attackerAssetsBack, 1, "Attacker gets at most 1 wei back");
    }

    // ================================================================
    //  ATTACK 4: Sandwich attack on deposit
    //
    //  1. Attacker sees victim's deposit in mempool
    //  2. Front-runs with deposit + donation
    //  3. Victim's deposit lands
    //  4. Attacker back-runs with redeem
    // ================================================================
    function test_sandwichAttack_fails() public {
        uint256 attackerDeposit = 100e18;
        uint256 donationAmount = 1_000_000e18;
        uint256 victimDeposit = 50_000e18;

        console2.log("=== Sandwich Attack ===");

        // Front-run: attacker deposits
        uint256 attackerShares = _depositVia(attacker, attackerDeposit);
        console2.log("Attacker deposits:", attackerDeposit, "shares:", attackerShares);

        // Front-run: attacker donates
        _donate(donationAmount);
        console2.log("Attacker donates:", donationAmount);
        console2.log("  totalAssets:", vault.totalAssets());
        console2.log("  totalSupply:", vault.totalSupply());

        // Victim deposit lands
        uint256 victimShares = _depositVia(victim, victimDeposit);
        console2.log("Victim deposits:", victimDeposit, "shares:", victimShares);

        // Back-run: attacker redeems
        uint256 attackerAssetsBack = _redeemVia(attacker, attackerShares);
        console2.log("Attacker redeems:", attackerAssetsBack);

        // Attacker should NOT profit
        uint256 attackerSpent = attackerDeposit + donationAmount;
        console2.log("Attacker total spent:", attackerSpent);
        console2.log("Attacker got back:", attackerAssetsBack);

        assertLe(attackerAssetsBack, attackerDeposit, "Attacker gets back at most their deposit");
        assertTrue(attackerAssetsBack < attackerSpent, "Attacker lost the donation");

        // Victim should not lose anything
        uint256 victimAssetsBack = _redeemVia(victim, victimShares);
        assertEq(victimAssetsBack, victimDeposit, "Victim recovers full deposit");
    }

    // ================================================================
    //  ATTACK 5: Deposit, donate, then try to redeem at inflated rate
    //
    //  Attacker deposits, donates to inflate totalAssets, then tries
    //  to redeem at a higher rate. Since 1:1 ratio is used when
    //  solvent, the donation doesn't inflate redemption value.
    // ================================================================
    function test_selfDonationInflation_fails() public {
        uint256 attackerDeposit = 1000e18;
        uint256 donationAmount = 1_000_000e18;

        console2.log("=== Self-Donation Inflation ===");

        uint256 attackerShares = _depositVia(attacker, attackerDeposit);
        console2.log("Attacker deposits:", attackerDeposit, "shares:", attackerShares);

        _donate(donationAmount);
        console2.log("After donation - totalAssets:", vault.totalAssets());
        console2.log("After donation - totalSupply:", vault.totalSupply());

        // Attacker redeems hoping to get deposit + donation back
        uint256 attackerAssetsBack = _redeemVia(attacker, attackerShares);
        console2.log("Attacker redeems:", attackerAssetsBack);

        // 1:1 ratio means attacker only gets their deposit back
        assertEq(attackerAssetsBack, attackerDeposit, "Attacker only gets deposit back");

        // Donation is stuck as profit for the beneficiary
        uint256 profit = vault.totalProfit();
        console2.log("Vault profit (= donation):", profit);
        assertEq(profit, donationAmount, "Donation becomes profit for beneficiary");
    }

    // ================================================================
    //  ATTACK 6: Fuzz many deposit/donation/redeem combinations
    //
    //  For any combination of attacker deposit, donation, and victim
    //  deposit amounts, verify the victim never loses funds.
    // ================================================================
    function testFuzz_donationAttack_victimNeverLoses(
        uint128 attackerDeposit,
        uint128 donationAmount,
        uint128 victimDeposit
    ) public {
        // bound to reasonable non-zero amounts
        vm.assume(attackerDeposit >= 1 && attackerDeposit <= 1e30);
        vm.assume(donationAmount >= 1 && donationAmount <= 1e30);
        vm.assume(victimDeposit >= 1 && victimDeposit <= 1e30);

        // Attacker deposits
        uint256 attackerShares = _depositVia(attacker, attackerDeposit);

        // Attacker donates
        _donate(donationAmount);

        // Victim deposits
        uint256 victimShares = _depositVia(victim, victimDeposit);

        // Victim must get shares equal to deposit (1:1 ratio when solvent)
        assertEq(victimShares, victimDeposit, "Victim should get 1:1 shares");

        // Victim redeems
        uint256 victimAssetsBack = _redeemVia(victim, victimShares);
        assertEq(victimAssetsBack, victimDeposit, "Victim must recover full deposit");

        // Attacker can't profit from the deposit-donate-victim-redeem sequence
        uint256 attackerAssetsBack = _redeemVia(attacker, attackerShares);
        assertLe(attackerAssetsBack, attackerDeposit, "Attacker must not profit from attack");
    }

    // ================================================================
    //  ATTACK 7: Try to trigger _haveLoss() artificially
    //
    //  If an attacker could make _haveLoss() return false when there
    //  IS a loss, they could extract value. Verify this is impossible
    //  via donation alone.
    // ================================================================
    function test_cannotBypassHaveLoss() public {
        uint256 deposit = 1000e18;

        console2.log("=== Cannot Bypass _haveLoss ===");

        // Normal deposit
        uint256 shares = _depositVia(attacker, deposit);
        console2.log("After deposit - totalAssets:", vault.totalAssets());
        console2.log("After deposit - totalSupply:", vault.totalSupply());

        // totalAssets = 1 + deposit = 1 + 1000e18
        // totalSupply = 1 + 1000e18 (dead share + deposit shares)
        // _haveLoss: totalAssets(1 + 1000e18) < totalSupply(1 + 1000e18) = false

        // Donation only increases totalAssets, so it can never cause _haveLoss()
        _donate(1e18);
        assertFalse(vault.totalAssets() < vault.totalSupply(), "Donation cannot cause loss");

        // Only actual loss of assets (e.g., subvault loss) can trigger _haveLoss()
        // But that's not something an attacker can do via donation

        // Verify shares redeem correctly
        uint256 assetsBack = _redeemVia(attacker, shares);
        assertEq(assetsBack, deposit, "Full deposit recovered");
    }

    // ================================================================
    //  ATTACK 8: Multiple small donations between deposits
    //
    //  Try to accumulate rounding errors across many operations.
    // ================================================================
    function test_manySmallDonations_noRoundingExploit() public {
        uint256 victimDeposit = 100e18;

        console2.log("=== Many Small Donations ===");

        // Do 10 rounds of small donations followed by deposits
        uint256[] memory victimSharesList = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            // Small donation each round
            _donate(1);
            victimSharesList[i] = _depositVia(victim, victimDeposit);
        }

        // Redeem all and verify no loss
        uint256 totalRedeemed = 0;
        for (uint256 i = 0; i < 10; i++) {
            totalRedeemed += _redeemVia(victim, victimSharesList[i]);
        }

        uint256 totalDeposited = victimDeposit * 10;
        console2.log("Total deposited:", totalDeposited);
        console2.log("Total redeemed:", totalRedeemed);
        assertEq(totalRedeemed, totalDeposited, "No rounding loss across many operations");
    }
}
