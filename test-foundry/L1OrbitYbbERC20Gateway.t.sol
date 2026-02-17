// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {
    L1OrbitYbbERC20Gateway
} from "contracts/tokenbridge/ethereum/gateway/L1OrbitYbbERC20Gateway.sol";
import {L1GatewayRouter} from "contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import {MasterVault} from "contracts/tokenbridge/libraries/vault/MasterVault.sol";
import {MasterVaultFactory} from "contracts/tokenbridge/libraries/vault/MasterVaultFactory.sol";
import {ClonableBeaconProxy} from "contracts/tokenbridge/libraries/ClonableBeaconProxy.sol";
import {IGatewayRouter} from "contracts/tokenbridge/libraries/gateway/IGatewayRouter.sol";
import {ITokenGateway} from "contracts/tokenbridge/libraries/gateway/ITokenGateway.sol";
import {TestERC20} from "contracts/tokenbridge/test/TestERC20.sol";
import {ERC20InboxMock} from "contracts/tokenbridge/test/InboxMock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    ERC20PresetMinterPauser
} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract L1OrbitYbbERC20GatewayTest is Test {
    L1OrbitYbbERC20Gateway public gateway;
    L1GatewayRouter public router;
    MasterVaultFactory public factory;
    TestERC20 public token;
    ERC20InboxMock public inbox;
    ERC20 public nativeToken;

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
    uint256 public nativeTokenTotalFee;

    function setUp() public {
        inbox = new ERC20InboxMock();
        nativeToken = ERC20(address(new ERC20PresetMinterPauser("X", "Y")));
        ERC20PresetMinterPauser(address(nativeToken)).mint(user, 1_000_000 ether);
        inbox.setMockNativeToken(address(nativeToken));

        router = new L1GatewayRouter();
        MasterVault masterVaultImpl = new MasterVault();
        factory = new MasterVaultFactory();

        gateway = new L1OrbitYbbERC20Gateway();
        gateway.initialize(
            l2Gateway,
            address(router),
            address(inbox),
            keccak256(type(ClonableBeaconProxy).creationCode),
            l2BeaconProxyFactory,
            address(factory)
        );

        router.initialize(address(this), address(gateway), address(0), l2Router, address(inbox));

        factory.initialize(address(masterVaultImpl), address(this), IGatewayRouter(address(router)));

        nativeTokenTotalFee = maxGas * gasPriceBid;

        token = new TestERC20();
        vm.prank(user);
        token.mintAmount(DEPOSIT_AMOUNT);
    }

    function test_outboundTransfer_depositsToVault() public {
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

    function test_outboundTransferCustomRefund_revert_NoValue() public {
        vm.deal(address(router), 100 ether);
        vm.prank(address(router));
        vm.expectRevert("NO_VALUE");
        gateway.outboundTransferCustomRefund{value: 1 ether}(
            address(token), user, user, 100, maxGas, gasPriceBid, ""
        );
    }

    function test_outboundTransfer_revert_NotAllowedToBridgeFeeToken() public {
        vm.prank(address(router));
        vm.expectRevert("NOT_ALLOWED_TO_BRIDGE_FEE_TOKEN");
        gateway.outboundTransfer(address(nativeToken), user, 100, maxGas, gasPriceBid, "");
    }

    function test_getOutboundCalldata_reportsVaultDecimals() public {
        _depositToCreateVault();

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

    function _depositToCreateVault() internal {
        vm.prank(user);
        token.approve(address(gateway), DEPOSIT_AMOUNT);
        vm.prank(user);
        nativeToken.approve(address(gateway), nativeTokenTotalFee);
        vm.prank(address(router));
        gateway.outboundTransfer(
            address(token), user, DEPOSIT_AMOUNT, maxGas, gasPriceBid, _buildRouterEncodedData("")
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
