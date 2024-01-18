// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../libraries/Whitelist.sol";
import "./L1CustomGateway.sol";
import "../../libraries/IXERC20Lockbox.sol";
import "../../libraries/IXERC20.sol";

/**
 * @title Layer 1 Gateway contract for bridging custom XERC20s
 * @notice This contract handles token deposits, holds the escrowed tokens on layer 1 lockbox, and (ultimately) finalizes withdrawals.
 */
contract L1XERC20CustomGateway is L1CustomGateway {
    using SafeERC20 for IERC20;

    function initialize(
        address _l2Counterpart,
        address _l1Router,
        address _inbox,
        address _owner
    ) public override {
        super.initialize(_l2Counterpart, _l1Router, _inbox, _owner);
    }

    function outboundEscrowTransfer(
        address _l1XToken,
        address _from,
        uint256 _amount
    ) internal virtual override returns (uint256 amountReceived) {
        // this method is virtual since different subclasses can handle escrow differently
        // user funds are escrowed in the lockbox using this function
        address lockbox = IXERC20(_l1XToken).lockbox();
        IERC20 l1Token = IXERC20Lockbox(lockbox).ERC20();
        uint256 prevBalance = IERC20(_l1XToken).balanceOf(address(this));
        IERC20(l1Token).safeTransferFrom(_from, address(this), _amount);
        IXERC20Lockbox(lockbox).deposit(_amount);
        uint256 postBalance = IERC20(_l1XToken).balanceOf(address(this));
        return postBalance - prevBalance;
    }

    function inboundEscrowTransfer(
        address _l1XToken,
        address _dest,
        uint256 _amount
    ) internal virtual override {
        // this method is virtual since different subclasses can handle escrow differently
        address lockbox = IXERC20(_l1XToken).lockbox();
        IERC20 l1Token = IXERC20Lockbox(lockbox).ERC20();
        uint256 amount = (IXERC20Lockbox(lockbox).exchangeRate() * _amount) / 1e18;
        IXERC20Lockbox(lockbox).withdraw(amount);
        IERC20(l1Token).safeTransfer(_dest, amount);
    }
}
