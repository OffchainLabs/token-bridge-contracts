// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IMasterVault {
    function setSubVault(IERC4626 subVault) external;
}
