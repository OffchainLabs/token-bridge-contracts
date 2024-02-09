// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import {L1GatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";

contract ReferentGasReportTest is Test {
    /* solhint-disable func-name-mixedcase */

    // based on TX: 0x5e84c997db3f2a2f473728bd4c16609278b164ed850df6bc158052c3eecdf363
    function test_depositToken() public virtual {
        L1GatewayRouter router = L1GatewayRouter(0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef);
        address origin = address(0xA12acA14a746418666B8e133850e8176F9D615Bb);

        bytes memory data =
            hex"0000000000000000000000000000000000000000000000000003deb52de72c4000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000";

        vm.prank(origin);
        router.outboundTransfer{value: 0.00112678987070368 ether}(
            address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599),
            address(0xA12acA14a746418666B8e133850e8176F9D615Bb),
            uint256(129_915_934),
            uint256(124_984),
            uint256(300_000_000),
            data
        );
    }
}
