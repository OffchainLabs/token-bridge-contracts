// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./IMasterVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "lib/forge-std/src/interfaces/IERC4626.sol";

contract MasterVault is IMasterVault {
    using SafeERC20 for IERC20;

    error CallerIsNotGateway();
    error ZeroAddress();

    address public immutable token;
    address public immutable gateway;
    address public immutable subVault;

    event Deposited(uint256 amount, address from);
    event Withdrawn(uint256 amount, address recipient);

    modifier onlyGateway() {
        if (msg.sender != gateway) {
            revert CallerIsNotGateway();
        }
        _;
    }

    constructor(address _token, address _gateway, address _subVault) {
        if (_token == address(0) || _gateway == address(0) || _subVault == address(0)) {
            revert ZeroAddress();
        }
        token = _token;
        gateway = _gateway;
        subVault = _subVault;
    }

    function deposit(
        uint256 amount
    ) external override onlyGateway returns (uint256 amountDeposited) {
        amountDeposited = IERC4626(subVault).deposit(amount, gateway);
        emit Deposited(amount);
    }

    function withdraw(uint256 amount, address recipient) external override onlyGateway {
        IERC4626(subVault).withdraw(amount, recipient, gateway);
        emit Withdrawn(amount, recipient);
    }

    function getSubVault() external view returns (address) {
        return subVault;
    }
}
