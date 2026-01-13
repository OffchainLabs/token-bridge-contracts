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
    AccessControlUpgradeable
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

// todo: should we have an arbitrary call function for the vault manager to do stuff with the subvault? like queue withdrawals etc

/// @notice MasterVault is a metavault that deposits assets to an admin defined ERC4626 compliant subVault.
/// @dev    The MasterVault keeps some fraction of assets idle and deposits the rest into the subVault to earn yield.
///         A 100% performance fee can be enabled/disabled by the vault manager, and are collected on demand.
///         The MasterVault mitigates the "first depositor" problem by adding 18 decimals to the underlying asset.
///         i.e. if the underlying asset has 6 decimals, the MasterVault will have 24 decimals.
///
///         For a subVault to be compatible with the MasterVault, it must adhere to the following:
///         - convertToAssets and convertToShares must not be manipulable
///         - must not have deposit / withdrawal fees (todo: verify this requirement is necessary)
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
    uint8 public constant EXTRA_DECIMALS = 18;

    error SubVaultAssetMismatch();
    error PerformanceFeeDisabled();
    error BeneficiaryNotSet();
    error InvalidAsset();
    error InvalidOwner();
    error NonZeroTargetAllocation(uint256 targetAllocationWad);
    error NonZeroSubVaultShares(uint256 subVaultShares);
    error NotGateway(address caller);
    error SubVaultNotWhitelisted(address subVault);

    IERC20 public asset;

    /// @notice Gateway router used to verify deposit calls
    IGatewayRouter public gatewayRouter;

    /// @notice Set of whitelisted subvaults
    EnumerableSet.AddressSet private _whitelistedSubVaults;

    // todo: avoid inflation, rounding, other common 4626 vulns
    // we may need a minimum asset or master share amount when setting subvaults (bc of exchange rate calc)
    IERC4626 public subVault;

    uint256 public targetAllocationWad;

    /// @notice The minimum amount of assets that must be deposited/withdrawn when rebalancing.
    ///         If the amount to deposit or withdraw is less than this amount, no action is taken.
    ///         This prevents dust rebalances.
    /// @dev    Defaults to 1e6, but can be set by the vault manager to any value.
    uint256 public minimumRebalanceAmount;

    /// @notice Flag indicating if performance fee is enabled
    bool public enablePerformanceFee;

    /// @notice Address that receives performance fees
    address public beneficiary;

    /// @notice totalPrincipal tracks the total assets deposited into the vault (minus withdrawals)
    /// @dev    When performance fees are disabled, totalPrincipal is 0
    uint256 public totalPrincipal;

    event SubvaultChanged(address indexed oldSubvault, address indexed newSubvault);
    event PerformanceFeeToggled(bool enabled);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event MinimumRebalanceAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event PerformanceFeesWithdrawn(
        address indexed beneficiary, uint256 amountTransferred, uint256 amountWithdrawn
    );
    event Rebalanced(bool deposited, uint256 desiredAmount, uint256 actualAmount);
    event SubVaultWhitelistUpdated(address indexed subVault, bool whitelisted);

    function initialize(
        IERC4626 _subVault,
        string memory _name,
        string memory _symbol,
        address _owner,
        IGatewayRouter _gatewayRouter
    ) external initializer {
        __ERC20_init(_name, _symbol);

        asset = IERC20(address(_subVault.asset()));

        // call decimals() to ensure underlying has reasonable decimals and we won't have overflow
        decimals();

        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();
        __MasterVaultRoles_init(_owner);

        gatewayRouter = _gatewayRouter;

        // mint some dead shares to avoid first depositor issues
        // for more information on the mitigation:
        // https://web.archive.org/web/20250609034056/https://docs.openzeppelin.com/contracts/4.x/erc4626#fees
        _mint(address(1), 10 ** EXTRA_DECIMALS);

        asset.safeApprove(address(_subVault), type(uint256).max);

        subVault = _subVault;
        _setSubVaultWhitelist(address(_subVault), true);

        minimumRebalanceAmount = 1e6;
    }

    /// @notice Modifier to ensure only the registered gateway can call
    modifier onlyGateway() {
        if (gatewayRouter.getGateway(address(asset)) != msg.sender) {
            revert NotGateway(msg.sender);
        }
        _;
    }

    /// @notice Deposit some underlying assets in exchange for vault shares
    function deposit(uint256 assets)
        external
        whenNotPaused
        nonReentrant
        onlyGateway
        returns (uint256 shares)
    {
        shares = _convertToShares(assets, MathUpgradeable.Rounding.Down);
        if (enablePerformanceFee) totalPrincipal += assets;
        _mint(msg.sender, shares);
        asset.safeTransferFrom(msg.sender, address(this), assets);
    }

    /// @notice Redeem some vault shares in exchange for underlying assets
    function redeem(uint256 shares) internal whenNotPaused nonReentrant returns (uint256 assets) {
        assets = _convertToAssets(shares, MathUpgradeable.Rounding.Down);
        if (enablePerformanceFee) totalPrincipal -= assets;

        uint256 idleAssets = asset.balanceOf(address(this));
        if (idleAssets < assets) {
            uint256 assetsToWithdraw = assets - idleAssets;
            subVault.withdraw(assetsToWithdraw, address(this), address(this));
        }

        _burn(msg.sender, shares);
        asset.safeTransfer(msg.sender, assets);
    }

    function rebalance() external whenNotPaused nonReentrant onlyRole(KEEPER_ROLE) {
        _rebalance();
    }

    function distributePerformanceFee() external whenNotPaused nonReentrant onlyRole(KEEPER_ROLE) {
        _distributePerformanceFee();
    }

    /// @notice Set a new subvault
    /// @param  _subVault The subvault to set. Must be an ERC4626 vault with the same asset as this MasterVault.
    function setSubVault(IERC4626 _subVault) external nonReentrant onlyRole(SUBVAULT_MANAGER_ROLE) {
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

    function setTargetAllocationWad(uint256 _targetAllocationWad)
        external
        nonReentrant
        onlyRole(SUBVAULT_MANAGER_ROLE)
    {
        require(_targetAllocationWad <= 1e18, "Target allocation must be <= 100%");
        require(targetAllocationWad != _targetAllocationWad, "Allocation unchanged");
        targetAllocationWad = _targetAllocationWad;
    }

    function setMinimumRebalanceAmount(uint256 _minimumRebalanceAmount)
        external
        onlyRole(SUBVAULT_MANAGER_ROLE)
    {
        uint256 oldAmount = minimumRebalanceAmount;
        minimumRebalanceAmount = _minimumRebalanceAmount;
        emit MinimumRebalanceAmountUpdated(oldAmount, _minimumRebalanceAmount);
    }

    /// @notice Toggle performance fee collection on/off
    /// @param enabled True to enable performance fees, false to disable
    function setPerformanceFee(bool enabled) external nonReentrant onlyRole(FEE_MANAGER_ROLE) {
        // reset totalPrincipal to current totalAssets when enabling performance fee
        // this prevents a sudden large profit
        if (enabled) {
            totalPrincipal = _totalAssets(MathUpgradeable.Rounding.Up); // todo: confirm rounding direction
        } else {
            _distributePerformanceFee();
            totalPrincipal = 0;
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

    /// @notice Add or remove a subvault from the whitelist
    /// @param _subVault The subvault address to update
    /// @param _whitelisted True to whitelist the subvault, false to remove it
    function setSubVaultWhitelist(address _subVault, bool _whitelisted)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
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

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Overridden to add EXTRA_DECIMALS to the underlying asset decimals
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(address(asset)).decimals() + EXTRA_DECIMALS;
    }

    /**
     * @dev See {IERC4626-totalAssets}.
     */
    function totalAssets() public view returns (uint256) {
        return _totalAssets(MathUpgradeable.Rounding.Down);
    }

    function totalProfit(MathUpgradeable.Rounding rounding) public view returns (uint256) {
        uint256 __totalAssets = _totalAssets(rounding);
        return __totalAssets > totalPrincipal ? __totalAssets - totalPrincipal : 0;
    }

    function _rebalance() internal {
        uint256 totalAssetsUp = _totalAssetsLessProfit(MathUpgradeable.Rounding.Up);
        uint256 totalAssetsDown = _totalAssetsLessProfit(MathUpgradeable.Rounding.Down);
        uint256 idleTargetUp =
            totalAssetsUp.mulDiv(1e18 - targetAllocationWad, 1e18, MathUpgradeable.Rounding.Up);
        uint256 idleTargetDown =
            totalAssetsDown.mulDiv(1e18 - targetAllocationWad, 1e18, MathUpgradeable.Rounding.Down);
        uint256 idleBalance = asset.balanceOf(address(this));

        if (idleTargetDown <= idleBalance && idleBalance <= idleTargetUp) {
            return;
        }

        if (idleBalance < idleTargetDown) {
            // we need to withdraw from subvault
            uint256 desiredWithdraw = idleTargetDown - idleBalance;
            uint256 maxWithdrawable = subVault.maxWithdraw(address(this));
            uint256 withdrawAmount =
                desiredWithdraw < maxWithdrawable ? desiredWithdraw : maxWithdrawable;
            if (withdrawAmount < minimumRebalanceAmount) {
                return;
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
                return;
            }
            subVault.deposit(depositAmount, address(this));
            emit Rebalanced(true, desiredDeposit, depositAmount);
        }
    }

    function _distributePerformanceFee() internal {
        if (!enablePerformanceFee) revert PerformanceFeeDisabled();
        if (beneficiary == address(0)) {
            revert BeneficiaryNotSet();
        }

        uint256 profit = totalProfit(MathUpgradeable.Rounding.Down);
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

    function _totalAssets(MathUpgradeable.Rounding rounding) internal view returns (uint256) {
        return asset.balanceOf(address(this))
            + _subVaultSharesToAssets(subVault.balanceOf(address(this)), rounding);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding)
        internal
        view
        returns (uint256 shares)
    {
        // we add one as part of the first deposit mitigation
        // see for details: https://docs.openzeppelin.com/contracts/5.x/erc4626
        return
            assets.mulDiv(
                totalSupply(), _totalAssetsLessProfit(_flipRounding(rounding)) + 1, rounding
            );
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding)
        internal
        view
        returns (uint256 assets)
    {
        // we add one as part of the first deposit mitigation
        // see for details: https://docs.openzeppelin.com/contracts/5.x/erc4626
        return shares.mulDiv(_totalAssetsLessProfit(rounding) + 1, totalSupply(), rounding);
    }

    function _totalAssetsLessProfit(MathUpgradeable.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        uint256 __totalAssets = _totalAssets(rounding);
        if (enablePerformanceFee && __totalAssets > totalPrincipal) {
            return totalPrincipal;
        }
        return __totalAssets;
    }

    function _subVaultSharesToAssets(uint256 subShares, MathUpgradeable.Rounding rounding)
        internal
        view
        returns (uint256 assets)
    {
        return rounding == MathUpgradeable.Rounding.Up
            ? subVault.previewMint(subShares)
            : subVault.previewRedeem(subShares);
    }

    function _flipRounding(MathUpgradeable.Rounding rounding)
        internal
        pure
        returns (MathUpgradeable.Rounding)
    {
        return rounding == MathUpgradeable.Rounding.Up
            ? MathUpgradeable.Rounding.Down
            : MathUpgradeable.Rounding.Up;
    }

    function _setSubVaultWhitelist(address _subVault, bool _whitelisted) internal {
        _whitelisted
            ? _whitelistedSubVaults.add(_subVault)
            : _whitelistedSubVaults.remove(_subVault);
        emit SubVaultWhitelistUpdated(_subVault, _whitelisted);
    }
}
