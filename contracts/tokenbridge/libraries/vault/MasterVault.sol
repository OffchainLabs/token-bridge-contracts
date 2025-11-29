// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {
    ERC4626Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    MathUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MasterVault is
    Initializable,
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    error TooFewSharesReceived();
    error TooManySharesBurned();
    error TooManyAssetsDeposited();
    error TooFewAssetsReceived();
    error InvalidAsset();
    error InvalidOwner();
    error ZeroAddress();
    error PerformanceFeeDisabled();
    error BeneficiaryNotSet();

    event PerformanceFeeToggled(bool enabled);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event PerformanceFeesWithdrawn(address indexed beneficiary, uint256 amount);

    // note: the performance fee can be avoided if the underlying strategy can be sandwiched (eg ETH to wstETH dex swap)
    // maybe a simpler and more robust implementation would be for the owner to adjust the subVaultExchRateWad directly
    // this would also avoid the need for totalPrincipal tracking
    // however, this would require more trust in the owner
    bool public enablePerformanceFee;
    address public beneficiary;
    uint256 public totalPrincipal; // total assets deposited, used to calculate profit

    function initialize(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _owner
    ) external initializer {
        if (address(_asset) == address(0)) revert InvalidAsset();
        if (_owner == address(0)) revert InvalidOwner();

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20Upgradeable(address(_asset)));
        __AccessControl_init();
        __Pausable_init();

        _setRoleAdmin(VAULT_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(FEE_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(VAULT_MANAGER_ROLE, _owner);
        _grantRole(FEE_MANAGER_ROLE, _owner); // todo: consider permissionless by default
        _grantRole(PAUSER_ROLE, _owner);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// fee-related methods ///

    /// @notice Toggle performance fee collection on/off
    /// @param enabled True to enable performance fees, false to disable
    function setPerformanceFee(bool enabled) external onlyRole(VAULT_MANAGER_ROLE) {
        enablePerformanceFee = enabled;
        emit PerformanceFeeToggled(enabled);
    }

    /// @notice Set the beneficiary address for performance fees
    /// @param newBeneficiary Address to receive performance fees
    function setBeneficiary(address newBeneficiary) external onlyRole(FEE_MANAGER_ROLE) {
        if (newBeneficiary == address(0)) revert ZeroAddress();
        address oldBeneficiary = beneficiary;
        beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(oldBeneficiary, newBeneficiary);
    }

    /// @notice calculating total profit
    function totalProfit() public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        return _totalAssets > totalPrincipal ? _totalAssets - totalPrincipal : 0;
    }

    /// @notice Withdraw all accumulated performance fees to beneficiary
    /// @dev Only callable by fee manager when performance fees are enabled
    function withdrawPerformanceFees() external onlyRole(FEE_MANAGER_ROLE) {
        if (!enablePerformanceFee) revert PerformanceFeeDisabled();
        if (beneficiary == address(0)) revert BeneficiaryNotSet();

        uint256 totalProfits = totalProfit();
        if (totalProfits > 0) {
            SafeERC20.safeTransfer(IERC20(asset()), beneficiary, totalProfits);
            emit PerformanceFeesWithdrawn(beneficiary, totalProfits);
        }
    }

    /// @notice return share price by asset in 18 decimals
    /// @dev max value is 1e18 if performance fee is enabled
    /// @dev examples:
    /// example 1. sharePrice = 1e18 means we need to pay 1  asset to get 1 share regardless of the decimals
    /// example 2. sharePrice = 10 * 1e18 means we need to pay 10  asset to get 1 share regardless of the decimals
    /// example 3. sharePrice = 0.1 * 1e18 means we need to pay 0.1  asset to get 1 share regardless of the decimals
    /// example 4. vault holds 99 USDC and 100 shares => sharePrice = 99 * 1e18 / 100
    function sharePrice() public view returns (uint256) {
        uint256 multiplier = 1e18;
        uint256 _totalAssets = totalAssets();
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            return 1 * multiplier;
        }

        uint256 _sharePrice = MathUpgradeable.mulDiv(_totalAssets, multiplier, _totalSupply);

        if (enablePerformanceFee) {
            _sharePrice = MathUpgradeable.min(_sharePrice, 1e18);
        }

        return _sharePrice;
    }

    /// ERC4626 internal methods ///

    /// @dev Override internal deposit to track total principal
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override whenNotPaused {
        super._deposit(caller, receiver, assets, shares);
        totalPrincipal += assets;
    }

    /// @dev Override internal withdraw to track total principal
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override whenNotPaused {
        super._withdraw(caller, receiver, owner, assets, shares);
        totalPrincipal -= assets;
    }
}
