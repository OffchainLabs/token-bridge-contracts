// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {MasterVaultRoles} from "./MasterVaultRoles.sol";
import {ERC20Upgradeable} from "contracts/tokenbridge/libraries/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    AccessControlUpgradeable,
    IAccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IGatewayRouter} from "../gateway/IGatewayRouter.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IMasterVault} from "./IMasterVault.sol";

/// @notice MasterVault is a metavault that deposits assets to an admin defined ERC4626 compliant subVault.
/// @dev    The MasterVault keeps some fraction of assets idle and deposits the rest into the subVault to earn yield.
///         A 100% performance fee is always enabled and collected on demand.
///         The MasterVault mitigates the "first depositor" problem via dead shares (1 share minted to address(1))
///         and a virtual asset offset (+1 in _totalAssets). The _haveLoss() check ensures that when solvent,
///         conversions use a fixed 1:1 ratio immune to donation manipulation.
///
///         For a subVault to be compatible with the MasterVault, it must adhere to the following:
///         - must be fully ERC4626 compliant
///         - previewMint and previewDeposit must not be manipulable
///         - deposit and withdraw must not be manipulable / sandwichable
///         - previewMint and previewDeposit must be roughly linear with respect to amounts.
///           Superlinear previewMint or sublinear previewDeposit may cause the MasterVault to overcharge on deposits and underpay on withdrawals.
///         - must not have deposit / withdrawal fees (because rebalancing can happen frequently)
///
///         Roles are primarily managed via an external MasterVaultRoles contract,
///         which allows multiple vaults to share a common roles registry.
///         Individual MasterVaults can also have local roles assigned, which are checked in addition to the roles registry.
///         If an account is granted a role in either the local vault or the roles registry, it is considered to have that role.
contract MasterVault is
    IMasterVault,
    MasterVaultRoles,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    /// @notice Default minimum rebalance amount
    uint120 public constant DEFAULT_MIN_REBALANCE_AMOUNT = 1e6;

    /// @notice Minimum rebalance cooldown in seconds
    uint32 public constant MIN_REBALANCE_COOLDOWN = 1;

    error SubVaultAssetMismatch();
    error BeneficiaryNotSet();
    error NotKeeper();
    error NonZeroTargetAllocation(uint256 targetAllocationWad);
    error NonZeroSubVaultShares(uint256 subVaultShares);
    error NotGateway(address caller);
    error SubVaultNotWhitelisted(address subVault);
    error RebalanceCooldownNotMet(uint256 timeSinceLastRebalance, uint256 cooldownRequired);
    error TargetAllocationMet();
    error RebalanceAmountTooSmall(
        bool isDeposit, uint256 amount, uint256 desiredAmount, uint256 minimumRebalanceAmount
    );
    error RebalanceCooldownTooLow(uint32 requested, uint32 minimum);
    error RebalanceExchRateTooLow(
        int256 minExchRateWad, int256 deltaAssets, uint256 subVaultShares
    );
    error RebalanceExchRateWrongSign(int256 minExchRateWad);
    error InsufficientAssets(uint256 assets, uint256 minAssets);

    /*
    Storage layout notes:

    We have three hot paths that should be optimized:
    - deposit
    - redeem
    - rebalance

    Below is the list of state variables accessed in each hot path.
    They are listed to see which variables should be packed together.

    deposit:
    - address subVault --------------------| <- this appears in most calls, it will use a full slot even tho it needs only 20 bytes
    - address asset
    - address gatewayRouter
    redeem:
    - address subVault --------------------|
    - address asset
    rebalance:
    - address subVault --------------------|
    - uint40 lastRebalanceTime (r/w) ------| <- timestamp, uint40 gives up to year 36812
    - uint32 rebalanceCooldown             | <- timer, uint32 gives up to ~136 years
    - uint64 targetAllocationWad           | <- <=1e18, so uint64
    - uint120 minimumRebalanceAmount ------| <- uint120 remaining, should be enough for any asset
    - address asset
    - address rolesRegistry
    */

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

    /// @notice The current subvault. Assets are deposited into this vault to earn yield.
    IERC4626 public subVault;

    event SubvaultChanged(address indexed oldSubvault, address indexed newSubvault);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event MinimumRebalanceAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event PerformanceFeesWithdrawn(
        address indexed beneficiary, uint256 amountTransferred, uint256 amountWithdrawn
    );
    event Rebalanced(bool deposited, uint256 desiredAmount, uint256 actualAmount);
    event RebalancedToZero(uint256 shares, uint256 assets);
    event SubVaultWhitelistUpdated(address indexed subVault, bool whitelisted);
    event RebalanceCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
    event TargetAllocationUpdated(uint256 oldAllocation, uint256 newAllocation);

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

        __ReentrancyGuard_init();
        __Pausable_init();
        __MasterVaultRoles_init();

        gatewayRouter = _gatewayRouter;

        // mint some dead shares to avoid first depositor issues
        // for more information on the mitigation:
        // https://web.archive.org/web/20250609034056/https://docs.openzeppelin.com/contracts/4.x/erc4626#fees
        _mint(address(1), 1);

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

    /// @notice Modifier to ensure only keeper
    // if KEEPER_ROLE is granted to address(0), anyone can call
    modifier onlyKeeper() {
        if (!hasRole(KEEPER_ROLE, address(0)) && !hasRole(KEEPER_ROLE, msg.sender)) {
            revert NotKeeper();
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
    /// @param  minAssets Minimum amount of assets to receive (slippage protection), 0 to skip check
    /// @return assets The amount of underlying assets transferred to the redeemer
    function redeem(uint256 shares, uint256 minAssets)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 assets)
    {
        assets = _convertToAssetsRoundDown(shares);
        if (minAssets > 0 && assets < minAssets) {
            revert InsufficientAssets(assets, minAssets);
        }

        uint256 idleAssets = asset.balanceOf(address(this));
        _burn(msg.sender, shares);

        if (idleAssets < assets) {
            uint256 assetsToWithdraw = assets - idleAssets;
            // slither-disable-next-line unused-return
            subVault.withdraw(assetsToWithdraw, address(this), address(this));
        }

        asset.safeTransfer(msg.sender, assets);
    }

    /// @notice Rebalance assets between idle and the subvault to maintain target allocation
    /// @dev    Will revert if the cooldown period has not passed.
    ///         If targetAllocationWad is 0%, attempts to redeem all subvault shares (bypasses minimumRebalanceAmount).
    ///         Otherwise, deposits/withdraws to reach the target, reverting if the target is already met
    ///         or the amount is less than minimumRebalanceAmount.
    /// @param  minExchRateWad Minimum exchange rate (1e18 * deltaAssets / abs(subVaultShares)) for the deposit/withdraw operation
    ///                        Negative indicates a masterVault -> subVault deposit (negative deltaAssets),
    ///                        positive indicates a subVault -> masterVault withdraw (positive deltaAssets).
    // slither-disable-next-line reentrancy-no-eth
    function rebalance(int256 minExchRateWad) external whenNotPaused nonReentrant onlyKeeper {
        uint256 timeSinceLastRebalance = block.timestamp - lastRebalanceTime;
        if (timeSinceLastRebalance < rebalanceCooldown) {
            revert RebalanceCooldownNotMet(timeSinceLastRebalance, rebalanceCooldown);
        }

        if (targetAllocationWad == 0) {
            _rebalanceDrain(minExchRateWad);
        } else {
            _rebalanceToTarget(minExchRateWad);
        }

        lastRebalanceTime = uint40(block.timestamp);
    }

    /// @dev 0% target: redeem all subvault shares. Bypasses minimumRebalanceAmount so dust can be swept.
    function _rebalanceDrain(int256 minExchRateWad) private {
        uint256 subVaultShares = subVault.maxRedeem(address(this));
        if (subVaultShares == 0) revert TargetAllocationMet();

        uint256 assetsReceived = subVault.redeem(subVaultShares, address(this), address(this));
        _validateWithdrawExchRate(minExchRateWad, assetsReceived, subVaultShares);

        emit RebalancedToZero(subVaultShares, assetsReceived);
    }

    /// @dev Deposit to or withdraw from the subvault to reach targetAllocationWad.
    function _rebalanceToTarget(int256 minExchRateWad) private {
        uint256 totalAssetsUp = _totalAssets(MathUpgradeable.Rounding.Up);
        uint256 totalAssetsDown = _totalAssets(MathUpgradeable.Rounding.Down);
        uint256 idleTargetUp =
            totalAssetsUp.mulDiv(1e18 - targetAllocationWad, 1e18, MathUpgradeable.Rounding.Up);
        uint256 idleTargetDown =
            totalAssetsDown.mulDiv(1e18 - targetAllocationWad, 1e18, MathUpgradeable.Rounding.Down);
        uint256 idleBalance = asset.balanceOf(address(this));

        if (idleTargetDown <= idleBalance && idleBalance <= idleTargetUp) {
            revert TargetAllocationMet();
        }

        if (idleBalance < idleTargetDown) {
            uint256 desiredWithdraw = idleTargetDown - idleBalance;
            uint256 maxWithdrawable = subVault.maxWithdraw(address(this));
            uint256 withdrawAmount =
                desiredWithdraw < maxWithdrawable ? desiredWithdraw : maxWithdrawable;

            if (withdrawAmount < minimumRebalanceAmount) {
                revert RebalanceAmountTooSmall(
                    false, withdrawAmount, desiredWithdraw, minimumRebalanceAmount
                );
            }

            uint256 subVaultShares = subVault.withdraw(withdrawAmount, address(this), address(this));
            _validateWithdrawExchRate(minExchRateWad, withdrawAmount, subVaultShares);

            emit Rebalanced(false, desiredWithdraw, withdrawAmount);
        } else {
            uint256 desiredDeposit = idleBalance - idleTargetUp;
            uint256 maxDepositable = subVault.maxDeposit(address(this));
            uint256 depositAmount =
                desiredDeposit < maxDepositable ? desiredDeposit : maxDepositable;

            if (depositAmount < minimumRebalanceAmount) {
                revert RebalanceAmountTooSmall(
                    true, depositAmount, desiredDeposit, minimumRebalanceAmount
                );
            }

            asset.safeIncreaseAllowance(address(subVault), depositAmount);
            uint256 subVaultShares = subVault.deposit(depositAmount, address(this));
            _validateDepositExchRate(minExchRateWad, depositAmount, subVaultShares);

            emit Rebalanced(true, desiredDeposit, depositAmount);
        }
    }

    /// @notice Distribute performance fees to the beneficiary
    function distributePerformanceFee() external whenNotPaused nonReentrant onlyKeeper {
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
        uint256 oldAllocation = targetAllocationWad;
        targetAllocationWad = _targetAllocationWad;
        emit TargetAllocationUpdated(oldAllocation, _targetAllocationWad);
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

    /// @notice Returns the decimals of the underlying asset
    /// @dev    Requires underlying asset to implement IERC20Metadata.decimals()
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(address(asset)).decimals();
    }

    /// @notice Get the total assets managed by the vault
    function totalAssets() public view returns (uint256) {
        return _totalAssets(MathUpgradeable.Rounding.Down);
    }

    /// @notice Get the total profit earned by the vault
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
    ///      Will revert if beneficiary is not set
    function _distributePerformanceFee() internal {
        if (beneficiary == address(0)) {
            revert BeneficiaryNotSet();
        }

        uint256 profit = totalProfit();
        // slither-disable-next-line incorrect-equality
        if (profit == 0) return;

        uint256 totalIdle = asset.balanceOf(address(this));

        uint256 amountToTransfer = profit <= totalIdle ? profit : totalIdle;
        uint256 amountToWithdraw = profit - amountToTransfer;

        if (amountToTransfer > 0) {
            asset.safeTransfer(beneficiary, amountToTransfer);
        }
        if (amountToWithdraw > 0) {
            // slither-disable-next-line unused-return
            subVault.withdraw(amountToWithdraw, beneficiary, address(this));
        }

        emit PerformanceFeesWithdrawn(beneficiary, amountToTransfer, amountToWithdraw);
    }

    /// @dev Internal total assets function supporting a specific rounding direction
    /// We add one as part of the first deposit mitigation.
    /// See for details: https://docs.openzeppelin.com/contracts/5.x/erc4626
    function _totalAssets(MathUpgradeable.Rounding rounding) internal view returns (uint256) {
        return 1 + asset.balanceOf(address(this))
            + _subVaultSharesToAssets(subVault.balanceOf(address(this)), rounding);
    }

    /// @dev Internal total principal function supporting a specific rounding direction
    ///      Total principal equals totalSupply (1:1 share-to-asset ratio when solvent)
    function _totalPrincipal(MathUpgradeable.Rounding) internal view returns (uint256) {
        return totalSupply();
    }

    /// @dev Converts assets to shares, rounding down.
    ///      Uses ideal ratio when solvent, standard formula when in loss.
    function _convertToSharesRoundDown(uint256 assets) internal view returns (uint256 shares) {
        // bias against the depositor by rounding DOWN totalAssets to more easily detect losses
        if (_haveLoss()) {
            // we have losses
            return assets.mulDiv(
                totalSupply(),
                _totalAssets(MathUpgradeable.Rounding.Up),
                MathUpgradeable.Rounding.Down
            );
        }
        // no losses, use ideal 1:1 ratio
        return assets;
    }

    /// @dev Converts shares to assets, rounding down.
    ///      Uses ideal ratio when solvent, standard formula when in loss.
    function _convertToAssetsRoundDown(uint256 shares) internal view returns (uint256 assets) {
        // bias against the depositor by rounding DOWN totalAssets to more easily detect losses
        if (_haveLoss()) {
            // we have losses
            return shares.mulDiv(
                _totalAssets(MathUpgradeable.Rounding.Down),
                totalSupply(),
                MathUpgradeable.Rounding.Down
            );
        }
        // no losses, use ideal 1:1 ratio
        return shares;
    }

    /// @dev Whether the vault has losses
    function _haveLoss() internal view returns (bool) {
        return _totalAssets(MathUpgradeable.Rounding.Down) < totalSupply();
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

    /// @dev Validates exchange rate for a deposit operation (assets spent per share received)
    function _validateDepositExchRate(
        int256 minExchRateWad,
        uint256 assetsSpent,
        uint256 subVaultShares
    ) internal pure {
        if (minExchRateWad > 0) {
            revert RebalanceExchRateWrongSign(minExchRateWad);
        }
        // slither-disable-next-line incorrect-equality
        uint256 actualExchRate = subVaultShares == 0
            ? type(uint256).max
            : assetsSpent.mulDiv(1e18, subVaultShares, MathUpgradeable.Rounding.Up);
        if (actualExchRate > uint256(-minExchRateWad)) {
            revert RebalanceExchRateTooLow(minExchRateWad, -int256(assetsSpent), subVaultShares);
        }
    }

    /// @dev Validates exchange rate for a withdraw/redeem operation
    function _validateWithdrawExchRate(
        int256 minExchRateWad,
        uint256 assetsReceived,
        uint256 subVaultShares
    ) internal pure {
        if (minExchRateWad < 0) {
            revert RebalanceExchRateWrongSign(minExchRateWad);
        }
        // we do not need to check for a div by zero because a subvault would never give us assets for zero shares
        uint256 actualExchRate =
            assetsReceived.mulDiv(1e18, subVaultShares, MathUpgradeable.Rounding.Down);
        if (actualExchRate < uint256(minExchRateWad)) {
            revert RebalanceExchRateTooLow(minExchRateWad, int256(assetsReceived), subVaultShares);
        }
    }

    /// @dev Helper to add/remove a subvault from the whitelist
    function _setSubVaultWhitelist(address _subVault, bool _whitelisted) internal {
        // slither-disable-next-line unused-return
        _whitelisted
            ? _whitelistedSubVaults.add(_subVault)
            : _whitelistedSubVaults.remove(_subVault);
        emit SubVaultWhitelistUpdated(_subVault, _whitelisted);
    }
}
