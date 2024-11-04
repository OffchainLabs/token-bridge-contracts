// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {L1GatewayRouter} from "../../contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import {L1ERC20Gateway} from "../../contracts/tokenbridge/ethereum/gateway/L1ERC20Gateway.sol";
import {L1CustomGateway} from "../../contracts/tokenbridge/ethereum/gateway/L1CustomGateway.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProductionGasReportTest is Test {
    /* solhint-disable func-name-mixedcase */

    // based on TX: 0xa23e528910c7cb0f4e86d1b3745e334ad84bcd600591857b44854a5b7ad1f804
    function test_depositTokenStdGateway() public virtual {
        L1GatewayRouter router = L1GatewayRouter(0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef);
        address origin = address(0x0936F059c3f3F6d354A268c927e83388A1db2BAe);
        uint256 amount = 0.00020920159720128 ether;
        address token = address(0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83);
        uint256 tokenAmount = 20_000_000_000_000_000_000_000;
        vm.deal(origin, amount);
        vm.startPrank(origin);
        IERC20(token).approve(address(0xa3A7B6F88361F48403514059F1F16C8E78d60EeC), tokenAmount);
        bytes memory data =
            hex"0000000000000000000000000000000000000000000000000000b4732c3f8dc000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000";
        uint256 gasBefore = gasleft();
        router.outboundTransfer{value: amount}({
            _token: token,
            _to: address(0x0936F059c3f3F6d354A268c927e83388A1db2BAe),
            _amount: tokenAmount,
            _maxGas: 124_975,
            _gasPriceBid: 86_376_000,
            _data: data
        });
        uint256 gasAfter = gasleft();
        console.log("GAs used:", gasBefore - gasAfter);
    }

    function test_Tstore() public {
        L1ERC20Gateway gateway = new L1ERC20Gateway();
        vm.etch(address(0xb4299A1F5f26fF6a98B7BA35572290C359fde900), address(gateway).code);
        test_depositTokenStdGateway();
    }

    // based on TX: 0xf7925d851185bed53740694b1bcaaf7e78038847c259039d037a1ee7ccfcb38f
    function test_depositTokenCustomGateway() public virtual {
        L1GatewayRouter router = L1GatewayRouter(0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef);
        address origin = address(0x41d3D33156aE7c62c094AAe2995003aE63f587B3);
        uint256 amount = 0.000092506225179456 ether;
        address token = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        uint256 tokenAmount = 50_000_000_000;
        vm.deal(origin, amount);
        vm.startPrank(origin);
        IERC20(token).approve(address(0xcEe284F754E854890e311e3280b767F80797180d), tokenAmount);
        bytes memory data =
            hex"00000000000000000000000000000000000000000000000000004520940d734000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000";
        uint256 gasBefore = gasleft();
        router.outboundTransfer{value: amount}({
            _token: token,
            _to: address(0x0301A3C9887E2B8C26f9e8B48d56b81E7f4B3bCD),
            _amount: tokenAmount,
            _maxGas: 275_000,
            _gasPriceBid: 60_000_000,
            _data: data
        });
        uint256 gasAfter = gasleft();
        console.log("GAs used:", gasBefore - gasAfter);
    }

    function test_TstoreCustom() public {
        L1CustomGateway gateway = new L1CustomGateway();
        vm.etch(address(0xC8D26aB9e132C79140b3376a0Ac7932E4680Aa45), address(gateway).code);
        test_depositTokenCustomGateway();
    }
}
