// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./ReferentGasReport.t.sol";
import {L1ERC20Gateway} from "contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol";

contract CurrentGasReportTest is ReferentGasReportTest {
    /* solhint-disable func-name-mixedcase */
    function test_depositToken() public override {
        // create instance of L1ERC20Gateway contract from current code, and use it in place of
        // actual standard gateway logic code that is deployed on-chain
        L1ERC20Gateway gateway = new L1ERC20Gateway();
        vm.etch(address(0xb4299A1F5f26fF6a98B7BA35572290C359fde900), address(gateway).code);

        super.test_depositToken();
    }
}
