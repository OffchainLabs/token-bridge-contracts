// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {MasterVault} from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MasterVaultFactory
} from "../../../contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {
    FeeOnTransferERC20
} from "../../../contracts/tokenbridge/test/FeeOnTransferERC20.sol";
import {IGatewayRouter} from "../../../contracts/tokenbridge/libraries/gateway/IGatewayRouter.sol";
import {MockGatewayRouter} from "./MasterVaultCore.t.sol";

contract MasterVaultFeeOnTransferTest is Test {
    MasterVaultFactory public factory;
    MasterVault public vault;
    FeeOnTransferERC20 public token;

    address public user = vm.addr(1);
    address public feeRecipient = address(0xFEE);
    uint256 public constant FEE_BPS = 500; // 5%

    function setUp() public {
        token = new FeeOnTransferERC20(FEE_BPS, feeRecipient);

        factory = new MasterVaultFactory();
        MockGatewayRouter mockGatewayRouter = new MockGatewayRouter(user);
        MasterVault impl = new MasterVault();

        factory.initialize(
            address(impl), address(this), IGatewayRouter(address(mockGatewayRouter))
        );

        vault = MasterVault(factory.deployVault(address(token)));
    }

    function test_deposit_sharesMatchActualReceived() public {
        uint256 depositAmount = 1000e18;
        uint256 expectedReceived = depositAmount - (depositAmount * FEE_BPS / 10_000);

        vm.startPrank(user);
        token.mintAmount(depositAmount);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount);
        vm.stopPrank();

        assertEq(shares, expectedReceived, "shares != actual received");
        assertEq(vault.balanceOf(user), expectedReceived, "user share balance wrong");
        assertEq(token.balanceOf(address(vault)), expectedReceived, "vault token balance wrong");
    }
}
