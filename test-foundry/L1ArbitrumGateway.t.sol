// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "contracts/tokenbridge/ethereum/gateway/L1ArbitrumGateway.sol";
import {TestERC20} from "contracts/tokenbridge/test/TestERC20.sol";
import {InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";

abstract contract L1ArbitrumGatewayTest is Test {
    IL1ArbitrumGateway public l1Gateway;
    IERC20 public token;

    address public l2Gateway = makeAddr("l2Gateway");
    address public router = makeAddr("router");
    address public inbox;
    address public user = makeAddr("user");

    // retryable params
    uint256 public maxSubmissionCost;
    uint256 public maxGas = 1_000_000_000;
    uint256 public gasPriceBid = 100_000_000;
    uint256 public retryableCost;
    address public creditBackAddress = makeAddr("creditBackAddress");

    // fuzzer behaves weirdly when it picks up this address which is used internally for issuing cheatcodes
    address internal constant FOUNDRY_CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    /* solhint-disable func-name-mixedcase */

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

    function test_finalizeInboundTransfer_revert_NoSender() public {
        InboxMock(address(inbox)).setL2ToL1Sender(address(0));

        // trigger withdrawal
        vm.prank(address(IInbox(l1Gateway.inbox()).bridge()));
        vm.expectRevert("NO_SENDER");
        l1Gateway.finalizeInboundTransfer(address(token), user, user, 100, "");
    }

    function test_getExternalCall() public {
        L1ArbitrumGatewayMock mockGateway = new L1ArbitrumGatewayMock();

        uint256 exitNum = 7;
        address initialDestination = makeAddr("initialDestination");
        bytes memory initialData = bytes("1234");
        (address target, bytes memory data) =
            mockGateway.getExternalCall(exitNum, initialDestination, initialData);

        assertEq(target, initialDestination, "Wrong target");
        assertEq(data, initialData, "Wrong data");
    }

    function test_getOutboundCalldata() public virtual {
        bytes memory outboundCalldata = l1Gateway.getOutboundCalldata({
            _token: address(token),
            _from: user,
            _to: address(800),
            _amount: 355,
            _data: abi.encode("doStuff()")
        });

        bytes memory expectedCalldata = abi.encodeWithSelector(
            ITokenGateway.finalizeInboundTransfer.selector,
            address(token),
            user,
            address(800),
            355,
            abi.encode("", abi.encode("doStuff()"))
        );

        assertEq(outboundCalldata, expectedCalldata, "Invalid outboundCalldata");
    }

    function test_outboundTransfer() public virtual {}

    function test_outboundTransferCustomRefund_revert_ExtraDataDisabled() public {
        bytes memory callHookData = abi.encodeWithSignature("doSomething()");
        bytes memory routerEncodedData = buildRouterEncodedData(callHookData);

        vm.prank(router);
        vm.expectRevert("EXTRA_DATA_DISABLED");
        l1Gateway.outboundTransferCustomRefund(
            address(token), user, user, 400, 0.1 ether, 0.01 ether, routerEncodedData
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
            address(token), user, user, 400, 0.1 ether, 0.01 ether, ""
        );
    }

    function test_postUpgradeInit() public {
        address proxyAdmin = makeAddr("proxyAdmin");
        vm.store(
            address(l1Gateway),
            0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103,
            bytes32(uint256(uint160(proxyAdmin)))
        );
        vm.prank(proxyAdmin);

        L1ArbitrumGateway(address(l1Gateway)).postUpgradeInit();
    }

    function test_postUpgradeInit_revert_NotFromAdmin() public {
        address proxyAdmin = makeAddr("proxyAdmin");
        vm.store(
            address(l1Gateway),
            0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103,
            bytes32(uint256(uint160(proxyAdmin)))
        );

        vm.expectRevert("NOT_FROM_ADMIN");
        L1ArbitrumGateway(address(l1Gateway)).postUpgradeInit();
    }

    function test_supportsInterface() public {
        bytes4 iface = type(IERC165).interfaceId;
        assertEq(l1Gateway.supportsInterface(iface), true, "Interface should be supported");

        iface = IL1ArbitrumGateway.outboundTransferCustomRefund.selector;
        assertEq(l1Gateway.supportsInterface(iface), true, "Interface should be supported");

        iface = bytes4(0);
        assertEq(l1Gateway.supportsInterface(iface), false, "Interface shouldn't be supported");

        iface = IL1ArbitrumGateway.inbox.selector;
        assertEq(l1Gateway.supportsInterface(iface), false, "Interface shouldn't be supported");
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
}

contract L1ArbitrumGatewayMock is L1ArbitrumGateway {
    function calculateL2TokenAddress(address x)
        public
        view
        override(ITokenGateway, TokenGateway)
        returns (address)
    {
        return x;
    }
}

contract MockReentrantInbox {
    function createRetryableTicket(
        address,
        uint256,
        uint256,
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) external payable returns (uint256) {
        // re-enter
        L1ArbitrumGateway(msg.sender).outboundTransferCustomRefund{value: msg.value}(
            address(100), address(100), address(100), 2, 2, 2, bytes("")
        );
    }
}

contract MockReentrantERC20 {
    function balanceOf(address) external returns (uint256) {
        // re-enter
        L1ArbitrumGateway(msg.sender).outboundTransferCustomRefund(
            address(100), address(100), address(100), 2, 2, 3, bytes("")
        );
        return 5;
    }

    function bridgeBurn(address, uint256) external {
        // re-enter
        L1ArbitrumGateway(msg.sender).outboundTransferCustomRefund(
            address(100), address(100), address(100), 2, 2, 3, bytes("")
        );
    }
}
