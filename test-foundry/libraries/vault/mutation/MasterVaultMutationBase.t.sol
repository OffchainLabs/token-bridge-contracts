// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest, MockGatewayRouter} from "../MasterVaultCore.t.sol";
import {MasterVault} from "../../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MasterVaultRoles
} from "../../../../contracts/tokenbridge/libraries/vault/MasterVaultRoles.sol";
import {
    DefaultSubVault,
    MasterVaultFactory
} from "../../../../contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {MockSubVault} from "../../../../contracts/tokenbridge/test/MockSubVault.sol";
import {TestERC20} from "../../../../contracts/tokenbridge/test/TestERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IGatewayRouter} from "../../../../contracts/tokenbridge/libraries/gateway/IGatewayRouter.sol";
import {IAccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import {Test, Vm} from "forge-std/Test.sol";

contract MasterVaultMutationBase is MasterVaultCoreTest {
    address public keeper = address(0xBBBB);
    address public beneficiaryAddr = address(0x9999);
    address public generalManager = address(0xAAAA);
    address public pauser = address(0xCCCC);

    function setUp() public override {
        super.setUp();
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), generalManager);
        vault.rolesRegistry().grantRole(vault.KEEPER_ROLE(), keeper);
        vault.rolesRegistry().grantRole(vault.FEE_MANAGER_ROLE(), address(this));
        vault.rolesRegistry().grantRole(vault.PAUSER_ROLE(), pauser);
        vault.setBeneficiary(beneficiaryAddr);
        vault.setMinimumRebalanceAmount(1);
    }

    function _depositAs(uint256 amount) internal returns (uint256) {
        vm.prank(user);
        token.mintAmount(amount);
        vm.startPrank(user);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount);
        vm.stopPrank();
        return shares;
    }

    function _setupWithAllocation(uint256 depositAmount, uint64 allocationWad) internal {
        _depositAs(depositAmount);
        vault.setTargetAllocationWad(allocationWad);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vault.rebalance(-1e18);
    }
}
