// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {L1YbbCustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1YbbCustomGateway.sol";
import {L1GatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import {MasterVault} from "contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MasterVaultFactory} from "contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {IGatewayRouter} from "contracts/tokenbridge/libraries/gateway/IGatewayRouter.sol";
import {InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";

contract L1YbbCustomGatewayTest is Test {
    L1YbbCustomGateway public gateway;
    L1GatewayRouter public router;
    MasterVaultFactory public factory;
    InboxMock public inbox;

    address public l2Gateway = makeAddr("l2Gateway");
    address public l2Router = makeAddr("l2Router");
    address public owner = makeAddr("owner");

    function setUp() public {
        inbox = new InboxMock();
        router = new L1GatewayRouter();
        MasterVault masterVaultImpl = new MasterVault();
        factory = new MasterVaultFactory();

        gateway = new L1YbbCustomGateway();
        gateway.initialize(l2Gateway, address(router), address(inbox), owner, address(factory));

        router.initialize(address(this), address(gateway), address(0), l2Router, address(inbox));

        factory.initialize(address(masterVaultImpl), address(this), IGatewayRouter(address(router)));
    }

    function test_supportsInterface_slippageTolerance() public {
        assertTrue(
            gateway.supportsInterface(
                gateway.outboundTransferCustomRefundWithSlippageTolerance.selector
            ),
            "slippage-tolerance selector should be supported"
        );
        assertTrue(
            gateway.supportsInterface(gateway.outboundTransferCustomRefund.selector),
            "outboundTransferCustomRefund selector should still be supported"
        );
        assertFalse(gateway.supportsInterface(bytes4(0)), "zero selector should not be supported");
    }
}
