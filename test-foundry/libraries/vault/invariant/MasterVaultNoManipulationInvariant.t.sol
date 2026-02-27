// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// import {MasterVaultInvariant} from "./MasterVaultInvariant.t.sol";
// import {MasterVaultHandler} from "./MasterVaultHandler.sol";

// /// @notice Invariant tests with subvault rounding-error manipulation disabled.
// /// @dev    Inherits all invariants from MasterVaultInvariant and adds invariants
// ///         that only hold when the subvault behaves honestly (no rounding errors).
// contract MasterVaultNoManipulationInvariant is MasterVaultInvariant {
//     function _createHandler() internal override {
//         handler = new MasterVaultHandler(vault, subVault, token, user, keeper, false);
//         vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(handler));
//     }

//     /// @notice When no rounding errors injected, assets cover principal.
//     /// @dev    Under normal operation, the vault should never become insolvent.
//     function invariant_solvency() public {
//         if (handler.ghost_callCount(handler.simulateSubVaultLoss.selector) != 0) return; // todo: similar manipulation flag necessary
//         assertGe(vault.totalAssets() * DEAD_SHARES + 1, vault.totalSupply(), "insolvent without manipulation");
//     }

//     /// @notice Performance fees must never exceed reported profit.
//     function invariant_feeDistributionBounded() public {
//         subVault.setMaxWithdrawLimit(type(uint256).max);
//         uint256 roundingTolerance = handler.ghost_callCount(handler.deposit.selector) + handler.ghost_callCount(handler.redeem.selector);
//         vm.prank(keeper);
//         vault.distributePerformanceFee();
//         assertLe(
//             token.balanceOf(vault.beneficiary()),
//             handler.ghost_profit() + roundingTolerance,
//             "fees extracted exceed profit"
//         );
//     }
// }
