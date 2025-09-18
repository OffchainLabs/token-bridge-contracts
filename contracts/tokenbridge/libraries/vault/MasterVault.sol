// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./IMasterVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "lib/forge-std/src/interfaces/IERC4626.sol";

contract MasterVault is IMasterVault, Ownable {
    using SafeERC20 for IERC20;

    error CallerIsNotGateway();
    error ZeroAddress();
    error SubVaultIsNotSet();

    address public immutable token;
    address public immutable gateway;
    address public subVault;

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount, address recipient, uint256 shares);
    event SubVaultSet(address subVault);

    modifier onlyGateway() {
        if (msg.sender != gateway) {
            revert CallerIsNotGateway();
        }
        _;
    }

    constructor(address _token, address _gateway, address _owner) Ownable() {
        if (_token == address(0) || _gateway == address(0) || _owner == address(0)) {
            revert ZeroAddress();
        }
        token = _token;
        gateway = _gateway;
        transferOwnership(_owner);
    }

    function deposit(
        uint256 amount
    ) external override onlyGateway returns (uint256 amountDeposited) {
        if (subVault == address(0)) {
            revert SubVaultIsNotSet();
        }
        amountDeposited = IERC4626(subVault).deposit(amount, gateway);
        emit Deposited(amount);
    }

    function withdraw(uint256 amount, address recipient) external override onlyGateway {
        if (subVault == address(0)) {
            revert SubVaultIsNotSet();
        }
        uint256 shares = IERC4626(subVault).withdraw(amount, recipient, gateway);
        emit Withdrawn(amount, recipient, shares);
    }

    function getSubVault() external view returns (address) {
        return subVault;
    }

    function setSubVault(address _subVault) external override onlyOwner {
        // todo: need to make sure we transfer funds here
        subVault = _subVault;
        emit SubVaultSet(_subVault);
    }
}
