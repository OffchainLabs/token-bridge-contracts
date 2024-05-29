// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {L2GatewayToken} from "../libraries/L2GatewayToken.sol";

/**
 * @title A custom token contract that can be used as bridged USDC
 * @dev   At some point later bridged USDC can be upgraded to native USDC
 */
contract BridgedUsdcCustomToken is L2GatewayToken {
    /**
     * @notice initialize the token
     * @param name_ ERC20 token name
     * @param l2Gateway_ L2 gateway this token communicates with
     * @param l1Counterpart_ L1 address of ERC20
     */
    function initialize(string memory name_, address l2Gateway_, address l1Counterpart_) public {
        L2GatewayToken._initialize({
            name_: name_,
            symbol_: "USDC.e",
            decimals_: uint8(6),
            l2Gateway_: l2Gateway_,
            l1Counterpart_: l1Counterpart_
        });
    }
}
