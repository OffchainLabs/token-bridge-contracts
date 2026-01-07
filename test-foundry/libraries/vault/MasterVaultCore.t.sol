// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { MasterVault } from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MasterVaultFactory
} from "../../../contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import { TestERC20 } from "../../../contracts/tokenbridge/test/TestERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {
    BeaconProxyFactory,
    ClonableBeaconProxy
} from "../../../contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { console2 } from "forge-std/console2.sol";

contract MasterVaultCoreTest is Test {
    MasterVaultFactory public factory;
    MasterVault public vault;
    TestERC20 public token;

    address public user = vm.addr(1);
    string public name = "Master Test Token";
    string public symbol = "mTST";
    uint256 public constant DEAD_SHARES = 10 ** 18;

    struct State {
        uint256 userShares;
        uint256 masterVaultTotalAssets;
        uint256 masterVaultTotalSupply;
        uint256 masterVaultTokenBalance;
        uint256 masterVaultSubVaultShareBalance;
        uint256 masterVaultTotalPrincipal;
        uint256 subVaultTotalAssets;
        uint256 subVaultTotalSupply;
        uint256 subVaultTokenBalance;
    }

    function getAssetsHoldingVault() internal view virtual returns (address) {
        return address(vault.subVault()) == address(0) ? address(vault) : address(vault.subVault());
    }

    function setUp() public virtual {
        factory = new MasterVaultFactory();
        factory.initialize(address(this));
        token = new TestERC20();
        vault = MasterVault(factory.deployVault(address(token)));
    }

    function _checkState(State memory expectedState) internal {
        assertEq(expectedState.userShares, vault.balanceOf(user), "userShares mismatch");
        assertEq(
            expectedState.masterVaultTotalAssets,
            vault.totalAssets(),
            "masterVaultTotalAssets mismatch"
        );
        assertEq(
            expectedState.masterVaultTotalSupply,
            vault.totalSupply(),
            "masterVaultTotalSupply mismatch"
        );
        assertEq(
            expectedState.masterVaultTokenBalance,
            token.balanceOf(address(vault)),
            "masterVaultTokenBalance mismatch"
        );
        assertEq(
            expectedState.masterVaultSubVaultShareBalance,
            vault.subVault().balanceOf(address(vault)),
            "masterVaultSubVaultShareBalance mismatch"
        );
        assertEq(
            expectedState.masterVaultTotalPrincipal,
            vault.totalPrincipal(),
            "masterVaultTotalPrincipal mismatch"
        );
        assertEq(
            expectedState.subVaultTotalAssets,
            vault.subVault().totalAssets(),
            "subVaultTotalAssets mismatch"
        );
        assertEq(
            expectedState.subVaultTotalSupply,
            vault.subVault().totalSupply(),
            "subVaultTotalSupply mismatch"
        );
        assertEq(
            expectedState.subVaultTokenBalance,
            token.balanceOf(address(vault.subVault())),
            "subVaultTokenBalance mismatch"
        );
    }

    function _getState() internal view returns (State memory) {
        return
            State({
                userShares: vault.balanceOf(user),
                masterVaultTotalAssets: vault.totalAssets(),
                masterVaultTotalSupply: vault.totalSupply(),
                masterVaultTokenBalance: token.balanceOf(address(vault)),
                masterVaultSubVaultShareBalance: vault.subVault().balanceOf(address(vault)),
                masterVaultTotalPrincipal: vault.totalPrincipal(),
                subVaultTotalAssets: vault.subVault().totalAssets(),
                subVaultTotalSupply: vault.subVault().totalSupply(),
                subVaultTokenBalance: token.balanceOf(address(vault.subVault()))
            });
    }

    function _logState(string memory label, State memory state) internal view {
        console2.log(label);
        console2.log(" userShares:", state.userShares);
        console2.log(" masterVaultTotalAssets:", state.masterVaultTotalAssets);
        console2.log(" masterVaultTotalSupply:", state.masterVaultTotalSupply);
        console2.log(" masterVaultTokenBalance:", state.masterVaultTokenBalance);
        console2.log(" masterVaultSubVaultShareBalance:", state.masterVaultSubVaultShareBalance);
        console2.log(" masterVaultTotalPrincipal:", state.masterVaultTotalPrincipal);
        console2.log(" subVaultTotalAssets:", state.subVaultTotalAssets);
        console2.log(" subVaultTotalSupply:", state.subVaultTotalSupply);
        console2.log(" subVaultTokenBalance:", state.subVaultTokenBalance);
    }
}
