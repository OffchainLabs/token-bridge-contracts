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
import {MasterVaultWithManipulationHandler, MasterVaultHandler} from "./MasterVaultHandler.sol";
import {console2} from "forge-std/console2.sol";

contract MockGatewayRouterInvariant {
    address public gateway;

    constructor(address _gateway) {
        gateway = _gateway;
    }

    function getGateway(address) external view returns (address) {
        return gateway;
    }
}

abstract contract BaseMasterVaultInvariant is Test {
    MasterVaultFactory public factory;
    MasterVault public vault;
    FuzzSubVault public subVault;
    TestERC20 public token;
    address public handler;

    address public user = vm.addr(1);
    address public keeper = address(0xBBBB);
    address public beneficiaryAddr = address(0x9999);
    address public proxyAdmin = address(0xAA);

    uint256 public random;

    uint256 public constant DEAD_SHARES = 10 ** 6;

    function setUp() public virtual {
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

        handler = _createHandler();
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), handler);
        targetContract(handler);
    }

    function _createHandler() internal virtual returns (address);

    function _clearAllLimits() internal {
        subVault.setMaxWithdrawLimit(type(uint256).max);
        subVault.setMaxDepositLimit(type(uint256).max);
        subVault.setMaxRedeemLimit(type(uint256).max);
    }

    function _clearAllRoundingError() internal {
        subVault.setDepositErrorWad(0);
        subVault.setWithdrawErrorWad(0);
        subVault.setRedeemErrorWad(0);
        subVault.setPreviewMintErrorWad(0);
        subVault.setPreviewRedeemErrorWad(0);
    }

    function _revert(bytes memory reason) internal pure {
        assembly { revert(add(reason, 32), mload(reason)) }
    }

    /// @dev Returns false if the subvault exchange rate would cause the deposit path to overflow
    ///      or yield 0 shares. Withdraw and drain paths are naturally bounded and never overflow.
    function _rebalanceWillOverflow() internal view returns (bool) {
        uint64 alloc = vault.targetAllocationWad();
        if (alloc == 0) return true; // drain path — always safe

        uint256 idle = token.balanceOf(address(vault));
        uint256 total = vault.totalAssets();
        uint256 idleTarget = (total * (1e18 - alloc)) / 1e18;

        if (idle <= idleTarget) return true; // withdraw path - always safe

        // Deposit path: shares = depositAmount * subSupply / subAssets
        uint256 depositAmount = idle - idleTarget;
        uint256 subSupply = subVault.totalSupply();

        // Overflow: result exceeds uint256 when supply/assets ratio is too large
        if (type(uint256).max / subSupply < depositAmount) return false;
        return true;
    }

    function _errorSelector(bytes memory reason) internal pure returns (bytes4 sel) {
        if (reason.length >= 4) {
            assembly { sel := mload(add(reason, 32)) }
        }
    }

    function _rebalanceSlippage() internal view returns (int256) {
        uint64 alloc = vault.targetAllocationWad();
        if (alloc == 0) return int256(0);
        uint256 idle = token.balanceOf(address(vault));
        uint256 idleTarget = ((vault.totalAssets() + 1) * (1e18 - alloc)) / 1e18;
        return idle > idleTarget ? type(int248).min : int256(0);
    }

    function _rebalanceToZero() internal returns (bool skip) {
        if (vault.targetAllocationWad() != 0) {
            vault.setTargetAllocationWad(0);
        }

        uint256 shareBalance = vault.subVault().balanceOf(address(vault));
        if (shareBalance == 0) return false;

        uint256 maxRedeem = vault.subVault().maxRedeem(address(vault));
        if (maxRedeem == 0) revert("maxRedeem should not be zero");

        uint256 iterationsRequired = (shareBalance) / maxRedeem + 1;

        // set some reasonable upper bound on iterations to prevent infinite loop
        if (iterationsRequired > 50) {
            _clearAllLimits();
            iterationsRequired = (shareBalance) / vault.subVault().maxRedeem(address(vault)) + 1;
            require(iterationsRequired == 2, "too many iterations required to rebalance to zero");
        }

        for (uint256 i = 0; i < iterationsRequired && vault.subVault().balanceOf(address(vault)) != 0; i++) {
            vm.warp(block.timestamp + 2);
            vm.prank(keeper);
            vault.rebalance(0);
        }

        uint256 shareBalanceAfter = vault.subVault().balanceOf(address(vault));
        assertEq(shareBalanceAfter, 0, "should have redeemed all shares after iterations");
    }

    function _mintAndDeposit(uint256 amount) internal returns (uint256) {
        vm.startPrank(user);
        token.mintAmount(amount);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount);
        vm.stopPrank();
        return shares;
    }

    function _rebalanceAcceptTargetMetAndImpossibleExchRate() internal {
        vm.warp(block.timestamp + 2);
        vm.startPrank(keeper);
        try vault.rebalance(_rebalanceSlippage()) {}
        catch (bytes memory reason) {
            bytes4 sel = _errorSelector(reason);
            if (sel == MasterVault.RebalanceExchRateTooLow.selector) {
                (, int256 deltaAssets, uint256 subVaultShares) = abi.decode(_sliceMemoryBytes(reason, 4), (int256, int256, uint256));
                if (deltaAssets != 0 && subVaultShares != 0) {
                    _revert(reason);
                }
            }
            else if (sel != MasterVault.TargetAllocationMet.selector) {
                _revert(reason);
            }
        }
        vm.stopPrank();
    }

    function _sliceMemoryBytes(bytes memory x, uint256 start) internal view returns (bytes memory result) {
        return this.sliceCalldataBytes(x, start);
    }

    function sliceCalldataBytes(bytes calldata x, uint256 start) external pure returns (bytes memory) {
        return x[start:];
    }

    function _rand() internal returns (uint256) {
        random = uint256(keccak256(abi.encode(random)));
        return random;
    }
}

