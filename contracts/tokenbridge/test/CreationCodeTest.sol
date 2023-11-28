// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {CreationCodeHelper} from "../libraries/CreationCodeHelper.sol";

contract CreationCodeTest {
    /**
     * @dev This function needs to match `_creationCodeFor()` in L1AtomicTokenBridgeCreator and L2AtomicTokenBridgefactory.
     *      The only difference is that is made external instead of internal to make testing easier.
     */
    function creationCodeFor(bytes memory code) external pure returns (bytes memory) {
        return CreationCodeHelper.getCreationCodeFor(code);
    }
}
