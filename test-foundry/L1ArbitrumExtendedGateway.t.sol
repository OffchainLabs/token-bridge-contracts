// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import "contracts/tokenbridge/ethereum/gateway/L1ArbitrumExtendedGateway.sol";

abstract contract L1ArbitrumExtendedGatewayTest is Test {
    IL1ArbitrumGateway public l1Gateway;

    function test_encodeWithdrawal(uint256 exitNum, address dest) public {
        bytes32 encodedWithdrawal = L1ArbitrumExtendedGateway(address(l1Gateway)).encodeWithdrawal(
            exitNum,
            dest
        );
        bytes32 expectedEncoding = keccak256(abi.encode(exitNum, dest));

        assertEq(encodedWithdrawal, expectedEncoding, "Invalid encodeWithdrawal");
    }

    function test_getExternalCall(uint256 exitNum, address dest, bytes memory data) public {
        (address target, bytes memory extData) = L1ArbitrumExtendedGateway(address(l1Gateway))
            .getExternalCall(exitNum, dest, data);

        assertEq(target, dest, "Invalid dest");
        assertEq(extData, data, "Invalid data");

        bytes32 exitId = keccak256(abi.encode(exitNum, dest));
        (bool isExit, address newTo, bytes memory newData) = L1ArbitrumExtendedGateway(
            address(l1Gateway)
        ).redirectedExits(exitId);
        assertEq(isExit, false, "Invalid isExit");
        assertEq(newTo, address(0), "Invalid _newTo");
        assertEq(newData.length, 0, "Invalid _newData");
    }
}
