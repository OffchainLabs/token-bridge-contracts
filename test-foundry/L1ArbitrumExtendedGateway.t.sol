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

    function test_transferExitAndCall_EmptyData(
        uint256 exitNum,
        address initialDestination,
        address newDestination
    ) public {
        bytes memory newData;
        bytes memory data;

        // check event
        vm.expectEmit(true, true, true, true);
        emit WithdrawRedirected(initialDestination, newDestination, exitNum, newData, data, false);

        // do it
        vm.prank(initialDestination);
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            exitNum,
            initialDestination,
            newDestination,
            newData,
            data
        );

        // check exit data is properly updated
        bytes32 exitId = keccak256(abi.encode(exitNum, initialDestination));
        (bool isExit, address exitTo, bytes memory exitData) = L1ArbitrumExtendedGateway(
            address(l1Gateway)
        ).redirectedExits(exitId);
        assertEq(isExit, true, "Invalid isExit");
        assertEq(exitTo, newDestination, "Invalid exitTo");
        assertEq(exitData.length, 0, "Invalid exitData");
    }

    function test_transferExitAndCall_revert_NotExpectedSender() public {
        address nonSender = address(800);
        vm.expectRevert("NOT_EXPECTED_SENDER");
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            4,
            nonSender,
            address(2),
            "",
            ""
        );
    }

    function test_transferExitAndCall_revert_NoDataAllowed() public {
        bytes memory nonEmptyData = bytes("abc");
        vm.prank(address(1));
        vm.expectRevert("NO_DATA_ALLOWED");
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            4,
            address(1),
            address(2),
            nonEmptyData,
            ""
        );
    }

    function test_transferExitAndCall_revert_ToNotContract(address initialDestination) public {
        bytes memory data = abi.encode("execute()");
        address nonContractNewDestination = address(15);

        vm.prank(initialDestination);
        vm.expectRevert("TO_NOT_CONTRACT");
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            4,
            initialDestination,
            nonContractNewDestination,
            "",
            data
        );
    }

    /////
    /// Event declarations
    /////
    event WithdrawRedirected(
        address indexed from,
        address indexed to,
        uint256 indexed exitNum,
        bytes newData,
        bytes data,
        bool madeExternalCall
    );
}
