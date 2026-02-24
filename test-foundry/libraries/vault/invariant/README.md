# MasterVault Invariant & Fuzz Tests

Handler-based invariant testing and targeted fuzz testing for the MasterVault. Exercises the full state space — including arbitrary subvault behavior — to catch bugs that scenario-based tests miss.

## Architecture

```
contracts/tokenbridge/test/FuzzSubVault.sol           Minimal vault mock (no ERC4626 inheritance)
test-foundry/libraries/vault/invariant/
├── MasterVaultHandler.sol                            Handler (fuzzer entry point)
├── MasterVaultInvariant.t.sol                        Stateful invariant tests
├── MasterVaultFuzz.t.sol                             Targeted fuzz tests
└── README.md
```

### FuzzSubVault

A minimal vault mock that only implements the ERC4626 subset MasterVault actually calls (`asset`, `deposit`, `withdraw`, `maxDeposit`, `maxWithdraw`, `previewMint`, `previewRedeem`, `balanceOf`). No ERC4626 inheritance — vault math is hand-rolled with `Math.mulDiv` so the mock is fully auditable.

The fuzzer controls every degree of freedom the spec leaves open:

- `adminMint(to, shares)` — mint shares without backing assets (simulates loss, A < T)
- `adminBurn(from, shares)` — burn shares without withdrawing assets (A > T)
- `setMaxWithdrawLimit(limit)` — cap withdrawals (enforced by `withdraw`, reverts if exceeded)
- `setMaxDepositLimit(limit)` — cap deposits (enforced by `deposit`, reverts if exceeded)

### Handler

11 actions the fuzzer calls in random order:

| Action | Caller | What it does |
|---|---|---|
| `deposit` | user/gateway | Mint tokens, approve, deposit |
| `redeem` | user | Redeem shares for assets |
| `rebalance` | keeper | Warp time, rebalance with permissive slippage |
| `distributePerformanceFee` | keeper | Claim fees to beneficiary |
| `setTargetAllocation` | manager | Set allocation 0–100% |
| `simulateSubVaultProfit` | — | Send tokens to subvault |
| `simulateSubVaultLoss` | — | Remove tokens from subvault |
| `inflateSubVaultShares` | — | `adminMint` (skew rate down) |
| `deflateSubVaultShares` | — | `adminBurn` (skew rate up) |
| `capSubVaultMaxWithdraw` | — | Limit subvault withdrawals |
| `capSubVaultMaxDeposit` | — | Limit subvault deposits |

All actions use `try/catch` so the handler never reverts to the fuzzer.

Ghost variables track cumulative deposits, redemptions, profit, loss, and fees for cross-action invariant checking.

## Invariants (7)

Checked by Foundry after every call sequence in `MasterVaultInvariant.t.sol`:

| Invariant | What it checks |
|---|---|
| `accountingIdentity` | `totalAssets == 1 + idle + previewRedeem(subShares)` |
| `deadSharesPreserved` | `totalSupply >= 10^6` (first-depositor mitigation) |
| `totalAssetsFloor` | `totalAssets >= 1` (+1 offset always present) |
| `allocationBounds` | `targetAllocationWad <= 1e18` |
| `noValueCreation` | outflows <= inflows + 1 |
| `solvencyWhenNoManipulation` | assets cover principal when no external losses |
| `subVaultShareConsistency` | vault shares <= subvault totalSupply |

## Targeted Fuzz Tests (7)

In `MasterVaultFuzz.t.sol`. Each is a fixed operation sequence with fuzzed inputs:

| Test | Property | Expected |
|---|---|---|
| `test_rebalanceToZero_clearsAllShares` | No dust shares after rebalance to 0% | **FAILS** (known bug) |
| `test_subVaultSwitch_alwaysSucceeds` | Can always switch subvaults after rebalance to 0% | **FAILS** (same bug) |
| `test_depositRedeem_roundTrip` | Redeem never returns more than deposited | PASS |
| `test_proportionalRedemption` | Two users get proportional redemptions | PASS |
| `test_feeDistribution_bounded` | Fees <= profit, user keeps principal | PASS |
| `test_rebalance_totalAssetsPreserved` | Rebalancing doesn't leak/create value | PASS |
| `test_rebalance_idempotent` | Second rebalance reverts with `TargetAllocationMet` | PASS |

## Running

```bash
# Invariant tests
forge test --match-path test-foundry/libraries/vault/invariant/MasterVaultInvariant.t.sol -vvv

# Targeted fuzz tests
forge test --match-path test-foundry/libraries/vault/invariant/MasterVaultFuzz.t.sol -vvv

# Just the dust share catcher
forge test --match-test test_rebalanceToZero_clearsAllShares -vvv
```

## Configuration

In `foundry.toml`:

```toml
[invariant]
runs = 256
depth = 50
fail_on_revert = false
```

## Extending

**New invariant**: Add an `invariant_` function to `MasterVaultInvariant.t.sol`. Foundry discovers it automatically.

**New fuzz test**: Add a `test_` function to `MasterVaultFuzz.t.sol`. Bound inputs, set up state, execute, assert.

**New handler action**: Add a public function to `MasterVaultHandler.sol`. Update ghost variables. Foundry discovers it via `targetContract`.

**New subvault knob**: Add a setter + storage to `FuzzSubVault.sol`, then add a handler action that calls it.
