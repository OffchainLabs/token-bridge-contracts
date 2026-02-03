// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {L1YbbERC20Gateway} from "contracts/tokenbridge/ethereum/gateway/L1YbbERC20Gateway.sol";
import {L1GatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import {MasterVault} from "contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MasterVaultFactory} from "contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {IGatewayRouter} from "contracts/tokenbridge/libraries/gateway/IGatewayRouter.sol";
import {TestERC20} from "contracts/tokenbridge/test/TestERC20.sol";
import {InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Yield Bearing Bridge End-to-End Tests
 * @notice Tests the full deposit and redeem flows through the gateway with YBB integration
 * @dev These tests verify:
 *      - User deposits through L1GatewayRouter → L1YbbERC20Gateway → MasterVault.deposit()
 *      - User withdrawals through finalizeInboundTransfer → MasterVault.redeem() → User
 *      - Multiple users depositing and redeeming
 *      - Subvault allocation and rebalancing
 */
contract YieldBearingBridgeE2ETest is Test {
    L1GatewayRouter public router;
    L1YbbERC20Gateway public gateway;
    MasterVaultFactory public vaultFactory;
    MasterVault public masterVault;
    TestERC20 public token;
    InboxMock public inbox;

    address public l2Gateway = makeAddr("l2Gateway");
    address public l2Router = makeAddr("l2Router");
    address public owner = makeAddr("owner");
    address public userA = makeAddr("userA");
    address public userB = makeAddr("userB");

    bytes32 public cloneableProxyHash =
        0x0000000000000000000000000000000000000000000000000000000000000001;
    address public l2BeaconProxyFactory = makeAddr("l2BeaconProxyFactory");

    uint256 public maxSubmissionCost = 70;
    uint256 public maxGas = 1_000_000_000;
    uint256 public gasPriceBid = 100_000_000;
    uint256 public retryableCost;

    uint256 public constant DEAD_SHARES = 10 ** 6;

    event DepositInitiated(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _sequenceNumber,
        uint256 _amount
    );

    event WithdrawalFinalized(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _exitNum,
        uint256 _amount
    );

    function setUp() public {
        inbox = new InboxMock();
        router = new L1GatewayRouter();
        gateway = new L1YbbERC20Gateway();
        token = new TestERC20();

        vaultFactory = new MasterVaultFactory();
        vaultFactory.initialize(owner, IGatewayRouter(address(router)));

        gateway.initialize(
            l2Gateway,
            address(router),
            address(inbox),
            cloneableProxyHash,
            l2BeaconProxyFactory,
            address(vaultFactory)
        );

        router.initialize(owner, address(gateway), address(0), l2Router, address(inbox));

        retryableCost = maxSubmissionCost + gasPriceBid * maxGas;

        vm.prank(userA);
        token.mint(10_000 ether);
        vm.prank(userB);
        token.mint(10_000 ether);

        vm.deal(userA, 100 ether);
        vm.deal(userB, 100 ether);

        masterVault = MasterVault(vaultFactory.deployVault(address(token)));

        vm.startPrank(owner);
        vaultFactory.rolesRegistry().grantRole(masterVault.GENERAL_MANAGER_ROLE(), owner);
        vaultFactory.rolesRegistry().grantRole(masterVault.FEE_MANAGER_ROLE(), owner);
        vaultFactory.rolesRegistry().grantRole(masterVault.KEEPER_ROLE(), owner);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_singleUser() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(userA);
        token.approve(address(gateway), depositAmount);
        uint256 userBalanceBefore = token.balanceOf(userA);

        router.outboundTransfer{value: retryableCost}(
            address(token),
            userA,
            depositAmount,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );
        vm.stopPrank();

        assertEq(
            token.balanceOf(userA),
            userBalanceBefore - depositAmount,
            "User balance should decrease"
        );
        assertEq(
            token.balanceOf(address(masterVault)), depositAmount, "MasterVault should hold tokens"
        );
        assertEq(
            masterVault.balanceOf(address(gateway)),
            depositAmount * DEAD_SHARES,
            "Gateway should hold shares"
        );
    }

    function test_deposit_multipleUsers() public {
        uint256 depositAmountA = 100 ether;
        uint256 depositAmountB = 300 ether;

        vm.startPrank(userA);
        token.approve(address(gateway), depositAmountA);
        router.outboundTransfer{value: retryableCost}(
            address(token),
            userA,
            depositAmountA,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );
        vm.stopPrank();

        vm.startPrank(userB);
        token.approve(address(gateway), depositAmountB);
        router.outboundTransfer{value: retryableCost}(
            address(token),
            userB,
            depositAmountB,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );
        vm.stopPrank();

        assertEq(
            token.balanceOf(address(masterVault)),
            depositAmountA + depositAmountB,
            "MasterVault should hold all tokens"
        );
        assertEq(
            masterVault.balanceOf(address(gateway)),
            (depositAmountA + depositAmountB) * DEAD_SHARES,
            "Gateway should hold all shares"
        );
    }

    function test_deposit_withSlippageCheck() public {
        uint256 depositAmount = 100 ether;
        uint256 minimumShares = depositAmount * DEAD_SHARES;

        vm.startPrank(userA);
        token.approve(address(gateway), depositAmount);
        bytes memory extraData = abi.encode(uint256(0), minimumShares);
        router.outboundTransfer{value: retryableCost}(
            address(token),
            userA,
            depositAmount,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, extraData)
        );
        vm.stopPrank();

        assertEq(
            masterVault.balanceOf(address(gateway)),
            minimumShares,
            "Gateway should have received expected shares"
        );
    }

    function test_deposit_slippageCheckFails() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(userB);
        token.approve(address(gateway), 100 ether);
        router.outboundTransfer{value: retryableCost}(
            address(token), userB, 100 ether, maxGas, gasPriceBid, abi.encode(maxSubmissionCost, "")
        );
        vm.stopPrank();

        vm.prank(address(masterVault));
        token.transfer(address(0xdead), 50 ether);

        vm.startPrank(userA);
        token.approve(address(gateway), depositAmount);
        uint256 unrealisticMinShares = depositAmount * DEAD_SHARES * 2;
        bytes memory extraData = abi.encode(uint256(0), unrealisticMinShares);

        vm.expectRevert("INSUFFICIENT_AMOUNT_RECEIVED");
        router.outboundTransfer{value: retryableCost}(
            address(token),
            userA,
            depositAmount,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, extraData)
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_redeem_singleUser() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(userA);
        token.approve(address(gateway), depositAmount);
        router.outboundTransfer{value: retryableCost}(
            address(token),
            userA,
            depositAmount,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );
        vm.stopPrank();

        uint256 sharesToRedeem = masterVault.balanceOf(address(gateway));
        uint256 userBalanceBefore = token.balanceOf(userA);

        inbox.setL2ToL1Sender(l2Gateway);
        vm.prank(address(inbox));
        gateway.finalizeInboundTransfer(
            address(token), userA, userA, sharesToRedeem, abi.encode(uint256(1), "")
        );

        assertEq(
            token.balanceOf(userA) - userBalanceBefore,
            depositAmount,
            "User should receive all tokens back"
        );
        assertEq(masterVault.balanceOf(address(gateway)), 0, "Gateway should have 0 shares");
    }

    function test_redeem_multipleUsers() public {
        uint256 depositAmountA = 100 ether;
        uint256 depositAmountB = 300 ether;

        vm.startPrank(userA);
        token.approve(address(gateway), depositAmountA);
        router.outboundTransfer{value: retryableCost}(
            address(token),
            userA,
            depositAmountA,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );
        vm.stopPrank();

        uint256 sharesA = masterVault.balanceOf(address(gateway));

        vm.startPrank(userB);
        token.approve(address(gateway), depositAmountB);
        router.outboundTransfer{value: retryableCost}(
            address(token),
            userB,
            depositAmountB,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );
        vm.stopPrank();

        uint256 sharesB = masterVault.balanceOf(address(gateway)) - sharesA;

        inbox.setL2ToL1Sender(l2Gateway);

        uint256 userABalanceBefore = token.balanceOf(userA);
        vm.prank(address(inbox));
        gateway.finalizeInboundTransfer(
            address(token), userA, userA, sharesA, abi.encode(uint256(1), "")
        );
        assertEq(
            token.balanceOf(userA) - userABalanceBefore,
            depositAmountA,
            "User A should receive their deposit"
        );

        uint256 userBBalanceBefore = token.balanceOf(userB);
        vm.prank(address(inbox));
        gateway.finalizeInboundTransfer(
            address(token), userB, userB, sharesB, abi.encode(uint256(2), "")
        );
        assertEq(
            token.balanceOf(userB) - userBBalanceBefore,
            depositAmountB,
            "User B should receive their deposit"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        SUBVAULT ALLOCATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositAndRedeem_withSubvaultAllocation() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(owner);
        masterVault.setMinimumRebalanceAmount(1);
        masterVault.setTargetAllocationWad(1e18);
        vm.stopPrank();

        vm.startPrank(userA);
        token.approve(address(gateway), depositAmount);
        router.outboundTransfer{value: retryableCost}(
            address(token),
            userA,
            depositAmount,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );
        vm.stopPrank();

        uint256 shares = masterVault.balanceOf(address(gateway));

        vm.prank(owner);
        masterVault.rebalance(type(int256).min + 1);

        assertEq(token.balanceOf(address(masterVault)), 0, "MasterVault should have 0 idle tokens");
        assertGt(token.balanceOf(address(masterVault.subVault())), 0, "SubVault should hold tokens");

        inbox.setL2ToL1Sender(l2Gateway);
        uint256 userBalanceBefore = token.balanceOf(userA);

        vm.prank(address(inbox));
        gateway.finalizeInboundTransfer(
            address(token), userA, userA, shares, abi.encode(uint256(1), "")
        );

        assertEq(
            token.balanceOf(userA) - userBalanceBefore,
            depositAmount,
            "User should receive full deposit"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_redeem_revertOnInvalidSender() public {
        inbox.setL2ToL1Sender(address(0));
        vm.prank(address(inbox));
        vm.expectRevert("NO_SENDER");
        gateway.finalizeInboundTransfer(
            address(token), userA, userA, 100, abi.encode(uint256(1), "")
        );
    }

    function test_redeem_revertOnWrongCounterpart() public {
        inbox.setL2ToL1Sender(makeAddr("wrongGateway"));
        vm.prank(address(inbox));
        vm.expectRevert("ONLY_COUNTERPART_GATEWAY");
        gateway.finalizeInboundTransfer(
            address(token), userA, userA, 100, abi.encode(uint256(1), "")
        );
    }

    function test_deposit_revertNotFromRouter() public {
        vm.prank(userA);
        token.approve(address(gateway), 100 ether);
        vm.prank(userA);
        vm.expectRevert("NOT_FROM_ROUTER");
        gateway.outboundTransfer(
            address(token), userA, 100 ether, maxGas, gasPriceBid, abi.encode(maxSubmissionCost, "")
        );
    }

    function test_fuzz_depositAndRedeem(uint96 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);

        vm.prank(userA);
        token.mint(depositAmount);

        vm.startPrank(userA);
        token.approve(address(gateway), depositAmount);
        router.outboundTransfer{value: retryableCost}(
            address(token),
            userA,
            depositAmount,
            maxGas,
            gasPriceBid,
            abi.encode(maxSubmissionCost, "")
        );
        vm.stopPrank();

        uint256 shares = masterVault.balanceOf(address(gateway));
        uint256 userBalanceBefore = token.balanceOf(userA);

        inbox.setL2ToL1Sender(l2Gateway);
        vm.prank(address(inbox));
        gateway.finalizeInboundTransfer(
            address(token), userA, userA, shares, abi.encode(uint256(1), "")
        );

        assertEq(
            token.balanceOf(userA) - userBalanceBefore,
            depositAmount,
            "User should receive exact deposit"
        );
    }
}
