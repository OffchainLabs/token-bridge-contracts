// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {L1YbbERC20Gateway} from "contracts/tokenbridge/ethereum/gateway/L1YbbERC20Gateway.sol";
import {L1GatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import {MasterVault} from "contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MasterVaultFactory} from "contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {MasterVaultRoles} from "contracts/tokenbridge/libraries/vault/MasterVaultRoles.sol";
import {
    BeaconProxyFactory,
    ClonableBeaconProxy
} from "contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IGatewayRouter} from "contracts/tokenbridge/libraries/gateway/IGatewayRouter.sol";
import {ITokenGateway} from "contracts/tokenbridge/libraries/gateway/ITokenGateway.sol";
import {TestERC20} from "contracts/tokenbridge/test/TestERC20.sol";
import {InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    GatewayMessageHandler
} from "contracts/tokenbridge/libraries/gateway/GatewayMessageHandler.sol";

contract L1YbbERC20GatewayTest is Test {
    L1YbbERC20Gateway public gateway;
    L1GatewayRouter public router;
    MasterVaultFactory public factory;
    TestERC20 public token;
    InboxMock public inbox;

    address public l2Gateway = makeAddr("l2Gateway");
    address public l2Router = makeAddr("l2Router");
    address public l2BeaconProxyFactory = makeAddr("l2BeaconProxyFactory");
    address public user = makeAddr("user");
    address public l2Dest = makeAddr("l2Dest");

    uint256 public constant DEPOSIT_AMOUNT = 1000e18;
    uint256 public constant EXTRA_DECIMALS = 6;
    uint256 public maxSubmissionCost = 0;
    uint256 public maxGas = 1_000_000;
    uint256 public gasPriceBid = 1;

    function setUp() public {
        inbox = new InboxMock();
        router = new L1GatewayRouter();

        MasterVaultRoles rolesRegistry = new MasterVaultRoles();
        rolesRegistry.initialize(address(this));

        MasterVault masterVaultImpl = new MasterVault();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(masterVaultImpl));
        BeaconProxyFactory beaconProxyFactory = new BeaconProxyFactory();
        beaconProxyFactory.initialize(address(beacon));

        factory = new MasterVaultFactory();

        gateway = new L1YbbERC20Gateway();
        gateway.initialize(
            l2Gateway,
            address(router),
            address(inbox),
            keccak256(type(ClonableBeaconProxy).creationCode),
            l2BeaconProxyFactory,
            address(factory)
        );

        router.initialize(
            address(this), // owner
            address(gateway), // default gateway
            address(0), // whitelist (unused)
            l2Router, // counterpart
            address(inbox)
        );

        factory.initialize(
            address(rolesRegistry), address(beaconProxyFactory), IGatewayRouter(address(router))
        );

        token = new TestERC20();
        vm.prank(user);
        token.mintAmount(DEPOSIT_AMOUNT);
    }

    function test_outboundTransfer_depositsToVault() public {
        uint256 userBalanceBefore = token.balanceOf(user);
        assertEq(userBalanceBefore, DEPOSIT_AMOUNT, "User should have tokens");

        vm.prank(user);
        token.approve(address(gateway), DEPOSIT_AMOUNT);

        bytes memory userData = abi.encode(maxSubmissionCost, "");

        // needed ETH to cover the retryable ticket: maxSubmissionCost + maxGas * gasPriceBid
        uint256 retryableCost = maxSubmissionCost + maxGas * gasPriceBid;
        vm.deal(user, retryableCost);

        vm.prank(user);
        router.outboundTransferCustomRefund{value: retryableCost}(
            address(token), user, l2Dest, DEPOSIT_AMOUNT, maxGas, gasPriceBid, userData
        );

        assertEq(token.balanceOf(user), 0, "User should have no tokens left");

        // verify MasterVault was deployed and holds the tokens
        address vaultAddr = factory.calculateVaultAddress(address(token));
        assertTrue(vaultAddr.code.length > 0, "Vault should be deployed");
        assertEq(token.balanceOf(vaultAddr), DEPOSIT_AMOUNT, "Vault should hold deposited tokens");

        // verify gateway holds vault shares
        // shares = DEPOSIT_AMOUNT * totalSupply / totalAssets
        //        = DEPOSIT_AMOUNT * 10^6 / (1 + 0) = DEPOSIT_AMOUNT * 10^6
        uint256 expectedShares = DEPOSIT_AMOUNT * (10 ** EXTRA_DECIMALS);
        MasterVault vault = MasterVault(vaultAddr);
        assertEq(
            vault.balanceOf(address(gateway)), expectedShares, "Gateway should hold vault shares"
        );

        // verify vault total assets includes the deposit
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT + 1, "Vault totalAssets should be deposit + 1");

        // vault total supply = dead shares + minted shares
        uint256 deadShares = 10 ** EXTRA_DECIMALS;
        assertEq(
            vault.totalSupply(),
            deadShares + expectedShares,
            "Vault totalSupply should be deadShares + userShares"
        );
    }

    function test_vault_registryAdminCanGrantLocalRoles() public {
        _depositToCreateVault();
        MasterVault vault = MasterVault(factory.calculateVaultAddress(address(token)));

        address manager = makeAddr("manager");
        vault.grantRole(vault.GENERAL_MANAGER_ROLE(), manager);
        assertTrue(vault.hasRole(vault.GENERAL_MANAGER_ROLE(), manager));
    }

    function test_outboundTransfer_revertsOnZeroShares() public {
        vm.prank(user);
        token.approve(address(gateway), 0);

        bytes memory userData = abi.encode(maxSubmissionCost, "");
        uint256 retryableCost = maxSubmissionCost + maxGas * gasPriceBid;
        vm.deal(user, retryableCost);

        vm.prank(user);
        vm.expectRevert("ZERO_SHARES");
        router.outboundTransferCustomRefund{value: retryableCost}(
            address(token), user, l2Dest, 0, maxGas, gasPriceBid, userData
        );
    }

    function _depositToCreateVault() internal {
        vm.prank(user);
        token.approve(address(gateway), DEPOSIT_AMOUNT);
        uint256 retryableCost = maxSubmissionCost + maxGas * gasPriceBid;
        vm.deal(user, retryableCost);
        vm.prank(user);
        router.outboundTransferCustomRefund{value: retryableCost}(
            address(token),
            user,
            l2Dest,
            DEPOSIT_AMOUNT,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );
    }

    function test_getOutboundCalldata_reportsVaultDecimals() public {
        vm.prank(user);
        token.approve(address(gateway), DEPOSIT_AMOUNT);

        bytes memory userData = abi.encode(maxSubmissionCost, "");
        uint256 retryableCost = maxSubmissionCost + maxGas * gasPriceBid;
        vm.deal(user, retryableCost);

        vm.prank(user);
        router.outboundTransferCustomRefund{value: retryableCost}(
            address(token), user, l2Dest, DEPOSIT_AMOUNT, maxGas, gasPriceBid, userData
        );

        uint8 vaultDecimals = token.decimals() + uint8(EXTRA_DECIMALS);

        bytes memory outboundCalldata = gateway.getOutboundCalldata(
            address(token), user, l2Dest, DEPOSIT_AMOUNT, abi.encode("test")
        );

        bytes memory expectedCalldata = abi.encodeWithSelector(
            ITokenGateway.finalizeInboundTransfer.selector,
            address(token),
            user,
            l2Dest,
            DEPOSIT_AMOUNT,
            abi.encode(
                abi.encode(
                    abi.encode("IntArbTestToken"), abi.encode("IARB"), abi.encode(vaultDecimals)
                ),
                abi.encode("test")
            )
        );

        assertEq(outboundCalldata, expectedCalldata, "Should encode vault decimals in calldata");
    }
}
