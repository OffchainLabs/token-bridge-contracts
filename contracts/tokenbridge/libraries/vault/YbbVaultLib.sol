// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IMasterVault} from "./IMasterVault.sol";
import {IMasterVaultFactory} from "./IMasterVaultFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library YbbVaultLib {
    using SafeERC20 for IERC20;

    // slither-disable-next-line arbitrary-send-erc20
    function depositToVault(address masterVaultFactory, address token, address from, uint256 amount)
        internal
        returns (uint256 shares)
    {
        uint256 prevBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(from, address(this), amount);
        uint256 postBalance = IERC20(token).balanceOf(address(this));
        uint256 amountReceived = postBalance - prevBalance;

        address masterVault = IMasterVaultFactory(masterVaultFactory).getVault(token);
        IERC20(token).safeIncreaseAllowance(masterVault, amountReceived);
        shares = IMasterVault(masterVault).deposit(amountReceived);
        require(shares > 0, "ZERO_SHARES");
    }

    function withdrawFromVault(
        address masterVaultFactory,
        address token,
        address dest,
        uint256 amount
    ) internal {
        address masterVault = IMasterVaultFactory(masterVaultFactory).getVault(token);
        IERC20(masterVault).safeTransfer(dest, amount);
    }
}
