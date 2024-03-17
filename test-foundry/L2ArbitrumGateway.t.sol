// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {L2ArbitrumGateway} from "contracts/tokenbridge/arbitrum/gateway/L2ArbitrumGateway.sol";
import {ArbSysMock} from "contracts/tokenbridge/test/ArbSysMock.sol";
import {ITokenGateway} from "contracts/tokenbridge/libraries/gateway/ITokenGateway.sol";

abstract contract L2ArbitrumGatewayTest is Test {
    L2ArbitrumGateway public l2Gateway;
    ArbSysMock public arbSysMock = new ArbSysMock();

    address public router = makeAddr("router");
    address public l1Counterpart = makeAddr("l1Counterpart");

    // token transfer params
    address public receiver = makeAddr("to");
    address public sender = makeAddr("from");
    uint256 public amount = 2400;

    /* solhint-disable func-name-mixedcase */
    function test_getOutboundCalldata() public {
        address token = makeAddr("token");
        bytes memory data = new bytes(340);

        bytes memory expected = abi.encodeWithSelector(
            ITokenGateway.finalizeInboundTransfer.selector,
            token,
            sender,
            receiver,
            amount,
            abi.encode(0, data)
        );
        bytes memory actual = l2Gateway.getOutboundCalldata(token, sender, receiver, amount, data);

        assertEq(actual, expected, "Invalid outbound calldata");
    }

    function test_finalizeInboundTransfer() public virtual;
    function test_finalizeInboundTransfer_WithCallHook() public virtual;

    function test_outboundTransfer() public virtual;

    function test_outboundTransfer_4Args() public virtual;

    function test_outboundTransfer_revert_ExtraDataDisabled() public {
        vm.expectRevert("EXTRA_DATA_DISABLED");
        bytes memory extraData = new bytes(0x1234);
        l2Gateway.outboundTransfer(address(100), address(101), 200, 0, 0, extraData);
    }

    function test_outboundTransfer_revert_NoValue() public {
        vm.expectRevert("NO_VALUE");
        l2Gateway.outboundTransfer{value: 1 ether}(
            address(100), address(101), 200, 0, 0, new bytes(0)
        );
    }

    function test_outboundTransfer_revert_NotExpectedL1Token() public virtual;

    function test_outboundTransfer_revert_TokenNotDeployed() public {
        address token = makeAddr("someToken");
        vm.expectRevert("TOKEN_NOT_DEPLOYED");
        l2Gateway.outboundTransfer(token, address(101), 200, 0, 0, new bytes(0));
    }

    ////
    // Event declarations
    ////
    event DepositFinalized(
        address indexed l1Token, address indexed _from, address indexed _receiver, uint256 _amount
    );

    event WithdrawalInitiated(
        address l1Token,
        address indexed _from,
        address indexed _receiver,
        uint256 indexed _l2ToL1Id,
        uint256 _exitNum,
        uint256 _amount
    );

    event TxToL1(
        address indexed _from, address indexed _receiver, uint256 indexed _id, bytes _data
    );
}
