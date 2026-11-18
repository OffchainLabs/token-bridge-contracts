// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MasterVaultCoreTest, MockGatewayRouter} from "./MasterVaultCore.t.sol";
import {MasterVault} from "../../../contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {
    MasterVaultFactory
} from "../../../contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {IGatewayRouter} from "../../../contracts/tokenbridge/libraries/gateway/IGatewayRouter.sol";
import {MockSubVault} from "../../../contracts/tokenbridge/test/MockSubVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract FeeOnTransferToken is ERC20 {
    uint256 public flatFee;

    constructor() ERC20("FeeToken", "FEE") {}

    function setFee(uint256 _flatFee) external {
        flatFee = _flatFee;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (flatFee > 0) {
            super.transferFrom(from, address(0xdead), flatFee);
            return super.transferFrom(from, to, amount - flatFee);
        }
        return super.transferFrom(from, to, amount);
    }
}

contract MasterVaultFirstDepositTest is MasterVaultCoreTest {
    using Math for uint256;

    // first deposit
    function test_deposit(uint96 _depositAmount) public {
        uint256 depositAmount = _depositAmount;
        vm.startPrank(user);
        token.mintAmount(depositAmount);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount);
        vm.stopPrank();
        _checkState(
            State({
                userShares: depositAmount,
                masterVaultTotalAssets: depositAmount + 1,
                masterVaultTotalSupply: (1 + depositAmount),
                masterVaultTokenBalance: depositAmount,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        assertEq(shares, depositAmount, "shares mismatch deposit return value");
    }

    function test_deposit_revertsFeeOnTransfer() public {
        FeeOnTransferToken fotToken = new FeeOnTransferToken();
        MockGatewayRouter mockRouter = new MockGatewayRouter(user);
        MasterVault impl = new MasterVault();
        MasterVaultFactory f = new MasterVaultFactory();
        f.initialize(address(impl), address(this), IGatewayRouter(address(mockRouter)));
        MasterVault v = MasterVault(f.deployVault(address(fotToken)));

        uint256 amount = 1000e18;
        uint256 fee = 1e18;
        fotToken.mint(user, amount);
        fotToken.setFee(fee);

        vm.startPrank(user);
        fotToken.approve(address(v), amount);
        vm.expectRevert(
            abi.encodeWithSelector(MasterVault.FeeOnTransferNotSupported.selector, amount, amount - fee)
        );
        v.deposit(amount);
        vm.stopPrank();
    }

    function test_redeem(uint96 _firstDeposit, uint96 _redeemAmount) public {
        uint256 firstDeposit = _firstDeposit;
        uint256 redeemAmount = _redeemAmount;
        vm.assume(redeemAmount <= firstDeposit);
        test_deposit(_firstDeposit);
        State memory beforeState = _getState();
        vm.startPrank(user);
        uint256 assets = vault.redeem(redeemAmount, 0);
        uint256 expectedAssets = (beforeState.masterVaultTotalAssets * redeemAmount)
            / (beforeState.masterVaultTotalSupply);
        vm.stopPrank();
        _checkState(
            State({
                userShares: beforeState.userShares - redeemAmount,
                masterVaultTotalAssets: beforeState.masterVaultTotalAssets - expectedAssets,
                masterVaultTotalSupply: beforeState.masterVaultTotalSupply - redeemAmount,
                masterVaultTokenBalance: beforeState.masterVaultTokenBalance - expectedAssets,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: 0,
                subVaultTotalSupply: 0,
                subVaultTokenBalance: 0
            })
        );
        assertEq(assets, expectedAssets, "assets mismatch redeem return value");
    }
}

contract MasterVaultTestWithSubvaultFresh is MasterVaultFirstDepositTest {
    function setUp() public override {
        super.setUp();
        MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");

        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.setSubVaultWhitelist(address(_subvault), true);
        vault.setSubVault(IERC4626(address(_subvault)));
    }
}

contract MasterVaultTestWithSubvaultHoldingAssets is MasterVaultFirstDepositTest {
    function _setupSubvaultWithAssets(uint256 _initAmount) internal {
        MockSubVault _subvault = new MockSubVault(IERC20(address(token)), "TestSubvault", "TSV");
        token.mintAmount(_initAmount);
        token.approve(address(_subvault), _initAmount);
        _subvault.deposit(_initAmount, address(this));
        assertEq(
            _initAmount,
            _subvault.totalAssets(),
            "subvault should be initiated with assets = _initAmount"
        );
        assertEq(
            _initAmount,
            _subvault.totalSupply(),
            "subvault should be initiated with shares = _initAmount"
        );

        vault.rolesRegistry().grantRole(vault.GENERAL_MANAGER_ROLE(), address(this));
        vault.setSubVaultWhitelist(address(_subvault), true);
        vault.setSubVault(IERC4626(address(_subvault)));
    }

    function test_deposit(uint96 _depositAmount, uint96 _initAmount) public {
        uint256 depositAmount = _depositAmount;
        uint256 initAmount = _initAmount;
        _setupSubvaultWithAssets(initAmount);

        vm.startPrank(user);
        token.mintAmount(depositAmount);
        token.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount);
        vm.stopPrank();
        _checkState(
            State({
                userShares: depositAmount,
                masterVaultTotalAssets: depositAmount + 1,
                masterVaultTotalSupply: (1 + depositAmount),
                masterVaultTokenBalance: depositAmount,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: initAmount,
                subVaultTotalSupply: initAmount,
                subVaultTokenBalance: initAmount
            })
        );
        assertEq(shares, depositAmount, "shares mismatch deposit return value");
    }

    function test_redeem(uint96 _firstDeposit, uint96 _redeemAmount, uint96 _initAmount) public {
        uint256 firstDeposit = _firstDeposit;
        uint256 redeemAmount = _redeemAmount;
        vm.assume(redeemAmount <= firstDeposit);
        test_deposit(_firstDeposit, _initAmount);
        State memory beforeState = _getState();
        vm.startPrank(user);
        uint256 assets = vault.redeem(redeemAmount, 0);
        uint256 expectedAssets = (beforeState.masterVaultTotalAssets * redeemAmount)
            / (beforeState.masterVaultTotalSupply);
        vm.stopPrank();
        _checkState(
            State({
                userShares: beforeState.userShares - redeemAmount,
                masterVaultTotalAssets: beforeState.masterVaultTotalAssets - expectedAssets,
                masterVaultTotalSupply: beforeState.masterVaultTotalSupply - redeemAmount,
                masterVaultTokenBalance: beforeState.masterVaultTokenBalance - expectedAssets,
                masterVaultSubVaultShareBalance: 0,
                subVaultTotalAssets: beforeState.subVaultTotalAssets,
                subVaultTotalSupply: beforeState.subVaultTotalSupply,
                subVaultTokenBalance: beforeState.subVaultTokenBalance
            })
        );
        assertEq(assets, expectedAssets, "assets mismatch redeem return value");
    }
}
