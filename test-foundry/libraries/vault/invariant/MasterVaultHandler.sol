// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {FuzzSubVault} from "../../../../contracts/tokenbridge/test/FuzzSubVault.sol";
import {TestERC20} from "../../../../contracts/tokenbridge/test/TestERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice Handler for MasterVault invariant testing.
/// @dev    The fuzzer calls handler functions in random order with random inputs.
///         Each function wraps a MasterVault operation, bounds inputs, pranks the correct caller,
///         and updates ghost state. All actions use try/catch so the handler never reverts to
///         the fuzzer -- this ensures maximum exploration of the state space.
contract MasterVaultHandler is Test {
    MasterVault public vault;
    FuzzSubVault public subVault;
    TestERC20 public token;
    address public user;
    address public keeper;

    // --- Ghost variables ---

    /// @notice Cumulative assets deposited into the MasterVault
    uint256 public ghost_deposited;

    /// @notice Cumulative assets received by users via redeem
    uint256 public ghost_redeemed;

    /// @notice Cumulative profit injected into the system (tokens sent to vault/subvault)
    uint256 public ghost_profit;

    /// @notice Cumulative loss removed from the system (tokens taken from vault/subvault)
    uint256 public ghost_loss;

    /// @notice Cumulative fees sent to beneficiary via distributePerformanceFee
    uint256 public ghost_feesClaimed;

    /// @notice Count of successful calls per action (for debugging fuzzer coverage)
    mapping(bytes4 => uint256) public ghost_callCount;

    /// @notice Whether subvault has been positively manipulated (profit-like: extra assets, deflated shares)
    bool public ghost_positiveManipulation;

    /// @notice Whether subvault has been negatively manipulated (loss-like: removed assets, inflated shares, rounding errors)
    bool public ghost_negativeManipulation;

    constructor(
        MasterVault _vault,
        FuzzSubVault _subVault,
        TestERC20 _token,
        address _user,
        address _keeper
    ) {
        vault = _vault;
        subVault = _subVault;
        token = _token;
        user = _user;
        keeper = _keeper;
    }

    // --- User actions ---

    /// @notice Deposit assets into the MasterVault via the gateway user
    /// @dev    Bounds amount to [1, 1e30] to stay within reasonable range
    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 1e30);

        vm.prank(user);
        token.mintAmount(amount);

        vm.startPrank(user);
        token.approve(address(vault), amount);
        try vault.deposit(amount) {
            ghost_deposited += amount;
            ghost_callCount[this.deposit.selector]++;
        } catch {}
        vm.stopPrank();
    }

    /// @notice Redeem shares from the MasterVault as user
    /// @dev    Bounds shares to [1, user balance]
    function redeem(uint256 shares) external {
        uint256 bal = vault.balanceOf(user);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);

        uint256 assetsBefore = token.balanceOf(user);
        vm.prank(user);
        try vault.redeem(shares, 0) {
            uint256 assetsAfter = token.balanceOf(user);
            ghost_redeemed += assetsAfter - assetsBefore;
            ghost_callCount[this.redeem.selector]++;
        } catch {}
    }

    // --- Keeper actions ---

    /// @notice Warp time and call rebalance with permissive slippage
    /// @dev    Uses extreme slippage bounds to avoid exchange rate reverts masking real bugs
    function rebalance() external {
        vm.warp(block.timestamp + 2);

        int256 minExchRate;
        uint256 idle = token.balanceOf(address(vault));
        uint256 totalUp = vault.totalAssets() + 1; // rough upper bound
        uint64 alloc = vault.targetAllocationWad();
        uint256 idleTarget = (totalUp * (1e18 - alloc)) / 1e18;

        // Negative means deposit (masterVault -> subVault), positive means withdraw
        if (idle > idleTarget) {
            minExchRate = -1e18;
        } else {
            minExchRate = 0;
        }

        vm.prank(keeper);
        try vault.rebalance(minExchRate) {
            ghost_callCount[this.rebalance.selector]++;
        } catch {}
    }

    /// @notice Distribute performance fees to beneficiary
    function distributePerformanceFee() external {
        address beneficiary = vault.beneficiary();
        uint256 before = token.balanceOf(beneficiary);

        vm.prank(keeper);
        try vault.distributePerformanceFee() {
            uint256 after_ = token.balanceOf(beneficiary);
            ghost_feesClaimed += after_ - before;
            ghost_callCount[this.distributePerformanceFee.selector]++;
        } catch {}
    }

    // --- Manager actions ---

    /// @notice Set target allocation (bounded 0 to 1e18)
    function setTargetAllocation(uint256 seed) external {
        uint64 alloc = uint64(bound(seed, 0, 1e18));
        try vault.setTargetAllocationWad(alloc) {
            ghost_callCount[this.setTargetAllocation.selector]++;
        } catch {}
    }

    // --- Environment manipulation ---

    /// @notice Send tokens directly to the subvault (simulates yield / A increases)
    function simulateSubVaultProfit(uint256 amt) external {
        amt = bound(amt, 1, 1e24);
        token.mintAmount(amt);
        token.transfer(address(subVault), amt);
        ghost_profit += amt;
        ghost_positiveManipulation = true;
        ghost_callCount[this.simulateSubVaultProfit.selector]++;
    }

    /// @notice Remove tokens from the subvault (simulates loss / A decreases)
    function simulateSubVaultLoss(uint256 amt) external {
        uint256 subBal = token.balanceOf(address(subVault));
        if (subBal == 0) return;
        amt = bound(amt, 1, subBal);

        vm.prank(address(subVault));
        token.transfer(address(0xdead), amt);
        ghost_loss += amt;
        ghost_negativeManipulation = true;
        ghost_callCount[this.simulateSubVaultLoss.selector]++;
    }

    /// @notice Mint shares without backing assets on FuzzSubVault (T increases, A < T)
    function inflateSubVaultShares(uint256 amt) external {
        amt = bound(amt, 1, 1e24);
        subVault.adminMint(address(vault), amt);
        ghost_negativeManipulation = true;
        ghost_callCount[this.inflateSubVaultShares.selector]++;
    }

    /// @notice Burn shares without withdrawing assets on FuzzSubVault (T decreases, A > T)
    function deflateSubVaultShares(uint256 amt) external {
        uint256 vaultShares = subVault.balanceOf(address(vault));
        if (vaultShares == 0) return;
        amt = bound(amt, 1, vaultShares);
        subVault.adminBurn(address(vault), amt);
        ghost_positiveManipulation = true;
        ghost_callCount[this.deflateSubVaultShares.selector]++;
    }

    /// @notice Set maxWithdraw limit on the subvault
    function capSubVaultMaxWithdraw(uint256 lim) external {
        lim = bound(lim, 0, type(uint128).max);
        subVault.setMaxWithdrawLimit(lim);
        ghost_callCount[this.capSubVaultMaxWithdraw.selector]++;
    }

    /// @notice Set maxDeposit limit on the subvault
    function capSubVaultMaxDeposit(uint256 lim) external {
        lim = bound(lim, 0, type(uint128).max);
        subVault.setMaxDepositLimit(lim);
        ghost_callCount[this.capSubVaultMaxDeposit.selector]++;
    }

    /// @notice Set maxRedeem limit on the subvault
    function capSubVaultMaxRedeem(uint256 lim) external {
        lim = bound(lim, 0, type(uint128).max);
        subVault.setMaxRedeemLimit(lim);
        ghost_callCount[this.capSubVaultMaxRedeem.selector]++;
    }

    /// @notice Set deposit rounding error on the subvault (0–10% in wad)
    function setDepositError(uint256 seed) external {
        uint256 wad = bound(seed, 0, 1e17);
        subVault.setDepositErrorWad(wad);
        if (wad > 0) ghost_negativeManipulation = true;
        ghost_callCount[this.setDepositError.selector]++;
    }

    /// @notice Set withdraw rounding error on the subvault (0–10% in wad)
    function setWithdrawError(uint256 seed) external {
        uint256 wad = bound(seed, 0, 1e17);
        subVault.setWithdrawErrorWad(wad);
        if (wad > 0) ghost_negativeManipulation = true;
        ghost_callCount[this.setWithdrawError.selector]++;
    }

    /// @notice Set redeem rounding error on the subvault (0–10% in wad)
    function setRedeemError(uint256 seed) external {
        uint256 wad = bound(seed, 0, 1e17);
        subVault.setRedeemErrorWad(wad);
        if (wad > 0) ghost_negativeManipulation = true;
        ghost_callCount[this.setRedeemError.selector]++;
    }

    /// @notice Set previewMint rounding error on the subvault (0–10% in wad)
    function setPreviewMintError(uint256 seed) external {
        uint256 wad = bound(seed, 0, 1e17);
        subVault.setPreviewMintErrorWad(wad);
        if (wad > 0) ghost_negativeManipulation = true;
        ghost_callCount[this.setPreviewMintError.selector]++;
    }

    /// @notice Set previewRedeem rounding error on the subvault (0–10% in wad)
    function setPreviewRedeemError(uint256 seed) external {
        uint256 wad = bound(seed, 0, 1e17);
        subVault.setPreviewRedeemErrorWad(wad);
        if (wad > 0) ghost_negativeManipulation = true;
        ghost_callCount[this.setPreviewRedeemError.selector]++;
    }
}
