// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../libraries/Whitelist.sol";
import "../../arbitrum/gateway/L2CustomGateway.sol";
import "../../libraries/IXERC20Lockbox.sol";
import "../../libraries/IXERC20.sol";

/**
 * @title Layer 1 Gateway contract for bridging custom XERC20s
 * @notice This contract handles token deposits, holds the escrowed tokens on layer 1 lockbox, and (ultimately) finalizes withdrawals.
 */
contract L2XERC20CustomGateway is L2CustomGateway {
    using SafeERC20 for IERC20;

    function initialize(address _l1Counterpart, address _router) public virtual override {
        super.initialize(_l1Counterpart, _router);
    }

    function outboundEscrowTransfer(
        address _l2Token,
        address _from,
        uint256 _amount
    ) internal virtual override returns (uint256 amountBurnt) {
        // this method is virtual since different subclasses can handle escrow differently
        // user funds are escrowed on the gateway using this function
        // burns L2 tokens in order to release escrowed L1 tokens
        IXERC20(_l2Token).burn(_from, _amount);
        // by default we assume that the amount we send to bridgeBurn is the amount burnt
        // this might not be the case for every token
        return _amount;
    }

    function inboundEscrowTransfer(
        address _l2Address,
        address _dest,
        uint256 _amount
    ) internal virtual override {
        // this method is virtual since different subclasses can handle escrow differently
        IXERC20(_l2Address).mint(_dest, _amount);
    }
}
