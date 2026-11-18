// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IMasterVault {
    function setSubVault(IERC4626 subVault) external;
    function deposit(uint256 assets) external returns (uint256 shares);
    function redeem(uint256 shares, uint256 minAssets) external returns (uint256 assets);
}