/// @notice Stateful invariant tests for MasterVault.
/// @dev    Setup deploys the vault via factory, a FuzzSubVault as the active subvault,
///         grants all roles, and targets the handler contract for fuzzer calls.
contract MasterVaultInvariant is BaseMasterVaultInvariant {
    function _createHandler() internal virtual override returns (address) {
        return address(new MasterVaultWithManipulationHandler(vault, subVault, token, user, keeper));
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

    /// @notice A deposit-redeem round-trip must never extract value.
    /// @dev    At any reachable state (arbitrary exchange rates from handler actions),
    ///         depositing X and immediately redeeming should return <= X.
    ///         Catches: share pricing rounding that favors depositor over vault.
    function invariant_depositRedeemNoValueExtraction() public {
        uint256 depositAmount = bound(MasterVaultHandler(handler).random(), 1, 1e18);
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

    /// @notice Redeeming shares must never return more than 1:1 (i.e. assets <= shares / 1e6).
    /// @dev    The ideal rate is the ceiling. Profit goes to beneficiary, not share holders.
    ///         Catches: share pricing bugs that let users extract more than they deposited.
    function invariant_redeemRateNeverAbovePar() public {
        _clearAllLimits();
        subVault.setWithdrawErrorWad(0);

        uint256 userShares = vault.balanceOf(user);
        if (userShares == 0) return;

        uint256 sharesToRedeem = bound(MasterVaultHandler(handler).random(), 1, userShares);
        uint256 balBefore = token.balanceOf(user);
        vm.prank(user);
        vault.redeem(sharesToRedeem, 0);
        uint256 assetsReceived = token.balanceOf(user) - balBefore;

        assertLe(assetsReceived * DEAD_SHARES, sharesToRedeem, "redeem rate exceeded 1:1");
    }

    /// @notice A rebalance must not change totalAssets (within tolerable error)
    /// @dev    Rebalancing can lose up to 1 subvault share's worth of value
    function invariant_rebalancePreservesTotalAssets() public {
        _clearAllLimits();
        _clearAllRoundingError();

        if (!_rebalanceWillOverflow()) return;

        uint256 totalBefore = vault.totalAssets();
        uint256 subVaultTotalAssetsBefore = vault.subVault().totalAssets();
        uint256 subVaultTotalSupplyBefore = vault.subVault().totalSupply();
        uint256 subVaultPPS = subVaultTotalAssetsBefore / subVaultTotalSupplyBefore;

        _rebalanceAcceptTargetMetAndImpossibleExchRate();

        uint256 totalAfter = vault.totalAssets();
        assertLe(totalAfter, totalBefore, "rebalance created value");
        assertGe(totalAfter + subVaultPPS, totalBefore, "rebalance lost more than subVaultPPS");
    }

    /// @notice Once target allocation is reached, further rebalances revert with TargetAllocationMet.
    /// @dev    Catches: oscillating rebalances, tolerance band not working.
    function invariant_rebalanceIdempotent() public {
        _clearAllLimits();
        _clearAllRoundingError();

        if (!_rebalanceWillOverflow()) return;

        // First rebalance to reach target
        _rebalanceAcceptTargetMetAndImpossibleExchRate();

        // recheck since first rebalance may have shifted the band into deposit territory
        // this is not an issue because it involves the mastervault totalAssets correctly changing
        if (!_rebalanceWillOverflow()) return;

        // Second rebalance must not succeed
        vm.warp(block.timestamp + 2);
        vm.startPrank(keeper);
        try vault.rebalance(_rebalanceSlippage()) {
            revert("second rebalance succeeded when target allocation met");
        }
        catch (bytes memory reason) {
            bytes4 sel = _errorSelector(reason);
            if (sel != MasterVault.TargetAllocationMet.selector && sel != MasterVault.RebalanceExchRateTooLow.selector) {
                _revert(reason);
            }
        }
        vm.stopPrank();
    }

    /// @dev We can lose up to 1 subVault share worth of value
    function invariant_feeDistributionCantCauseInsolvency() public {
        _clearAllLimits();
        _clearAllRoundingError();
        if (vault.totalAssets() * DEAD_SHARES < vault.totalSupply()) {
            return;
        }
        uint256 subVaultPPS = vault.subVault().totalAssets() / vault.subVault().totalSupply();
        vm.prank(keeper);
        try vault.distributePerformanceFee() {} catch {}
        assertGe((vault.totalAssets() + subVaultPPS) * DEAD_SHARES, vault.totalSupply(), "vault became insolvent after fee distribution");
    }

    function invariant_noDonationAttackWhenSolvent() public {
        if (vault.totalAssets() * DEAD_SHARES < vault.totalSupply()) {
            return;
        }

        random = MasterVaultHandler(handler).random();
        uint256 userDepositAmount = bound(_rand(), 1, 1e18);
        uint256 snapshot = vm.snapshot();
        uint256 sharesRecvBefore = _mintAndDeposit(userDepositAmount);
        vm.revertTo(snapshot);

        // attacker deposit
        _mintAndDeposit(bound(_rand(), 1, 1e18));

        // attacker donate
        vm.prank(address(vault));
        token.mintAmount(bound(_rand(), 1, 1e18));

        // user deposit
        uint256 sharesRecvAfter = _mintAndDeposit(userDepositAmount);

        // make sure user does not lose
        assertGe(sharesRecvAfter, sharesRecvBefore, "user received fewer shares after attacker donation");
    }

    function invariant_donationAttackNotProfitable() public {
        random = MasterVaultHandler(handler).random();

        uint256 attackerDepositAmount = bound(_rand(), 1, 1e18);
        uint256 attackerDonationAmount = bound(_rand(), 1, 1e18);
        uint256 userDepositAmount = bound(_rand(), 1, 1e18);

        // attacker deposit
        uint256 attackerShares = _mintAndDeposit(attackerDepositAmount);
        // attacker donate
        vm.prank(address(vault));
        token.mintAmount(attackerDonationAmount);
        // user deposit
        _mintAndDeposit(userDepositAmount);

        // attacker redeem
        // make sure attacker does not profit
        vm.prank(user);
        assertLe(vault.redeem(attackerShares, 0), attackerDepositAmount + attackerDonationAmount, "attacker made profit from donation attack");
    }
}

contract MasterVaultNoManipulationInvariant is BaseMasterVaultInvariant {
    function _createHandler() internal virtual override returns (address) {
        return address(new MasterVaultHandler(vault, subVault, token, user, keeper));
    }

    /// @notice When no rounding errors injected, assets cover principal.
    /// @dev    Under normal operation, the vault should never become insolvent.
    function invariant_solvency() public {
        assertGe(vault.totalAssets() * DEAD_SHARES, vault.totalSupply(), "insolvent without manipulation");
    }

    /// @notice Performance fees must never exceed reported profit.
    function invariant_feeDistributionBounded() public {
        subVault.setMaxWithdrawLimit(type(uint256).max);
        uint256 roundingTolerance = MasterVaultHandler(handler).ghost_callCount(MasterVaultHandler.deposit.selector) + MasterVaultHandler(handler).ghost_callCount(MasterVaultHandler.redeem.selector);
        vm.prank(keeper);
        vault.distributePerformanceFee();
        assertLe(
            token.balanceOf(vault.beneficiary()),
            MasterVaultHandler(handler).ghost_profit() + roundingTolerance,
            "fees extracted exceed profit"
        );
    }
}
