// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {MasterVaultRoles} from "./MasterVaultRoles.sol";
import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    AccessControlUpgradeable,
    IAccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IGatewayRouter} from "../gateway/IGatewayRouter.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice MasterVault is a metavault that deposits assets to an admin defined ERC4626 compliant subVault.
/// @dev    The MasterVault keeps some fraction of assets idle and deposits the rest into the subVault to earn yield.
///         A 100% performance fee can be enabled/disabled by the vault manager, and are collected on demand.
///         The MasterVault mitigates the "first depositor" problem by adding 18 decimals to the underlying asset.
///         i.e. if the underlying asset has 6 decimals, the MasterVault will have 24 decimals.
///
///         For a subVault to be compatible with the MasterVault, it must adhere to the following:
///         - previewMint and previewDeposit must not be manipulable
///         - previewMint and previewDeposit must be roughly linear with respect to amounts.
///           Superlinear previewMint/previewDeposit may cause the MasterVault to overcharge on deposits and underpay on withdrawals.
///         - must not have deposit / withdrawal fees (because rebalancing can happen frequently)
///
///         Roles are primarily managed via an external MasterVaultRoles contract,
///         which allows multiple vaults to share a common roles registry.
///         Individual MasterVaults can also have local roles assigned, which are checked in addition to the roles registry.
///         If an account is granted a role in either the local vault or the roles registry, it is considered to have that role.
contract MasterVault is
    MasterVaultRoles,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Extra decimals added to the ERC20 decimals of the underlying asset to determine the decimals of the MasterVault
    /// @dev    This is done to mitigate the "first depositor" problem described in the OpenZeppelin ERC4626 documentation.
    ///         See https://docs.openzeppelin.com/contracts/5.x/erc4626 for more details on the mitigation.
    ///         Should be << 18 to maintain precision in profit calculations. (see principalPriceWad)
    ///         Should be > 0 to meaningfully mitigate the first depositor problem.
    uint8 public constant EXTRA_DECIMALS = 6;

    /// @notice Default minimum rebalance amount
    uint120 public constant DEFAULT_MIN_REBALANCE_AMOUNT = 1e6;

    /// @notice Minimum rebalance cooldown in seconds
    uint32 public constant MIN_REBALANCE_COOLDOWN = 1;

    error SubVaultAssetMismatch();
    error PerformanceFeeDisabled();
    error BeneficiaryNotSet();
    error NonZeroTargetAllocation(uint256 targetAllocationWad);
    error NonZeroSubVaultShares(uint256 subVaultShares);
    error NotGateway(address caller);
    error SubVaultNotWhitelisted(address subVault);
    error RebalanceCooldownNotMet(uint256 timeSinceLastRebalance, uint256 cooldownRequired);
    error TargetAllocationMet();
    error RebalanceAmountTooSmall(
        bool isDeposit, uint256 amount, uint256 desiredAmount, uint256 minimumRebalanceAmount
    );
    error PerformanceFeeUnchanged(bool enabled);
    error RebalanceCooldownTooLow(uint32 requested, uint32 minimum);

    /*
    Storage layout notes:

    We have three hot paths that should be optimized:
    - deposit
    - redeem
    - rebalance

    Below is the list of state variables accessed in each hot path.
    They are listed to see which variables should be packed together.

    deposit:
    - address subVault ------------------| <- these three show up in each path, so pack them together
    - bool enablePerformanceFee          |
    - uint88 principalPriceWad ----------|
    - address asset
    - address gatewayRouter
    redeem:
    - address subVault ------------------|
    - bool enablePerformanceFee          |
    - uint88 principalPriceWad ----------|
    - address asset
    rebalance:
    - address subVault ------------------|
    - bool enablePerformanceFee          |
    - uint88 principalPriceWad ----------|
    - uint40 lastRebalanceTime (r/w) ----| <- timestamp, uint40 gives up to year 36812
    - uint32 rebalanceCooldown           | <- timer, uint32 gives up to ~136 years
    - uint64 targetAllocationWad         | <- <=1e18, so uint64
    - uint120 minimumRebalanceAmount ----| <- uint120 remaining, should be enough for any asset
    - address asset
    - address rolesRegistry
    */

    /// @notice The current subvault. Assets are deposited into this vault to earn yield.
    IERC4626 public subVault;

    /// @notice Flag indicating if performance fee is enabled
    bool public enablePerformanceFee;

    /// @notice The price of masterVault shares (in assets per share times 1e18)
    ///         at the time of turning on performance fees.
    ///         It is used to calculate profit for performance fee distribution.
    ///         It's akin to a price water mark.
    /// @dev    When performance fees are disabled, principalPriceWad is 0
    ///         88 bits is enough size. The initial value is "1 to 1", which is 1e18 / 1e6 = 1e12.
    ///         To overflow, the principal price must increase by 2^88 / 1e12 = 3.1e14 times,
    ///         which is unrealistic.
    uint88 public principalPriceWad;

    /// @notice Timestamp of the last rebalance
    uint40 public lastRebalanceTime;

    /// @notice The minimum time in seconds that must pass between rebalances
    /// @dev    Defaults to 1 second. Cannot be 0.
    uint32 public rebalanceCooldown;

    /// @notice Target allocation of assets to keep in the subvault, expressed in wad (1e18 = 100%)
    ///         Rebalances will attempt to maintain this allocation.
    uint64 public targetAllocationWad;

    /// @notice The minimum amount of assets that must be deposited/withdrawn when rebalancing.
    ///         If the amount to deposit or withdraw is less than this amount, no action is taken.
    ///         This prevents dust rebalances.
    /// @dev    Defaults to 1e6, but can be set by the vault manager to any value.
    uint120 public minimumRebalanceAmount;

    /// @notice The underlying asset of the vault
    IERC20 public asset;

    /// @notice Gateway router used to verify deposit calls
    IGatewayRouter public gatewayRouter;

    /// @notice Set of whitelisted subvaults
    EnumerableSet.AddressSet private _whitelistedSubVaults;

    /// @notice Roles registry contract. This contract is checked in addition to local roles.
    ///         If an account has a role in either the local vault or the roles registry, it is considered to have that role.
    MasterVaultRoles public rolesRegistry;

    /// @notice Address that receives performance fees
    address public beneficiary;

    event SubvaultChanged(address indexed oldSubvault, address indexed newSubvault);
    event PerformanceFeeToggled(bool enabled);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event MinimumRebalanceAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event PerformanceFeesWithdrawn(
        address indexed beneficiary, uint256 amountTransferred, uint256 amountWithdrawn
    );
    event Rebalanced(bool deposited, uint256 desiredAmount, uint256 actualAmount);
    event SubVaultWhitelistUpdated(address indexed subVault, bool whitelisted);
    event RebalanceCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);

    function initialize(
        IERC4626 _subVault,
        string memory _name,
        string memory _symbol,
        MasterVaultRoles _rolesRegistry,
        IGatewayRouter _gatewayRouter
    ) external initializer {
        __ERC20_init(_name, _symbol);

        asset = IERC20(address(_subVault.asset()));
        rolesRegistry = _rolesRegistry;

        // call decimals() to ensure underlying has reasonable decimals and we won't have overflow
        decimals();

        __ReentrancyGuard_init();
        __Pausable_init();
        __MasterVaultRoles_init();

        gatewayRouter = _gatewayRouter;

        // mint some dead shares to avoid first depositor issues
        // for more information on the mitigation:
        // https://web.archive.org/web/20250609034056/https://docs.openzeppelin.com/contracts/4.x/erc4626#fees
        _mint(address(1), 10 ** EXTRA_DECIMALS);

        asset.safeApprove(address(_subVault), type(uint256).max);

        subVault = _subVault;
        _setSubVaultWhitelist(address(_subVault), true);

        minimumRebalanceAmount = DEFAULT_MIN_REBALANCE_AMOUNT;
        rebalanceCooldown = MIN_REBALANCE_COOLDOWN;
    }

    /// @notice Modifier to ensure only the registered gateway can call
    modifier onlyGateway() {
        if (gatewayRouter.getGateway(address(asset)) != msg.sender) {
            revert NotGateway(msg.sender);
        }
        _;
    }

    /// @notice Deposit some underlying assets in exchange for vault shares
    /// @dev    Can only be called by the token bridge gateway
    /// @param  assets The amount of underlying assets to deposit
    /// @return shares The amount of vault shares minted to the depositor
    function deposit(uint256 assets)
        external
        whenNotPaused
        nonReentrant
        onlyGateway
        returns (uint256 shares)
    {
        shares = _convertToSharesRoundDown(assets);
        _mint(msg.sender, shares);
        asset.safeTransferFrom(msg.sender, address(this), assets);
    }

    /// @notice Redeem some vault shares in exchange for underlying assets
    /// @dev    Anyone can redeem their shares at any time
    /// @param  shares The amount of vault shares to redeem
    /// @return assets The amount of underlying assets transferred to the redeemer
    function redeem(uint256 shares) external whenNotPaused nonReentrant returns (uint256 assets) {
        assets = _convertToAssetsRoundDown(shares);

        uint256 idleAssets = asset.balanceOf(address(this));
        if (idleAssets < assets) {
            uint256 assetsToWithdraw = assets - idleAssets;
            subVault.withdraw(assetsToWithdraw, address(this), address(this));
        }

        _burn(msg.sender, shares);
        asset.safeTransfer(msg.sender, assets);
    }

    /// @notice Rebalance assets between idle and the subvault to maintain target allocation
    /// @dev    Will revert if the cooldown period has not passed
    ///         Will revert if the target allocation is already met
    ///         Will revert if the amount to deposit/withdraw is less than the minimumRebalanceAmount.
    function rebalance() external whenNotPaused nonReentrant onlyRole(KEEPER_ROLE) {
        // Check cooldown
        uint256 timeSinceLastRebalance = block.timestamp - lastRebalanceTime;
        if (timeSinceLastRebalance < rebalanceCooldown) {
            revert RebalanceCooldownNotMet(timeSinceLastRebalance, rebalanceCooldown);
        }

        uint256 totalAssetsUp = _totalAssetsLessProfit(MathUpgradeable.Rounding.Up);
        uint256 totalAssetsDown = _totalAssetsLessProfit(MathUpgradeable.Rounding.Down);
        uint256 idleTargetUp =
            totalAssetsUp.mulDiv(1e18 - targetAllocationWad, 1e18, MathUpgradeable.Rounding.Up);
        uint256 idleTargetDown =
            totalAssetsDown.mulDiv(1e18 - targetAllocationWad, 1e18, MathUpgradeable.Rounding.Down);
        uint256 idleBalance = asset.balanceOf(address(this));

        if (idleTargetDown <= idleBalance && idleBalance <= idleTargetUp) {
            revert TargetAllocationMet();
        }

        if (idleBalance < idleTargetDown) {
            // we need to withdraw from subvault
            uint256 desiredWithdraw = idleTargetDown - idleBalance;
            uint256 maxWithdrawable = subVault.maxWithdraw(address(this));
            uint256 withdrawAmount =
                desiredWithdraw < maxWithdrawable ? desiredWithdraw : maxWithdrawable;
            if (withdrawAmount < minimumRebalanceAmount) {
                revert RebalanceAmountTooSmall(
                    false, withdrawAmount, desiredWithdraw, minimumRebalanceAmount
                );
            }
            subVault.withdraw(withdrawAmount, address(this), address(this));
            emit Rebalanced(false, desiredWithdraw, withdrawAmount);
        } else {
            // we need to deposit into subvault
            uint256 desiredDeposit = idleBalance - idleTargetUp;
            uint256 maxDepositable = subVault.maxDeposit(address(this));
            uint256 depositAmount =
                desiredDeposit < maxDepositable ? desiredDeposit : maxDepositable;
            if (depositAmount < minimumRebalanceAmount) {
                revert RebalanceAmountTooSmall(
                    true, depositAmount, desiredDeposit, minimumRebalanceAmount
                );
            }
            subVault.deposit(depositAmount, address(this));
            emit Rebalanced(true, desiredDeposit, depositAmount);
        }

        lastRebalanceTime = uint40(block.timestamp);
    }

    /// @notice Distribute performance fees to the beneficiary
    function distributePerformanceFee() external whenNotPaused nonReentrant onlyRole(KEEPER_ROLE) {
        _distributePerformanceFee();
    }

    /// @notice Set a new subvault
    /// @dev    Target allocation must be zero and there must be no existing subvault shares held.
    ///         The new subvault must be whitelisted and have the same asset as this MasterVault.
    /// @param  _subVault The subvault to set. Must be an ERC4626 vault with the same asset as this MasterVault.
    function setSubVault(IERC4626 _subVault) external nonReentrant onlyRole(GENERAL_MANAGER_ROLE) {
        if (!isSubVaultWhitelisted(address(_subVault))) {
            revert SubVaultNotWhitelisted(address(_subVault));
        }
        if (address(_subVault.asset()) != address(asset)) revert SubVaultAssetMismatch();

        // we ensure target allocation is zero, therefore the master vault holds no subvault shares
        if (targetAllocationWad != 0) revert NonZeroTargetAllocation(targetAllocationWad);

        // sanity check to ensure we have zero subvault shares before changing
        if (subVault.balanceOf(address(this)) != 0) {
            revert NonZeroSubVaultShares(subVault.balanceOf(address(this)));
        }

        address oldSubVault = address(subVault);
        subVault = _subVault;

        if (oldSubVault != address(0)) asset.safeApprove(address(oldSubVault), 0);
        asset.safeApprove(address(_subVault), type(uint256).max);

        emit SubvaultChanged(oldSubVault, address(_subVault));
    }

    /// @notice Set the target allocation of assets to keep in the subvault
    /// @dev    Target allocation must be between 0 and 1e18 (100%).
    /// @param  _targetAllocationWad The target allocation in wad (1e18 = 100%)
    function setTargetAllocationWad(uint64 _targetAllocationWad)
        external
        nonReentrant
        onlyRole(GENERAL_MANAGER_ROLE)
    {
        require(_targetAllocationWad <= 1e18, "Target allocation must be <= 100%");
        require(targetAllocationWad != _targetAllocationWad, "Allocation unchanged");
        targetAllocationWad = _targetAllocationWad;
    }

    /// @notice Set the minimum amount of assets that must be deposited/withdrawn when rebalancing
    /// @param _minimumRebalanceAmount The minimum amount of assets for rebalancing
    function setMinimumRebalanceAmount(uint120 _minimumRebalanceAmount)
        external
        onlyRole(GENERAL_MANAGER_ROLE)
    {
        uint256 oldAmount = minimumRebalanceAmount;
        minimumRebalanceAmount = _minimumRebalanceAmount;
        emit MinimumRebalanceAmountUpdated(oldAmount, _minimumRebalanceAmount);
    }

    /// @notice Set the rebalance cooldown period
    /// @param _rebalanceCooldown The minimum time in seconds that must pass between rebalances
    function setRebalanceCooldown(uint32 _rebalanceCooldown)
        external
        onlyRole(GENERAL_MANAGER_ROLE)
    {
        if (_rebalanceCooldown < MIN_REBALANCE_COOLDOWN) {
            revert RebalanceCooldownTooLow(_rebalanceCooldown, MIN_REBALANCE_COOLDOWN);
        }
        uint256 oldCooldown = rebalanceCooldown;
        rebalanceCooldown = _rebalanceCooldown;
        emit RebalanceCooldownUpdated(oldCooldown, _rebalanceCooldown);
    }

    /// @notice Toggle performance fee collection on/off
    ///         When enabling, principalPriceWad snaps to the current price. 
    ///         When price increases afterwards, profit is earned for the beneficiary.
    ///         If disabling, any pending performance fees are distributed immediately.
    /// @param enabled True to enable performance fees, false to disable
    function setPerformanceFee(bool enabled) external nonReentrant onlyRole(FEE_MANAGER_ROLE) {
        if (enablePerformanceFee == enabled) {
            revert PerformanceFeeUnchanged(enabled);
        }

        // reset principalPriceWad to current totalAssets when enabling performance fee
        if (enabled) {
            // round up to avoid overcounting profit
            // this works against the fee collector
            principalPriceWad = uint88(
                _totalAssets(MathUpgradeable.Rounding.Up)
                    .mulDiv(1e18, totalSupply(), MathUpgradeable.Rounding.Up)
            );
        } else {
            _distributePerformanceFee();
            principalPriceWad = 0;
        }

        enablePerformanceFee = enabled;

        emit PerformanceFeeToggled(enabled);
    }

    /// @notice Set the beneficiary address for performance fees
    /// @param newBeneficiary Address to receive performance fees
    function setBeneficiary(address newBeneficiary) external onlyRole(FEE_MANAGER_ROLE) {
        address oldBeneficiary = beneficiary;
        beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(oldBeneficiary, newBeneficiary);
    }

    /// @notice Add or remove a subvault from the whitelist. 
    ///         Malicious, misconfigured, or buggy subVaults may cause total loss of funds.
    /// @param _subVault The subvault address to update
    /// @param _whitelisted True to whitelist the subvault, false to remove it
    function setSubVaultWhitelist(address _subVault, bool _whitelisted)
        external
        onlyRole(ADMIN_ROLE)
    {
        _setSubVaultWhitelist(_subVault, _whitelisted);
    }

    /// @notice Check if a subvault is whitelisted
    /// @param _subVault The subvault address to check
    /// @return True if the subvault is whitelisted
    function isSubVaultWhitelisted(address _subVault) public view returns (bool) {
        return _whitelistedSubVaults.contains(_subVault);
    }

    /// @notice Get all whitelisted subvaults
    /// @return Array of all whitelisted subvault addresses
    function whitelistedSubVaults() external view returns (address[] memory) {
        return _whitelistedSubVaults.values();
    }

    /// @notice Pause deposits and withdrawals
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause deposits and withdrawals
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Overridden to add EXTRA_DECIMALS to the underlying asset decimals
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(address(asset)).decimals() + EXTRA_DECIMALS;
    }

    /// @notice Get the total assets managed by the vault
    function totalAssets() public view returns (uint256) {
        return _totalAssets(MathUpgradeable.Rounding.Down);
    }

    /// @notice Get the total profit earned by the vault
    /// @dev    When performance fees are disabled, this will always return totalAssets
    function totalProfit() public view returns (uint256) {
        uint256 __totalAssets = _totalAssets(MathUpgradeable.Rounding.Down);
        uint256 __totalPrincipal = _totalPrincipal(MathUpgradeable.Rounding.Up);
        return __totalAssets > __totalPrincipal ? __totalAssets - __totalPrincipal : 0;
    }

    /// @dev Overriden to check MasterVaultRoles registry in addition to local roles
    function hasRole(bytes32 role, address account)
        public
        view
        virtual
        override(AccessControlUpgradeable, IAccessControlUpgradeable)
        returns (bool)
    {
        return super.hasRole(role, account) || rolesRegistry.hasRole(role, account);
    }

    /// @dev Internal fee distribution function
    ///      Will revert if performance fees are disabled or beneficiary is not set
    function _distributePerformanceFee() internal {
        if (!enablePerformanceFee) revert PerformanceFeeDisabled();
        if (beneficiary == address(0)) {
            revert BeneficiaryNotSet();
        }

        uint256 profit = totalProfit();
        if (profit == 0) return;

        uint256 totalIdle = asset.balanceOf(address(this));

        uint256 amountToTransfer = profit <= totalIdle ? profit : totalIdle;
        uint256 amountToWithdraw = profit - amountToTransfer;

        if (amountToTransfer > 0) {
            asset.safeTransfer(beneficiary, amountToTransfer);
        }
        if (amountToWithdraw > 0) {
            subVault.withdraw(amountToWithdraw, beneficiary, address(this));
        }

        emit PerformanceFeesWithdrawn(beneficiary, amountToTransfer, amountToWithdraw);
    }

    /// @dev Internal total assets function supporting a specific rounding direction
    function _totalAssets(MathUpgradeable.Rounding rounding) internal view returns (uint256) {
        return asset.balanceOf(address(this))
            + _subVaultSharesToAssets(subVault.balanceOf(address(this)), rounding);
    }

    /// @dev Internal total principal function supporting a specific rounding direction
    ///      When performance fees are disabled, total principal is 0
    ///      When performance fees are enabled, total principal is principalPriceWad * totalSupply / 1e18
    function _totalPrincipal(MathUpgradeable.Rounding rounding) internal view returns (uint256) {
        return uint256(principalPriceWad).mulDiv(totalSupply(), 1e18, rounding);
    }

    /// @dev Converts assets to shares using totalSupply and totalAssetsLessProfit, rounding down
    function _convertToSharesRoundDown(uint256 assets) internal view returns (uint256 shares) {
        // we add one as part of the first deposit mitigation
        // see for details: https://docs.openzeppelin.com/contracts/5.x/erc4626
        return assets.mulDiv(
            totalSupply(),
            _totalAssetsLessProfit(MathUpgradeable.Rounding.Up) + 1,
            MathUpgradeable.Rounding.Down
        );
    }

    /// @dev Converts shares to assets using totalSupply and totalAssetsLessProfit, rounding down
    function _convertToAssetsRoundDown(uint256 shares) internal view returns (uint256 assets) {
        // we add one as part of the first deposit mitigation
        // see for details: https://docs.openzeppelin.com/contracts/5.x/erc4626
        return shares.mulDiv(
            _totalAssetsLessProfit(MathUpgradeable.Rounding.Down) + 1,
            totalSupply(),
            MathUpgradeable.Rounding.Down
        );
    }

    /// @dev Gets total assets less profit, supporting a specific rounding direction
    function _totalAssetsLessProfit(MathUpgradeable.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        uint256 __totalAssets = _totalAssets(rounding);
        uint256 __totalPrincipal = _totalPrincipal(rounding);
        if (enablePerformanceFee && __totalAssets > __totalPrincipal) {
            return __totalPrincipal;
        }
        return __totalAssets;
    }

    /// @dev Converts subvault shares to assets using the subvault's preview functions
    ///      If rounding is Up, uses previewMint; if Down, uses previewRedeem
    function _subVaultSharesToAssets(uint256 subShares, MathUpgradeable.Rounding rounding)
        internal
        view
        returns (uint256 assets)
    {
        return rounding == MathUpgradeable.Rounding.Up
            ? subVault.previewMint(subShares)
            : subVault.previewRedeem(subShares);
    }

    /// @dev Helper to add/remove a subvault from the whitelist
    function _setSubVaultWhitelist(address _subVault, bool _whitelisted) internal {
        _whitelisted
            ? _whitelistedSubVaults.add(_subVault)
            : _whitelistedSubVaults.remove(_subVault);
        emit SubVaultWhitelistUpdated(_subVault, _whitelisted);
    }
}
