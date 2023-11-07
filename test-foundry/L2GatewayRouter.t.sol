// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {GatewayRouterTest} from "./GatewayRouter.t.sol";
import {L2GatewayRouter} from "contracts/tokenbridge/arbitrum/gateway/L2GatewayRouter.sol";
import {L1GatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import {L1ERC20Gateway} from "contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol";
import {L1CustomGateway} from "contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol";
import {InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";
import {IERC165} from "contracts/tokenbridge/libraries/IERC165.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20PresetMinterPauser} from
    "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract L2GatewayRouterTest is GatewayRouterTest {
    L2GatewayRouter public l2Router;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public counterpartGateway = makeAddr("counterpartGateway");
    address public inbox;

    function setUp() public virtual {
        inbox = address(new InboxMock());
        defaultGateway = address(new L1ERC20Gateway());

        router = new L2GatewayRouter();
        l2Router = L2GatewayRouter(address(router));
        l2Router.initialize(counterpartGateway, defaultGateway);

        // maxSubmissionCost = 50000;
        // retryableCost = maxSubmissionCost + maxGas * gasPriceBid;

        // vm.deal(owner, 100 ether);
        // vm.deal(user, 100 ether);
    }
}
