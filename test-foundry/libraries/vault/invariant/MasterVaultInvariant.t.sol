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
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MasterVaultHandler} from "./MasterVaultHandler.sol";

contract MockGatewayRouterInvariant {
    address public gateway;

    constructor(address _gateway) {
        gateway = _gateway;
    }

    function getGateway(address) external view returns (address) {
        return gateway;
    }
}

/// @notice Stateful invariant tests for MasterVault.
/// @dev    Setup deploys the vault via factory, a FuzzSubVault as the active subvault,
///         grants all roles, and targets the handler contract for fuzzer calls.
contract MasterVaultInvariant is Test {
    MasterVaultFactory public factory;
    MasterVault public vault;
    FuzzSubVault public subVault;
    TestERC20 public token;
    MasterVaultHandler public handler;

    address public user = vm.addr(1);
    address public keeper = address(0xBBBB);
    address public beneficiaryAddr = address(0x9999);
    address public proxyAdmin = address(0xAA);

    uint256 public constant DEAD_SHARES = 10 ** 6;

    function setUp() public {
        // Deploy factory behind a TransparentUpgradeableProxy
        MasterVault impl = new MasterVault();
        MasterVaultFactory factoryImpl = new MasterVaultFactory();
        factory = MasterVaultFactory(
            address(new TransparentUpgradeableProxy(address(factoryImpl), proxyAdmin, bytes("")))
        );
        MockGatewayRouterInvariant mockRouter = new MockGatewayRouterInvariant(user);
        factory.initialize(address(impl), address(this), IGatewayRouter(address(mockRouter)));
        token = new TestERC20();
        vault = MasterVault(factory.deployVault(address(token)));

        // Deploy FuzzSubVault and configure it as the active subvault
        subVault = new FuzzSubVault(IERC20(address(token)), "FuzzSub", "fSUB");
        vault.rolesRegistry().grantRole(vault.ADMIN_ROLE(), address(this));
        vault.setSubVaultWhitelist(address(subVault), true);
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.rolesRegistry().grantRole(vault.KEEPER_ROLE(), keeper);
        vault.rolesRegistry().grantRole(vault.FEE_MANAGER_ROLE(), address(this));
        vault.setSubVault(IERC4626(address(subVault)));
        vault.setBeneficiary(beneficiaryAddr);
        vault.setMinimumRebalanceAmount(1);

        // Deploy handler and target it
        handler = new MasterVaultHandler(vault, subVault, token, user, keeper);
        // Grant manager role to handler so setTargetAllocation works
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(handler));

        targetContract(address(handler));
    }

    // --- Invariants ---

    function invariant_canAlwaysRebalanceToZero() public {
        _rebalanceToZero();
    }

    function invariant_canAlwaysSwitchSubVaults() public {
        if (_rebalanceToZero()) return;

        FuzzSubVault newSubVault = new FuzzSubVault(IERC20(address(token)), "FuzzSub2", "fSUB2");
        vault.setSubVaultWhitelist(address(newSubVault), true);
        vault.setSubVault(IERC4626(address(newSubVault)));

        // restore original subvault so future invariant calls work
        vault.setSubVaultWhitelist(address(subVault), true);
        vault.setSubVault(IERC4626(address(subVault)));
    }

    /// @notice The totalAssets formula must always hold:
    ///         vault.totalAssets() == 1 + token.balanceOf(vault) + subVault.previewRedeem(subVault.balanceOf(vault))
    /// @dev    Any drift means the vault is mispricing shares.
    ///         Catches: accumulated rounding errors, incorrect subvault conversion, stale accounting.
    function invariant_accountingIdentity() public {
        uint256 idle = token.balanceOf(address(vault));
        uint256 subShares = subVault.balanceOf(address(vault));
        uint256 subAssets = subVault.previewRedeem(subShares);
        uint256 expected = 1 + idle + subAssets;
        assertEq(vault.totalAssets(), expected, "accounting identity violated");
    }

    /// @notice Dead shares from initialization are never burned.
    /// @dev    First-depositor attack mitigation depends on these.
    ///         Catches: underflow in burn logic, accidental redemption of dead shares.
    function invariant_deadSharesPreserved() public {
        assertGe(vault.totalSupply(), DEAD_SHARES, "dead shares burned");
    }

    /// @notice The +1 offset in _totalAssets is always present.
    /// @dev    Removing the offset breaks the first-depositor mitigation and share pricing.
    ///         Catches: underflow, offset regression.
    function invariant_totalAssetsFloor() public {
        assertGe(vault.totalAssets(), 1, "totalAssets below floor");
    }

    /// @notice Allocation percentage never exceeds 100%.
    /// @dev    Overflow in allocation would cause incorrect idle targets and broken rebalancing.
    function invariant_allocationBounds() public {
        assertLe(vault.targetAllocationWad(), 1e18, "allocation exceeds 100%");
    }

    /// @notice Total outflows never exceed total inflows (plus the +1 offset).
    /// @dev    The core economic invariant.
    ///         Catches: share inflation, rounding exploits, double-counting, incorrect fee extraction.
    function invariant_noValueCreation() public {
        assertLe(
            handler.ghost_redeemed() + handler.ghost_feesClaimed(),
            handler.ghost_deposited() + handler.ghost_profit() + 1,
            "value created from nothing"
        );
    }

    /// @notice When no external losses injected, assets cover principal (within rounding tolerance).
    /// @dev    Under normal operation, the vault should never become insolvent.
    ///         Fee distribution rounds down, so totalAssets may be up to 2 wei below totalPrincipal.
    ///         Catches: value leakage through rounding, incorrect share pricing.
    function invariant_solvencyWhenNoNegativeManipulation() public {
        if (!handler.ghost_negativeManipulation()) {
            uint256 totalPrincipal = vault.totalSupply() / DEAD_SHARES;
            uint256 totalAssets = vault.totalAssets();
            assertGe(totalAssets + 2, totalPrincipal, "insolvent without negative manipulation");
        }
    }

    /// @notice Vault can't hold more subvault shares than exist.
    /// @dev    Sanity check on subvault interaction correctness.
    function invariant_subVaultShareConsistency() public {
        assertLe(
            subVault.balanceOf(address(vault)),
            subVault.totalSupply(),
            "vault holds more subvault shares than exist"
        );
    }

    /// @notice A deposit-redeem round-trip must never extract value.
    /// @dev    At any reachable state (arbitrary exchange rates from handler actions),
    ///         depositing X and immediately redeeming should return <= X.
    ///         Catches: share pricing rounding that favors depositor over vault.
    function invariant_depositRedeemNoValueExtraction() public {
        uint256 depositAmount = bound(handler.random(), 1, 1e18);
        vm.prank(user);
        token.mintAmount(depositAmount);
        vm.startPrank(user);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount);
        vm.stopPrank();

        uint256 balBefore = token.balanceOf(user);
        vm.prank(user);
        vault.redeem(shares, 0);
        uint256 assetsReceived = token.balanceOf(user) - balBefore;

        assertLe(assetsReceived, depositAmount, "deposit-redeem round-trip extracted value");
    }

    function _rebalanceToZero() internal returns (bool skip) {
        if (vault.targetAllocationWad() != 0) {
            vault.setTargetAllocationWad(0);
        }

        uint256 shareBalance = vault.subVault().balanceOf(address(vault));
        if (shareBalance == 0) return true;

        uint256 maxRedeem = vault.subVault().maxRedeem(address(vault));
        if (maxRedeem == 0) return true;

        uint256 iterationsRequired = (shareBalance) / maxRedeem + 1;

        // set some reasonable upper bound on iterations to prevent infinite loop
        if (iterationsRequired > 10) return true;

        for (uint256 i = 0; i < iterationsRequired && vault.subVault().balanceOf(address(vault)) != 0; i++) {
            vm.warp(block.timestamp + 2);
            vm.prank(keeper);
            vault.rebalance(0);
        }

        uint256 shareBalanceAfter = vault.subVault().balanceOf(address(vault));
        assertEq(shareBalanceAfter, 0, "should have redeemed all shares after iterations");
    }
}
