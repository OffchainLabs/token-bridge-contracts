// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {CreationCodeHelper} from "../libraries/CreationCodeHelper.sol";

contract CreationCodeTest {
    /**
     * @dev Wrapper function around CreationCodeHelper.getCreationCodeFor used for testing convenience.
     */
    function creationCodeFor(bytes memory code) external pure returns (bytes memory) {
        return CreationCodeHelper.getCreationCodeFor(code);
    }
}
