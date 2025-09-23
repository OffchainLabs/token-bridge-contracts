// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC4626 } from "lib/forge-std/src/interfaces/IERC4626.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

// todo: make this more like a 4626 vault, erc20 shares + deposit + withdraw
// todo: consider beacon proxy
// todo: should we add role based access control?
contract MasterVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    error CallerIsNotGateway();
    error ZeroAddress();
    error SubVaultIsNotSet();
    error InsufficientAssets();
    error InsufficientShares();
    error InsufficientYield();

    address public immutable underlyingAsset;
    address public subVault;
    uint256 public netDeposits;

    event SubVaultSet(address subVault);
    event YieldWithdrawn(address indexed owner, uint256 amount);

    constructor(
        address _underlyingAsset,
        address _subVault
    ) ERC20(
        string(abi.encodePacked("Wrapped ", IERC20Metadata(_underlyingAsset).name())),
        string(abi.encodePacked("mst", IERC20Metadata(_underlyingAsset).symbol()))
    ) ERC4626(IERC20(_underlyingAsset)) Ownable() {
        if (_underlyingAsset == address(0)) {
            revert ZeroAddress();
        }
        if (_subVault == address(0)) {
            revert ZeroAddress();
        }
        underlyingAsset = _underlyingAsset;
        _setSubVault(_subVault);
    }

    function _setSubVault(address _subVault) internal {
        subVault = _subVault;
        emit SubVaultSet(_subVault);
    }

    /** @dev See {IERC4626-deposit}. */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        if (subVault == address(0)) {
            revert SubVaultIsNotSet();
        }

        IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), assets);
        IERC20(underlyingAsset).safeIncreaseAllowance(subVault, assets);
        IERC4626(subVault).deposit(assets, address(this));
        shares = convertToShares(assets);
        netDeposits += assets;
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /** @dev See {IERC4626-mint}. */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        assets = convertToAssets(shares);
        deposit(assets, receiver);
    }

    /** @dev See {IERC4626-withdraw}. */
    function withdraw(uint256 assets, address receiver, address owner) public virtual override returns (uint256 shares) {
        if (subVault == address(0)) {
            revert SubVaultIsNotSet();
        }

        shares = convertToShares(assets);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        uint256 subVaultAssets = _calculateSubVaultWithdrawal(assets);
        IERC4626(subVault).withdraw(subVaultAssets, address(this), address(this));
        _burn(owner, shares);
        netDeposits -= assets;
        IERC20(underlyingAsset).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256 assets) {
        assets = convertToAssets(shares);
        withdraw(assets, receiver, owner);
    }

    /// @notice Returns the address of the sub-vault that holds the underlying assets
    /// @return The address of the ERC4626 sub-vault
    function getSubVault() external view returns (address) {
        return subVault;
    }

    /// @notice Sets a new sub-vault address (only owner)
    /// @param _subVault The new ERC4626 sub-vault address
    function setSubVault(address _subVault) external onlyOwner {
        _setSubVault(_subVault);
    }

    /// @notice Returns the net amount of underlying assets deposited by users
    /// @return The total deposits minus withdrawals
    function getNetDeposits() external view returns (uint256) {
        return netDeposits;
    }
    
    function _calculateSubVaultWithdrawal(uint256 assets) internal view returns (uint256) {
        return assets;
    }

    /** @dev See {IERC4626-convertToShares}. */
    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        return assets;
    }

    /** @dev See {IERC4626-convertToAssets}. */
    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        return shares;
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        if (subVault == address(0)) {
            return 0;
        }
        return IERC4626(subVault).totalAssets();
    }

    /// @notice Calculates the current yield (profit) available for withdrawal by owner
    /// @return yield The amount of yield (totalAssets - netDeposits)
    function getYield() public view returns (uint256 yield) {
        uint256 total = totalAssets();
        yield = total > netDeposits ? total - netDeposits : 0;
    }

    /// @notice Withdraws available yield to the owner
    /// @dev Only callable by owner, handles liquidity constraints automatically
    function withdrawYield() external onlyOwner {
        if (subVault == address(0)) {
            revert SubVaultIsNotSet();
        }

        uint256 yield = getYield();
        if (yield == 0) {
            revert InsufficientYield();
        }

        uint256 maxWithdrawable = IERC4626(subVault).maxWithdraw(address(this));
        if (yield > maxWithdrawable) {
            yield = maxWithdrawable;
        }

        IERC4626(subVault).withdraw(yield, address(this), address(this));
        IERC20(underlyingAsset).safeTransfer(msg.sender, yield);
        emit YieldWithdrawn(msg.sender, yield);
    }
}
