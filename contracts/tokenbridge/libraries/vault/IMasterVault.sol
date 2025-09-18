// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface IMasterVault {
    // todo: add bytes param for slippage etc
    function deposit(uint256 amount) external returns (uint256);

    function withdraw(uint256 amount, address recipient) external;

    function getSubVault() external view returns (address);

    function setSubVault(address subVault) external;
}
