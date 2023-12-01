// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {L1AtomicTokenBridgeCreator} from
    "contracts/tokenbridge/ethereum/L1AtomicTokenBridgeCreator.sol";
import {L1TokenBridgeRetryableSender} from
    "contracts/tokenbridge/ethereum/L1TokenBridgeRetryableSender.sol";
import {TestUtil} from "./util/TestUtil.sol";
import {AddressAliasHelper} from "contracts/tokenbridge/libraries/AddressAliasHelper.sol";

contract L1AtomicTokenBridgeCreatorTest is Test {
    L1AtomicTokenBridgeCreator public l1Creator;
    address public deployer = makeAddr("deployer");

    function setUp() public {
        L1AtomicTokenBridgeCreator l1Creator = new L1AtomicTokenBridgeCreator();
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public {
        L1AtomicTokenBridgeCreator _creator = L1AtomicTokenBridgeCreator(
            TestUtil.deployProxy(address(new L1AtomicTokenBridgeCreator()))
        );
        L1TokenBridgeRetryableSender _sender = L1TokenBridgeRetryableSender(
            TestUtil.deployProxy(address(new L1TokenBridgeRetryableSender()))
        );

        vm.prank(deployer);
        _creator.initialize(_sender);

        assertEq(_creator.owner(), deployer, "Wrong owner");
        assertEq(address(_creator.retryableSender()), address(_sender), "Wrong sender");
        assertEq(uint256(vm.load(address(_sender), 0)), 1, "Wrong init state");

        address exepectedL2Factory = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xd6),
                            bytes1(0x94),
                            AddressAliasHelper.applyL1ToL2Alias(address(_creator)),
                            bytes1(0x80)
                        )
                    )
                )
            )
        );
        assertEq(
            address(_creator.canonicalL2FactoryAddress()),
            exepectedL2Factory,
            "Wrong canonicalL2FactoryAddress"
        );
    }

    function test_initialize_revert_AlreadyInit() public {
        L1AtomicTokenBridgeCreator _creator = L1AtomicTokenBridgeCreator(
            TestUtil.deployProxy(address(new L1AtomicTokenBridgeCreator()))
        );
        L1TokenBridgeRetryableSender _sender = new L1TokenBridgeRetryableSender();
        _creator.initialize(_sender);

        vm.expectRevert("Initializable: contract is already initialized");
        _creator.initialize(_sender);
    }

    function test_initialize_revert_CantInitLogic() public {
        L1AtomicTokenBridgeCreator _creator = new L1AtomicTokenBridgeCreator();

        vm.expectRevert("Initializable: contract is already initialized");
        _creator.initialize(L1TokenBridgeRetryableSender(address(100)));
    }
}
