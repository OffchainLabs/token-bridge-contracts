// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "contracts/tokenbridge/ethereum/gateway/L1ArbitrumExtendedGateway.sol";
import { TestERC20 } from "contracts/tokenbridge/test/TestERC20.sol";
import { InboxMock } from "contracts/tokenbridge/test/InboxMock.sol";

abstract contract L1ArbitrumExtendedGatewayTest is Test {
    IL1ArbitrumGateway public l1Gateway;
    IERC20 public token;

    address public l2Gateway = makeAddr("l2Gateway");
    address public router = makeAddr("router");
    address public inbox;
    address public user = makeAddr("user");

    // retryable params
    uint256 public maxSubmissionCost;
    uint256 public maxGas = 1000000000;
    uint256 public gasPriceBid = 3;
    uint256 public retryableCost;
    address public creditBackAddress = makeAddr("creditBackAddress");

    // fuzzer behaves weirdly when it picks up this address which is used internally for issuing cheatcodes
    address internal constant FOUNDRY_CHEATCODE_ADDRESS =
        0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    /* solhint-disable func-name-mixedcase */
    function test_encodeWithdrawal(uint256 exitNum, address dest) public {
        bytes32 encodedWithdrawal = L1ArbitrumExtendedGateway(address(l1Gateway)).encodeWithdrawal(
            exitNum,
            dest
        );
        bytes32 expectedEncoding = keccak256(abi.encode(exitNum, dest));

        assertEq(encodedWithdrawal, expectedEncoding, "Invalid encodeWithdrawal");
    }

    function test_finalizeInboundTransfer() public virtual {
        // fund gateway with tokens being withdrawn
        vm.prank(address(l1Gateway));
        TestERC20(address(token)).mint();

        // snapshot state before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 l1GatewayBalanceBefore = token.balanceOf(address(l1Gateway));

        // withdrawal params
        address from = address(3000);
        uint256 withdrawalAmount = 25;
        uint256 exitNum = 7;
        bytes memory callHookData = "";
        bytes memory data = abi.encode(exitNum, callHookData);

        InboxMock(address(inbox)).setL2ToL1Sender(l2Gateway);

        // trigger withdrawal
        vm.prank(address(IInbox(l1Gateway.inbox()).bridge()));
        l1Gateway.finalizeInboundTransfer(address(token), from, user, withdrawalAmount, data);

        // check tokens are properly released
        uint256 userBalanceAfter = token.balanceOf(user);
        assertEq(userBalanceAfter - userBalanceBefore, withdrawalAmount, "Wrong user balance");

        uint256 l1GatewayBalanceAfter = token.balanceOf(address(l1Gateway));
        assertEq(
            l1GatewayBalanceBefore - l1GatewayBalanceAfter,
            withdrawalAmount,
            "Wrong l1 gateway balance"
        );
    }

    function test_finalizeInboundTransfer_revert_NotFromBridge() public {
        address notBridge = address(300);
        vm.prank(notBridge);
        vm.expectRevert("NOT_FROM_BRIDGE");
        l1Gateway.finalizeInboundTransfer(address(token), user, user, 100, "");
    }

    function test_finalizeInboundTransfer_revert_OnlyCounterpartGateway() public {
        address notCounterPartGateway = address(400);
        InboxMock(address(inbox)).setL2ToL1Sender(notCounterPartGateway);

        // trigger withdrawal
        vm.prank(address(IInbox(l1Gateway.inbox()).bridge()));
        vm.expectRevert("ONLY_COUNTERPART_GATEWAY");
        l1Gateway.finalizeInboundTransfer(address(token), user, user, 100, "");
    }

    function test_getExternalCall(
        uint256 exitNum,
        address dest,
        bytes memory data
    ) public {
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

    function test_getExternalCall_Redirected(
        uint256 exitNum,
        address initialDest,
        address newDest
    ) public {
        // redirect
        vm.prank(initialDest);
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            exitNum,
            initialDest,
            newDest,
            "",
            ""
        );

        // check getExternalCall returns new destination
        (address target, bytes memory extData) = L1ArbitrumExtendedGateway(address(l1Gateway))
            .getExternalCall(exitNum, initialDest, "");
        assertEq(target, newDest, "Invalid dest");
        assertEq(extData.length, 0, "Invalid data");

        // check exit redirection is properly stored
        bytes32 exitId = keccak256(abi.encode(exitNum, initialDest));
        (bool isExit, address newTo, bytes memory newData) = L1ArbitrumExtendedGateway(
            address(l1Gateway)
        ).redirectedExits(exitId);
        assertEq(isExit, true, "Invalid isExit");
        assertEq(newTo, newDest, "Invalid _newTo");
        assertEq(newData.length, 0, "Invalid _newData");
    }

    function test_outboundTransferCustomRefund_revert_ExtraDataDisabled() public {
        bytes memory callHookData = abi.encodeWithSignature("doSomething()");
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        vm.prank(router);
        vm.expectRevert("EXTRA_DATA_DISABLED");
        l1Gateway.outboundTransferCustomRefund(
            address(token),
            user,
            user,
            400,
            0.1 ether,
            0.01 ether,
            routerEncodedData
        );
    }

    function test_outboundTransferCustomRefund_revert_L1NotContract() public {
        address invalidTokenAddress = address(70);

        vm.prank(router);
        vm.expectRevert("L1_NOT_CONTRACT");
        l1Gateway.outboundTransferCustomRefund(
            address(invalidTokenAddress),
            user,
            user,
            400,
            0.1 ether,
            0.01 ether,
            buildRouterEncodedData("")
        );
    }

    function test_outboundTransferCustomRefund_revert_NotFromRouter() public {
        vm.expectRevert("NOT_FROM_ROUTER");
        l1Gateway.outboundTransferCustomRefund(
            address(token),
            user,
            user,
            400,
            0.1 ether,
            0.01 ether,
            ""
        );
    }

    function test_supportsInterface(bytes4 iface) public {
        bool expected = false;
        if (
            iface == type(IERC165).interfaceId ||
            iface == IL1ArbitrumGateway.outboundTransferCustomRefund.selector
        ) {
            expected = true;
        }

        assertEq(l1Gateway.supportsInterface(iface), expected, "Interface shouldn't be supported");
    }

    function test_transferExitAndCall_EmptyData_NotRedirected(
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

    function test_transferExitAndCall_EmptyData_Redirected(
        uint256 exitNum,
        address initialDestination
    ) public {
        bytes memory data;
        address intermediateDestination = address(new TestExitReceiver());

        // transfer exit
        vm.prank(initialDestination);
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            exitNum,
            initialDestination,
            intermediateDestination,
            "",
            data
        );

        address finalDestination = address(new TestExitReceiver());
        vm.prank(intermediateDestination);
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            exitNum,
            initialDestination,
            finalDestination,
            "",
            data
        );

        // check exit data is properly updated
        bytes32 exitId = keccak256(abi.encode(exitNum, initialDestination));
        (bool isExit, address exitTo, bytes memory exitData) = L1ArbitrumExtendedGateway(
            address(l1Gateway)
        ).redirectedExits(exitId);
        assertEq(isExit, true, "Invalid isExit");
        assertEq(exitTo, finalDestination, "Invalid exitTo");
        assertEq(exitData.length, 0, "Invalid exitData");
    }

    function test_transferExitAndCall_NonEmptyData(uint256 exitNum, address initialDestination)
        public
    {
        bytes memory newData;
        bytes memory data = abi.encode("fun()");
        address newDestination = address(new TestExitReceiver());

        // check events
        vm.expectEmit(true, true, true, true);
        emit ExitHookTriggered(initialDestination, exitNum, data);

        vm.expectEmit(true, true, true, true);
        emit WithdrawRedirected(initialDestination, newDestination, exitNum, newData, data, true);

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

    function test_transferExitAndCall_NonEmptyData_Redirected(
        uint256 exitNum,
        address initialDestination
    ) public {
        bytes memory data = abi.encode("run()");
        address intermediateDestination = address(new TestExitReceiver());

        // transfer exit
        vm.prank(initialDestination);
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            exitNum,
            initialDestination,
            intermediateDestination,
            "",
            data
        );

        address finalDestination = address(new TestExitReceiver());
        vm.prank(intermediateDestination);
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            exitNum,
            initialDestination,
            finalDestination,
            "",
            data
        );

        // check exit data is properly updated
        bytes32 exitId = keccak256(abi.encode(exitNum, initialDestination));
        (bool isExit, address exitTo, bytes memory exitData) = L1ArbitrumExtendedGateway(
            address(l1Gateway)
        ).redirectedExits(exitId);
        assertEq(isExit, true, "Invalid isExit");
        assertEq(exitTo, finalDestination, "Invalid exitTo");
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

    function test_transferExitAndCall_revert_TransferHookFail(
        uint256 exitNum,
        address initialDestination
    ) public {
        bytes memory data = abi.encode("failIt");
        address newDestination = address(new TestExitReceiver());

        vm.prank(initialDestination);
        vm.expectRevert("TRANSFER_HOOK_FAIL");
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            exitNum,
            initialDestination,
            newDestination,
            "",
            data
        );
    }

    function test_transferExitAndCall_revert_TransferHookFail_Redirected(
        uint256 exitNum,
        address initialDestination
    ) public {
        bytes memory data = abi.encode("abc");
        address intermediateDestination = address(new TestExitReceiver());

        vm.prank(initialDestination);
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            exitNum,
            initialDestination,
            intermediateDestination,
            "",
            data
        );

        bytes memory failData = abi.encode("failIt");
        address finalDestination = address(new TestExitReceiver());

        vm.prank(intermediateDestination);
        vm.expectRevert("TRANSFER_HOOK_FAIL");
        L1ArbitrumExtendedGateway(address(l1Gateway)).transferExitAndCall(
            exitNum,
            initialDestination,
            finalDestination,
            "",
            failData
        );
    }

    ////
    // Helper functions
    ////
    function buildRouterEncodedData(bytes memory callHookData)
        internal
        view
        virtual
        returns (bytes memory)
    {
        bytes memory userEncodedData = abi.encode(maxSubmissionCost, callHookData);
        bytes memory routerEncodedData = abi.encode(user, userEncodedData);

        return routerEncodedData;
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
    event ExitHookTriggered(address sender, uint256 exitNum, bytes data);
}

contract TestExitReceiver is ITradeableExitReceiver {
    event ExitHookTriggered(address sender, uint256 exitNum, bytes data);

    function onExitTransfer(
        address sender,
        uint256 exitNum,
        bytes calldata data
    ) external override returns (bool) {
        emit ExitHookTriggered(sender, exitNum, data);
        return keccak256(data) != keccak256(abi.encode("failIt"));
    }
}
