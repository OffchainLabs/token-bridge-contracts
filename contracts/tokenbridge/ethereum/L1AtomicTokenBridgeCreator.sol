// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {L1GatewayRouter} from "./gateway/L1GatewayRouter.sol";
import {L1ERC20Gateway} from "./gateway/L1ERC20Gateway.sol";
import {L1CustomGateway} from "./gateway/L1CustomGateway.sol";
import {L1WethGateway} from "./gateway/L1WethGateway.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {L2AtomicTokenBridgeFactory, OrbitSalts} from "../arbitrum/L2AtomicTokenBridgeFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IInbox, IBridge, IOwnable} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {AddressAliasHelper} from "../libraries/AddressAliasHelper.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {BeaconProxyFactory, ClonableBeaconProxy} from "../libraries/ClonableBeaconProxy.sol";

/**
 * @title Layer1 token bridge creator
 * @notice This contract is used to deploy token bridge on custom L2 chains.
 * @dev Throughout the contract terms L1 and L2 are used, but those can be considered as base (N) chain and child (N+1) chain
 */
contract L1AtomicTokenBridgeCreator is Ownable {
    error L1AtomicTokenBridgeCreator_OnlyRollupOwner();
    error L1AtomicTokenBridgeCreator_InvalidRouterAddr();

    event OrbitTokenBridgeCreated(
        address router, address standardGateway, address customGateway, address wethGateway, address proxyAdmin
    );
    event OrbitTokenBridgeTemplatesUpdated();
    event NonCanonicalRouterSet(address indexed inbox, address indexed router);

    // non-canonical router registry
    mapping(address => address) public inboxToNonCanonicalRouter;

    // L1 logic contracts shared by all token bridges
    L1GatewayRouter public routerTemplate;
    L1ERC20Gateway public standardGatewayTemplate;
    L1CustomGateway public customGatewayTemplate;
    L1WethGateway public wethGatewayTemplate;

    // L2 contracts deployed to L1 as bytecode placeholders
    address public l2TokenBridgeFactoryTemplate;
    address public l2RouterTemplate;
    address public l2StandardGatewayTemplate;
    address public l2CustomGatewayTemplate;
    address public l2WethGatewayTemplate;
    address public l2WethTemplate;

    // WETH address on L1
    address public l1Weth;

    // immutable canonical addresses for L2 contracts
    // other canonical addresses (dependent on L2 template implementations) can be fetched through `computeExpectedL2***Address` functions
    address public immutable expectedL2FactoryAddress;
    address public immutable expectedL2ProxyAdminAddress;
    address public immutable expectedL2BeaconProxyFactoryAddress;

    constructor() Ownable() {
        expectedL2FactoryAddress = _computeAddress(AddressAliasHelper.applyL1ToL2Alias(address(this)), 0);

        expectedL2ProxyAdminAddress = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_PROXY_ADMIN), keccak256(type(ProxyAdmin).creationCode), expectedL2FactoryAddress
        );

        expectedL2BeaconProxyFactoryAddress = Create2.computeAddress(
            _getL2Salt(OrbitSalts.BEACON_PROXY_FACTORY),
            keccak256(type(BeaconProxyFactory).creationCode),
            expectedL2FactoryAddress
        );
    }

    /**
     * @notice Set addresses of L1 logic contracts and L2 contracts which are deployed on L1.
     * @dev L2 contracts are deployed to L1 as bytecode placeholders - that bytecode will be part of retryable
     *      payload used to deploy contracts on L2 side.
     */
    function setTemplates(
        L1GatewayRouter _router,
        L1ERC20Gateway _standardGateway,
        L1CustomGateway _customGateway,
        L1WethGateway _wethGatewayTemplate,
        address _l2TokenBridgeFactoryTemplate,
        address _l2RouterTemplate,
        address _l2StandardGatewayTemplate,
        address _l2CustomGatewayTemplate,
        address _l2WethGatewayTemplate,
        address _l2WethTemplate,
        address _l1Weth
    ) external onlyOwner {
        routerTemplate = _router;
        standardGatewayTemplate = _standardGateway;
        customGatewayTemplate = _customGateway;
        wethGatewayTemplate = _wethGatewayTemplate;

        l2TokenBridgeFactoryTemplate = _l2TokenBridgeFactoryTemplate;
        l2RouterTemplate = _l2RouterTemplate;
        l2StandardGatewayTemplate = _l2StandardGatewayTemplate;
        l2CustomGatewayTemplate = _l2CustomGatewayTemplate;
        l2WethGatewayTemplate = _l2WethGatewayTemplate;
        l2WethTemplate = _l2WethTemplate;

        l1Weth = _l1Weth;

        emit OrbitTokenBridgeTemplatesUpdated();
    }

    /**
     * @notice Deploy and initialize token bridge, both L1 and L2 sides, as part of a single TX.
     * @dev This is a single entrypoint of L1 token bridge creator. Function deploys L1 side of token bridge and then uses
     *      2 retryable tickets  to deploy L2 side. 1st one deploy L2 factory and 2nd calls function that deploys and inits
     *      all the rest of the contracts. L2 chain is determined by `inbox` parameter.
     */
    function createTokenBridge(
        address inbox,
        uint256 maxSubmissionCostForFactory,
        uint256 maxGasForFactory,
        uint256 maxSubmissionCostForContracts,
        uint256 maxGasForContracts,
        uint256 gasPriceBid
    ) external payable {
        address owner = _getRollupOwner(inbox);
        (address router, address standardGateway, address customGateway, address wethGateway) =
            _deployL1Contracts(inbox, owner);

        /// deploy factory and then L2 contracts through L2 factory, using 2 retryables calls
        _deployL2Factory(inbox, maxSubmissionCostForFactory, maxGasForFactory, gasPriceBid);
        _deployL2Contracts(
            router,
            standardGateway,
            customGateway,
            wethGateway,
            inbox,
            maxSubmissionCostForContracts,
            maxGasForContracts,
            gasPriceBid
        );
    }

    /**
     * @notice Rollup owner can override canonical router address by registering other non-canonical router.
     */
    function setNonCanonicalRouter(address inbox, address nonCanonicalRouter) external {
        if (msg.sender != _getRollupOwner(inbox)) revert L1AtomicTokenBridgeCreator_OnlyRollupOwner();
        if (nonCanonicalRouter == computeExpectedL1RouterAddress(inbox)) {
            revert L1AtomicTokenBridgeCreator_InvalidRouterAddr();
        }

        inboxToNonCanonicalRouter[inbox] = nonCanonicalRouter;
        emit NonCanonicalRouterSet(inbox, nonCanonicalRouter);
    }

    function getRouter(address inbox) public view returns (address) {
        address nonCanonicalRouter = inboxToNonCanonicalRouter[inbox];

        if (nonCanonicalRouter != address(0)) {
            return nonCanonicalRouter;
        }

        return computeExpectedL1RouterAddress(inbox);
    }

    function _deployL1Contracts(address inbox, address owner)
        internal
        returns (address router, address standardGateway, address customGateway, address wethGateway)
    {
        address proxyAdmin = address(new ProxyAdmin{ salt: _getL1Salt(OrbitSalts.L1_PROXY_ADMIN, inbox) }());

        // deploy router
        router = address(
            new TransparentUpgradeableProxy{ salt: _getL1Salt(OrbitSalts.L1_ROUTER, inbox) }(
                address(routerTemplate),
                proxyAdmin,
                bytes("")
            )
        );

        // deploy and init gateways
        standardGateway = _deployL1StandardGateway(proxyAdmin, router, inbox);
        customGateway = _deployL1CustomGateway(proxyAdmin, router, inbox, owner);
        wethGateway = _deployL1WethGateway(proxyAdmin, router, inbox);

        // init router
        L1GatewayRouter(router).initialize(
            owner, address(standardGateway), address(0), computeExpectedL2RouterAddress(), inbox
        );

        // transfer ownership to owner
        ProxyAdmin(proxyAdmin).transferOwnership(owner);

        // emit it
        emit OrbitTokenBridgeCreated(router, standardGateway, customGateway, wethGateway, proxyAdmin);
    }

    function _deployL1StandardGateway(address proxyAdmin, address router, address inbox) internal returns (address) {
        L1ERC20Gateway standardGateway = L1ERC20Gateway(
            address(
                new TransparentUpgradeableProxy{
                    salt: _getL1Salt(OrbitSalts.L1_STANDARD_GATEWAY, inbox)
                }(address(standardGatewayTemplate), proxyAdmin, bytes(""))
            )
        );

        standardGateway.initialize(
            computeExpectedL2StandardGatewayAddress(),
            router,
            inbox,
            keccak256(type(ClonableBeaconProxy).creationCode),
            expectedL2BeaconProxyFactoryAddress
        );

        return address(standardGateway);
    }

    function _deployL1CustomGateway(address proxyAdmin, address router, address inbox, address owner)
        internal
        returns (address)
    {
        L1CustomGateway customGateway = L1CustomGateway(
            address(
                new TransparentUpgradeableProxy{
                    salt: _getL1Salt(OrbitSalts.L1_CUSTOM_GATEWAY, inbox)
                }(address(customGatewayTemplate), proxyAdmin, bytes(""))
            )
        );

        customGateway.initialize(computeExpectedL2CustomGatewayAddress(), router, inbox, owner);

        return address(customGateway);
    }

    function _deployL1WethGateway(address proxyAdmin, address router, address inbox) internal returns (address) {
        L1WethGateway wethGateway = L1WethGateway(
            payable(
                address(
                    new TransparentUpgradeableProxy{
                        salt: _getL1Salt(OrbitSalts.L1_WETH_GATEWAY, inbox)
                    }(address(wethGatewayTemplate), proxyAdmin, bytes(""))
                )
            )
        );

        wethGateway.initialize(
            computeExpectedL2WethGatewayAddress(), router, inbox, l1Weth, computeExpectedL2WethAddress()
        );

        return address(wethGateway);
    }

    function _deployL2Factory(address inbox, uint256 maxSubmissionCost, uint256 maxGas, uint256 gasPriceBid) internal {
        // encode L2 factory bytecode
        bytes memory deploymentData = _creationCodeFor(l2TokenBridgeFactoryTemplate.code);

        uint256 value = maxSubmissionCost + maxGas * gasPriceBid;
        IInbox(inbox).createRetryableTicket{value: value}(
            address(0), 0, maxSubmissionCost, msg.sender, msg.sender, maxGas, gasPriceBid, deploymentData
        );
    }

    function _deployL2Contracts(
        address l1Router,
        address l1StandardGateway,
        address l1CustomGateway,
        address l1WethGateway,
        address inbox,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) internal {
        address l2ProxyAdminOwner = _getRollupOwner(inbox);
        bytes memory data = abi.encodeWithSelector(
            L2AtomicTokenBridgeFactory.deployL2Contracts.selector,
            _creationCodeFor(l2RouterTemplate.code),
            _creationCodeFor(l2StandardGatewayTemplate.code),
            _creationCodeFor(l2CustomGatewayTemplate.code),
            _creationCodeFor(l2WethGatewayTemplate.code),
            _creationCodeFor(l2WethTemplate.code),
            l1Router,
            l1StandardGateway,
            l1CustomGateway,
            l1WethGateway,
            l1Weth,
            computeExpectedL2StandardGatewayAddress(),
            l2ProxyAdminOwner
        );

        IInbox(inbox).createRetryableTicket{value: maxSubmissionCost + maxGas * gasPriceBid}(
            expectedL2FactoryAddress, 0, maxSubmissionCost, msg.sender, msg.sender, maxGas, gasPriceBid, data
        );
    }

    function computeExpectedL1RouterAddress(address inbox) public view returns (address) {
        address expectedL1ProxyAdminAddress = Create2.computeAddress(
            _getL1Salt(OrbitSalts.L1_PROXY_ADMIN, inbox), keccak256(type(ProxyAdmin).creationCode), address(this)
        );

        return Create2.computeAddress(
            _getL1Salt(OrbitSalts.L1_ROUTER, inbox),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(routerTemplate, expectedL1ProxyAdminAddress, bytes(""))
                )
            ),
            address(this)
        );
    }

    function computeExpectedL2RouterAddress() public view returns (address) {
        address expectedL2RouterLogic = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_ROUTER_LOGIC),
            keccak256(_creationCodeFor(l2RouterTemplate.code)),
            expectedL2FactoryAddress
        );

        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_ROUTER),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(expectedL2RouterLogic, expectedL2ProxyAdminAddress, bytes(""))
                )
            ),
            expectedL2FactoryAddress
        );
    }

    function computeExpectedL2StandardGatewayAddress() public view returns (address) {
        address expectedL2StandardGatewayLogic = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY_LOGIC),
            keccak256(_creationCodeFor(l2StandardGatewayTemplate.code)),
            expectedL2FactoryAddress
        );
        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(expectedL2StandardGatewayLogic, expectedL2ProxyAdminAddress, bytes(""))
                )
            ),
            expectedL2FactoryAddress
        );
    }

    function computeExpectedL2CustomGatewayAddress() public view returns (address) {
        address expectedL2CustomGatewayLogic = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY_LOGIC),
            keccak256(_creationCodeFor(l2CustomGatewayTemplate.code)),
            expectedL2FactoryAddress
        );

        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(expectedL2CustomGatewayLogic, expectedL2ProxyAdminAddress, bytes(""))
                )
            ),
            expectedL2FactoryAddress
        );
    }

    function computeExpectedL2WethGatewayAddress() public view returns (address) {
        address expectedL2WethGatewayLogic = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_WETH_GATEWAY_LOGIC),
            keccak256(_creationCodeFor(l2WethGatewayTemplate.code)),
            expectedL2FactoryAddress
        );

        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_WETH_GATEWAY),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(expectedL2WethGatewayLogic, expectedL2ProxyAdminAddress, bytes(""))
                )
            ),
            expectedL2FactoryAddress
        );
    }

    function computeExpectedL2WethAddress() public view returns (address) {
        address expectedL2WethLogic = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_WETH_LOGIC),
            keccak256(_creationCodeFor(l2WethTemplate.code)),
            expectedL2FactoryAddress
        );

        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_WETH),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(expectedL2WethLogic, expectedL2ProxyAdminAddress, bytes(""))
                )
            ),
            expectedL2FactoryAddress
        );
    }

    /**
     * @notice Generate a creation code that results on a contract with `code` as bytecode.
     *         Source - https://github.com/0xsequence/sstore2/blob/master/contracts/utils/Bytecode.sol
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

        return abi.encodePacked(hex"63", uint32(code.length), hex"80600E6000396000F3", code);
    }

    /**
     * @notice Compute address of contract deployed using CREATE opcode
     * @return computed address
     */
    function _computeAddress(address _origin, uint256 _nonce) public pure returns (address) {
        bytes memory data;
        if (_nonce == 0x00) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80));
        } else if (_nonce <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce));
        } else if (_nonce <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce));
        } else if (_nonce <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce));
        } else if (_nonce <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce));
        }
        return address(uint160(uint256(keccak256(data))));
    }

    function _getRollupOwner(address inbox) internal view returns (address) {
        return IInbox(inbox).bridge().rollup().owner();
    }

    function _getL1Salt(bytes32 prefix, address inbox) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(prefix, inbox));
    }

    function _getL2Salt(bytes32 prefix) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(prefix, AddressAliasHelper.applyL1ToL2Alias(address(this))));
    }
}
