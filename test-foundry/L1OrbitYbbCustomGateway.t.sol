// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {
    L1OrbitYbbCustomGateway
} from "contracts/tokenbridge/ethereum/gateway/L1OrbitYbbCustomGateway.sol";
import {
    L1OrbitCustomGateway
} from "contracts/tokenbridge/ethereum/gateway/L1OrbitCustomGateway.sol";
import {L1GatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import {MasterVault} from "contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MasterVaultFactory} from "contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {IGatewayRouter} from "contracts/tokenbridge/libraries/gateway/IGatewayRouter.sol";
import {TestERC20} from "contracts/tokenbridge/test/TestERC20.sol";
import {ERC20InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    ERC20PresetMinterPauser
} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract L1OrbitYbbCustomGatewayTest is Test {
    L1OrbitYbbCustomGateway public gateway;
    L1GatewayRouter public router;
    MasterVaultFactory public factory;
    TestERC20 public token;
    ERC20InboxMock public inbox;
    ERC20 public nativeToken;

    address public l2Gateway = makeAddr("l2Gateway");
    address public l2Router = makeAddr("l2Router");
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public l2Dest = makeAddr("l2Dest");
    address public creditBackAddress = makeAddr("creditBackAddress");

    uint256 public constant DEPOSIT_AMOUNT = 1000e18;
    uint256 public constant EXTRA_DECIMALS = 6;
    uint256 public maxSubmissionCost = 0;
    uint256 public maxGas = 1_000_000;
    uint256 public gasPriceBid = 1;
    uint256 public nativeTokenTotalFee;

    function setUp() public {
        inbox = new ERC20InboxMock();
        nativeToken = ERC20(address(new ERC20PresetMinterPauser("X", "Y")));
        ERC20PresetMinterPauser(address(nativeToken)).mint(user, 1_000_000 ether);
        ERC20PresetMinterPauser(address(nativeToken)).mint(owner, 1_000_000 ether);
        inbox.setMockNativeToken(address(nativeToken));

        router = new L1GatewayRouter();
        MasterVault masterVaultImpl = new MasterVault();
        factory = new MasterVaultFactory();

        gateway = new L1OrbitYbbCustomGateway();
        gateway.initialize(l2Gateway, address(router), address(inbox), owner, address(factory));

        router.initialize(address(this), address(gateway), address(0), l2Router, address(inbox));

        factory.initialize(address(masterVaultImpl), address(this), IGatewayRouter(address(router)));

        nativeTokenTotalFee = maxGas * gasPriceBid;

        token = new TestERC20();
        vm.prank(user);
        token.mintAmount(DEPOSIT_AMOUNT);
        vm.deal(address(token), 100 ether);
        vm.deal(owner, 100 ether);
    }

    function test_outboundTransfer_depositsToVault() public {
        _registerToken();

        vm.prank(user);
        token.approve(address(gateway), DEPOSIT_AMOUNT);

        vm.prank(user);
        nativeToken.approve(address(gateway), nativeTokenTotalFee);

        vm.prank(address(router));
        gateway.outboundTransfer(
            address(token), user, DEPOSIT_AMOUNT, maxGas, gasPriceBid, _buildRouterEncodedData("")
        );

        assertEq(token.balanceOf(user), 0, "User should have no tokens left");

        address vaultAddr = factory.calculateVaultAddress(address(token));
        assertTrue(vaultAddr.code.length > 0, "Vault should be deployed");
        assertEq(token.balanceOf(vaultAddr), DEPOSIT_AMOUNT, "Vault should hold deposited tokens");

        uint256 expectedShares = DEPOSIT_AMOUNT * (10 ** EXTRA_DECIMALS);
        MasterVault vault = MasterVault(vaultAddr);
        assertEq(
            vault.balanceOf(address(gateway)), expectedShares, "Gateway should hold vault shares"
        );
    }

    function test_registerTokenToL2() public {
        address l2Token = makeAddr("l2Token");

        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);
        vm.prank(address(token));
        nativeToken.approve(address(gateway), nativeTokenTotalFee);

        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        L1OrbitCustomGateway(address(gateway))
            .registerTokenToL2(l2Token, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee);

        assertEq(gateway.l1ToL2Token(address(token)), l2Token, "Invalid L2 token");
    }

    function test_forceRegisterTokenToL2() public {
        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = makeAddr("l1Token1");
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = makeAddr("l2Token1");

        vm.prank(owner);
        nativeToken.approve(address(gateway), nativeTokenTotalFee);

        vm.prank(owner);
        L1OrbitCustomGateway(address(gateway))
            .forceRegisterTokenToL2(
                l1Tokens, l2Tokens, maxGas, gasPriceBid, maxSubmissionCost, nativeTokenTotalFee
            );

        assertEq(gateway.l1ToL2Token(l1Tokens[0]), l2Tokens[0], "Invalid L2 token");
    }

    function _registerToken() internal {
        address l2Token = makeAddr("tokenL2Address");

        ERC20PresetMinterPauser(address(nativeToken)).mint(address(token), nativeTokenTotalFee);
        vm.prank(address(token));
        nativeToken.approve(address(gateway), nativeTokenTotalFee);

        vm.mockCall(
            address(token), abi.encodeWithSignature("isArbitrumEnabled()"), abi.encode(uint8(0xb1))
        );
        vm.prank(address(token));
        L1OrbitCustomGateway(address(gateway))
            .registerTokenToL2(
                l2Token,
                maxGas,
                gasPriceBid,
                maxSubmissionCost,
                creditBackAddress,
                nativeTokenTotalFee
            );
    }

    function _buildRouterEncodedData(bytes memory callHookData)
        internal
        view
        returns (bytes memory)
    {
        bytes memory userEncodedData =
            abi.encode(maxSubmissionCost, callHookData, nativeTokenTotalFee);
        return abi.encode(user, userEncodedData);
    }
}
