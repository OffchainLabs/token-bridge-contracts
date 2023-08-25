// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { L1OrbitCustomGateway } from "./L1OrbitCustomGateway.sol";
import { IArbToken } from "../../arbitrum/IArbToken.sol";

/**
 * @title   L1 Gateway for reverse "custom" bridging functionality in an ERC20-based rollup.
 * @notice  Handles some (but not all!) reverse custom Gateway needs.
 *          Use the reverse custom gateway instead of the normal custom
 *          gateway if you want total supply to be tracked on the L2
 *          rather than the L1.
 * @dev     The reverse custom gateway burns on the l2 and escrows on the l1
 *          which is the opposite of the way the normal custom gateway works
 *          This means that the total supply L2 isn't affected by bridging, which
 *          is helpful for observers calculating the total supply especially if
 *          if minting is also occuring on L2
 */
contract L1OrbitReverseCustomGateway is L1OrbitCustomGateway {
    function inboundEscrowTransfer(
        address _l1Address,
        address _dest,
        uint256 _amount
    ) internal virtual override {
        IArbToken(_l1Address).bridgeMint(_dest, _amount);
    }

    function outboundEscrowTransfer(
        address _l1Token,
        address _from,
        uint256 _amount
    ) internal override returns (uint256) {
        IArbToken(_l1Token).bridgeBurn(_from, _amount);
        // by default we assume that the amount we send to bridgeBurn is the amount burnt
        // this might not be the case for every token
        return _amount;
    }
}
