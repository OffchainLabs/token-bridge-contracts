// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { L1GatewayRouter } from "./gateway/L1GatewayRouter.sol";
import { L1ERC20Gateway } from "./gateway/L1ERC20Gateway.sol";
import { L1CustomGateway } from "./gateway/L1CustomGateway.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { L2AtomicTokenBridgeFactory } from "../arbitrum/L2AtomicTokenBridgeFactory.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IInbox } from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import { AddressAliasHelper } from "../libraries/AddressAliasHelper.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { BeaconProxyFactory, ClonableBeaconProxy } from "../libraries/ClonableBeaconProxy.sol";

contract L1AtomicTokenBridgeCreator is Ownable {
    event OrbitTokenBridgeCreated(
        address router,
        address standardGateway,
        address customGateway,
        address proxyAdmin
    );
    event OrbitTokenBridgeTemplatesUpdated();

    L1GatewayRouter public routerTemplate;
    L1ERC20Gateway public standardGatewayTemplate;
    L1CustomGateway public customGatewayTemplate;

    address public l2TokenBridgeFactoryOnL1;
    address public l2RouterOnL1;
    address public l2StandardGatewayOnL1;
    address public l2CustomGatewayOnL1;

    address public immutable expectedL2FactoryAddress;
    address public immutable expectedL2ProxyAdminAddress;
    address public immutable expectedL2BeaconProxyFactoryAddress;

    constructor() Ownable() {
        expectedL2FactoryAddress = computeAddress(
            AddressAliasHelper.applyL1ToL2Alias(address(this)),
            0
        );

        expectedL2ProxyAdminAddress = Create2.computeAddress(
            keccak256(bytes("OrbitL2ProxyAdmin")),
            keccak256(type(ProxyAdmin).creationCode),
            expectedL2FactoryAddress
        );

        expectedL2BeaconProxyFactoryAddress = Create2.computeAddress(
            keccak256(bytes("OrbitBeaconProxyFactory")),
            keccak256(type(BeaconProxyFactory).creationCode),
            expectedL2FactoryAddress
        );
    }

    function setTemplates(
        L1GatewayRouter _router,
        L1ERC20Gateway _standardGateway,
        L1CustomGateway _customGateway,
        address _l2TokenBridgeFactoryOnL1,
        address _l2RouterOnL1,
        address _l2StandardGatewayOnL1,
        address _l2CustomGatewayOnL1
    ) external onlyOwner {
        routerTemplate = _router;
        standardGatewayTemplate = _standardGateway;
        customGatewayTemplate = _customGateway;

        l2TokenBridgeFactoryOnL1 = _l2TokenBridgeFactoryOnL1;
        l2RouterOnL1 = _l2RouterOnL1;
        l2StandardGatewayOnL1 = _l2StandardGatewayOnL1;
        l2CustomGatewayOnL1 = _l2CustomGatewayOnL1;

        emit OrbitTokenBridgeTemplatesUpdated();
    }

    function createTokenBridge(
        address inbox,
        address owner,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) external payable {
        address proxyAdmin = address(new ProxyAdmin());

        L1GatewayRouter router = L1GatewayRouter(
            address(new TransparentUpgradeableProxy(address(routerTemplate), proxyAdmin, bytes("")))
        );
        L1ERC20Gateway standardGateway = _deployL1StandardGateway(
            proxyAdmin,
            address(router),
            inbox
        );
        L1CustomGateway customGateway = _deployL1CustomGateway(
            proxyAdmin,
            address(router),
            inbox,
            owner
        );

        // init router
        router.initialize(
            owner,
            address(standardGateway),
            address(0),
            _computeExpectedL2RouterAddress(),
            inbox
        );

        emit OrbitTokenBridgeCreated(
            address(router),
            address(standardGateway),
            address(customGateway),
            proxyAdmin
        );

        _deployL2Factory(inbox, maxSubmissionCost, maxGas, gasPriceBid);

        /// deploy L2 contracts through L2 factory
        _deployL2Router(address(router), inbox, maxSubmissionCost, maxGas, gasPriceBid);
        _deployL2StandardGateway(
            address(standardGateway),
            inbox,
            maxSubmissionCost,
            maxGas,
            gasPriceBid
        );
        _deployL2CustomGateway(
            address(customGateway),
            inbox,
            maxSubmissionCost,
            maxGas,
            gasPriceBid
        );
    }

    function _deployL1StandardGateway(
        address proxyAdmin,
        address router,
        address inbox
    ) internal returns (L1ERC20Gateway) {
        L1ERC20Gateway standardGateway = L1ERC20Gateway(
            address(
                new TransparentUpgradeableProxy(
                    address(standardGatewayTemplate),
                    proxyAdmin,
                    bytes("")
                )
            )
        );

        standardGateway.initialize(
            _computeExpectedL2StandardGatewayAddress(),
            router,
            inbox,
            keccak256(type(ClonableBeaconProxy).creationCode),
            expectedL2BeaconProxyFactoryAddress
        );

        return standardGateway;
    }

    function _deployL1CustomGateway(
        address proxyAdmin,
        address router,
        address inbox,
        address owner
    ) internal returns (L1CustomGateway) {
        L1CustomGateway customGateway = L1CustomGateway(
            address(
                new TransparentUpgradeableProxy(
                    address(customGatewayTemplate),
                    proxyAdmin,
                    bytes("")
                )
            )
        );

        customGateway.initialize(
            _computeExpectedL2CustomGatewayAddress(),
            address(router),
            inbox,
            owner
        );

        return customGateway;
    }

    function _deployL2Factory(
        address inbox,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) internal returns (uint256) {
        // encode L2 factory bytecode
        bytes memory deploymentData = _creationCodeFor(l2TokenBridgeFactoryOnL1.code);

        uint256 value = maxSubmissionCost + maxGas * gasPriceBid;
        uint256 ticketID = IInbox(inbox).createRetryableTicket{ value: value }(
            address(0),
            0,
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            deploymentData
        );

        return ticketID;
    }

    function _deployL2Router(
        address l1Router,
        address inbox,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) internal returns (uint256) {
        // get L2 factory bytecode
        bytes memory creationCode = _creationCodeFor(l2RouterOnL1.code);

        /// send retryable
        bytes memory data = abi.encodeWithSelector(
            L2AtomicTokenBridgeFactory.deployRouter.selector,
            creationCode,
            l1Router,
            _computeExpectedL2StandardGatewayAddress()
        );
        uint256 ticketID = IInbox(inbox).createRetryableTicket{
            value: maxSubmissionCost + maxGas * gasPriceBid
        }(
            expectedL2FactoryAddress,
            0,
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            data
        );
        return ticketID;
    }

    function _deployL2StandardGateway(
        address l1StandardGateway,
        address inbox,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) internal returns (uint256) {
        // get L2 standard gateway bytecode
        bytes memory creationCode = _creationCodeFor(l2StandardGatewayOnL1.code);

        /// send retryable
        bytes memory data = abi.encodeWithSelector(
            L2AtomicTokenBridgeFactory.deployStandardGateway.selector,
            creationCode,
            l1StandardGateway
        );
        uint256 value = maxSubmissionCost + maxGas * gasPriceBid;
        uint256 ticketID = IInbox(inbox).createRetryableTicket{ value: value }(
            expectedL2FactoryAddress,
            0,
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            data
        );
        return ticketID;
    }

    function _deployL2CustomGateway(
        address l1CustomGateway,
        address inbox,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) internal returns (uint256) {
        // encode L2 custom gateway bytecode
        bytes memory creationCode = _creationCodeFor(l2CustomGatewayOnL1.code);

        /// send retryable
        bytes memory data = abi.encodeWithSelector(
            L2AtomicTokenBridgeFactory.deployCustomGateway.selector,
            creationCode,
            l1CustomGateway
        );
        uint256 value = maxSubmissionCost + maxGas * gasPriceBid;
        uint256 ticketID = IInbox(inbox).createRetryableTicket{ value: value }(
            expectedL2FactoryAddress,
            0,
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            data
        );
        return ticketID;
    }

    /**
     * @notice Generate a creation code that results on a contract with `_code` as bytecode
     * @param code The returning value of the resulting `creationCode`
     * @return creationCode (constructor) for new contract
     */
    function _creationCodeFor(bytes memory code) internal pure returns (bytes memory) {
        /*
            0x00    0x63         0x63XXXXXX  PUSH4 _code.length  size
            0x01    0x80         0x80        DUP1                size size
            0x02    0x60         0x600e      PUSH1 14            14 size size
            0x03    0x60         0x6000      PUSH1 00            0 14 size size
            0x04    0x39         0x39        CODECOPY            size
            0x05    0x60         0x6000      PUSH1 00            0 size
            0x06    0xf3         0xf3        RETURN
            <CODE>
        */

        return
            abi.encodePacked(hex"63", uint32(code.length), hex"80_60_0E_60_00_39_60_00_F3", code);
    }

    function computeAddress(address _origin, uint _nonce) public pure returns (address) {
        bytes memory data;
        if (_nonce == 0x00)
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80));
        else if (_nonce <= 0x7f)
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce));
        else if (_nonce <= 0xff)
            data = abi.encodePacked(
                bytes1(0xd7),
                bytes1(0x94),
                _origin,
                bytes1(0x81),
                uint8(_nonce)
            );
        else if (_nonce <= 0xffff)
            data = abi.encodePacked(
                bytes1(0xd8),
                bytes1(0x94),
                _origin,
                bytes1(0x82),
                uint16(_nonce)
            );
        else if (_nonce <= 0xffffff)
            data = abi.encodePacked(
                bytes1(0xd9),
                bytes1(0x94),
                _origin,
                bytes1(0x83),
                uint24(_nonce)
            );
        else
            data = abi.encodePacked(
                bytes1(0xda),
                bytes1(0x94),
                _origin,
                bytes1(0x84),
                uint32(_nonce)
            );
        return address(uint160(uint256(keccak256(data))));
    }

    function _computeExpectedL2RouterAddress() internal returns (address) {
        address expectedL2RouterLogic = Create2.computeAddress(
            keccak256(bytes("OrbitL2GatewayRouterLogic")),
            keccak256(_creationCodeFor(l2RouterOnL1.code)),
            expectedL2FactoryAddress
        );

        return
            Create2.computeAddress(
                keccak256(bytes("OrbitL2GatewayRouterProxy")),
                keccak256(
                    abi.encodePacked(
                        type(TransparentUpgradeableProxy).creationCode,
                        abi.encode(expectedL2RouterLogic, expectedL2ProxyAdminAddress, bytes(""))
                    )
                ),
                expectedL2FactoryAddress
            );
    }

    function _computeExpectedL2StandardGatewayAddress() internal view returns (address) {
        address expectedL2StandardGatewayLogic = Create2.computeAddress(
            keccak256(bytes("OrbitL2StandardGatewayLogic")),
            keccak256(_creationCodeFor(l2StandardGatewayOnL1.code)),
            expectedL2FactoryAddress
        );
        return
            Create2.computeAddress(
                keccak256(bytes("OrbitL2StandardGatewayProxy")),
                keccak256(
                    abi.encodePacked(
                        type(TransparentUpgradeableProxy).creationCode,
                        abi.encode(
                            expectedL2StandardGatewayLogic,
                            expectedL2ProxyAdminAddress,
                            bytes("")
                        )
                    )
                ),
                expectedL2FactoryAddress
            );
    }

    function _computeExpectedL2CustomGatewayAddress() internal view returns (address) {
        address expectedL2CustomGatewayLogic = Create2.computeAddress(
            keccak256(bytes("OrbitL2CustomGatewayLogic")),
            keccak256(_creationCodeFor(l2CustomGatewayOnL1.code)),
            expectedL2FactoryAddress
        );

        return
            Create2.computeAddress(
                keccak256(bytes("OrbitL2CustomGatewayProxy")),
                keccak256(
                    abi.encodePacked(
                        type(TransparentUpgradeableProxy).creationCode,
                        abi.encode(
                            expectedL2CustomGatewayLogic,
                            expectedL2ProxyAdminAddress,
                            bytes("")
                        )
                    )
                ),
                expectedL2FactoryAddress
            );
    }
}
