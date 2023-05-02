// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { GatewayRouter } from "contracts/tokenbridge/libraries/gateway/GatewayRouter.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "forge-std/console.sol";

abstract contract GatewayRouterTest is Test {
    GatewayRouter public router;
    address public defaultGateway;

    // retryable params
    uint256 public maxSubmissionCost = 50000;
    uint256 public maxGas = 1000000000;
    uint256 public gasPriceBid = 3;
    uint256 public retryableCost = maxSubmissionCost + maxGas * gasPriceBid;
    address public creditBackAddress = makeAddr("creditBackAddress");

    /* solhint-disable func-name-mixedcase */
    function test_getGateway_DefaultGateway(address token) public {
        address gateway = router.getGateway(token);
        assertEq(gateway, defaultGateway, "Invalid gateway");
    }
}
