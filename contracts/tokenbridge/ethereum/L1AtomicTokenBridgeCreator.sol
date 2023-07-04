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
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) external payable {
        address proxyAdmin = address(new ProxyAdmin());

        L1GatewayRouter router = L1GatewayRouter(
            address(new TransparentUpgradeableProxy(address(routerTemplate), proxyAdmin, bytes("")))
        );
        L1ERC20Gateway standardGateway = L1ERC20Gateway(
            address(
                new TransparentUpgradeableProxy(
                    address(standardGatewayTemplate),
                    proxyAdmin,
                    bytes("")
                )
            )
        );
        L1CustomGateway customGateway = L1CustomGateway(
            address(
                new TransparentUpgradeableProxy(
                    address(customGatewayTemplate),
                    proxyAdmin,
                    bytes("")
                )
            )
        );

        emit OrbitTokenBridgeCreated(
            address(router),
            address(standardGateway),
            address(customGateway),
            proxyAdmin
        );

        _deployL2Factory(inbox, maxSubmissionCost, maxGas, gasPriceBid);

        /// deploy L2 contracts thorugh L2 factory
        address l2FactoryExpectedAddress = computeAddress(
            AddressAliasHelper.applyL1ToL2Alias(address(this)),
            0
        );
        _deployL2Router(
            address(router),
            l2FactoryExpectedAddress,
            inbox,
            maxSubmissionCost,
            maxGas,
            gasPriceBid
        );
        _deployL2StandardGateway(
            address(standardGateway),
            l2FactoryExpectedAddress,
            inbox,
            maxSubmissionCost,
            maxGas,
            gasPriceBid
        );
        _deployL2CustomGateway(
            address(customGateway),
            l2FactoryExpectedAddress,
            inbox,
            maxSubmissionCost,
            maxGas,
            gasPriceBid
        );

        //// init contracts
        // {
        //     /// dependencies - l2Router, l2StandardGateway, l2CustomGateway, cloneableProxyHash, l2BeaconProxyFactory, owner, inbox
        //     router.initialize(address(1), address(standardGateway), address(0), address(1), inbox);
        //     standardGateway.initialize(address(1), address(router), inbox, "abc", address(1));
        //     customGateway.initialize(address(1), address(router), inbox, address(1));
        // }
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
        address l2Factory,
        address inbox,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) internal returns (uint256) {
        // get L2 factory bytecode
        bytes memory creationCode = _creationCodeFor(l2RouterOnL1.code);

        /// send retryable
        address l2StandardGatewayExpectedAddress = _getExpectedL2StandardGatewayAddress(l2Factory);
        bytes memory data = abi.encodeWithSelector(
            L2AtomicTokenBridgeFactory.deployRouter.selector,
            creationCode,
            l1Router,
            l2StandardGatewayExpectedAddress
        );
        uint256 ticketID = IInbox(inbox).createRetryableTicket{
            value: maxSubmissionCost + maxGas * gasPriceBid
        }(l2Factory, 0, maxSubmissionCost, msg.sender, msg.sender, maxGas, gasPriceBid, data);
        return ticketID;
    }

    function _deployL2StandardGateway(
        address l1StandardGateway,
        address l2Factory,
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
            l2Factory,
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
        address l2Factory,
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
            l2Factory,
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

    function _getExpectedL2StandardGatewayAddress(
        address deployer
    ) internal view returns (address expectedL2StandardGatewayAddress) {
        address l2StandardGatewayLogicExpected = Create2.computeAddress(
            keccak256(bytes("OrbitL2StandardGatewayLogic")),
            keccak256(_creationCodeFor(l2StandardGatewayOnL1.code)),
            deployer
        );

        address proxyAdminExpected = Create2.computeAddress(
            keccak256(bytes("OrbitL2ProxyAdmin")),
            keccak256(type(ProxyAdmin).creationCode),
            deployer
        );

        bytes memory tupCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(l2StandardGatewayLogicExpected, proxyAdminExpected, bytes(""))
        );

        expectedL2StandardGatewayAddress = Create2.computeAddress(
            keccak256(bytes("OrbitL2StandardGatewayProxy")),
            keccak256(tupCode),
            deployer
        );
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
}
