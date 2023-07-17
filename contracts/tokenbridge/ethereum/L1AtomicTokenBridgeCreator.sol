// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {
    L1TokenBridgeRetryableSender,
    L1Addresses,
    RetryableParams,
    L2TemplateAddresses
} from "./L1TokenBridgeRetryableSender.sol";
import {L1GatewayRouter} from "./gateway/L1GatewayRouter.sol";
import {L1ERC20Gateway} from "./gateway/L1ERC20Gateway.sol";
import {L1CustomGateway} from "./gateway/L1CustomGateway.sol";
import {L1WethGateway} from "./gateway/L1WethGateway.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    L2AtomicTokenBridgeFactory,
    CanonicalAddressSeed,
    OrbitSalts,
    L2RuntimeCode,
    ProxyAdmin
} from "../arbitrum/L2AtomicTokenBridgeFactory.sol";
import {IInbox, IBridge, IOwnable} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {AddressAliasHelper} from "../libraries/AddressAliasHelper.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {BeaconProxyFactory, ClonableBeaconProxy} from "../libraries/ClonableBeaconProxy.sol";
import {Initializable, OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title Layer1 token bridge creator
 * @notice This contract is used to deploy token bridge on custom L2 chains.
 * @dev Throughout the contract terms L1 and L2 are used, but those can be considered as base (N) chain and child (N+1) chain
 */
contract L1AtomicTokenBridgeCreator is Initializable, OwnableUpgradeable {
    error L1AtomicTokenBridgeCreator_OnlyRollupOwner();
    error L1AtomicTokenBridgeCreator_InvalidRouterAddr();
    error L1AtomicTokenBridgeCreator_TemplatesNotSet();

    event OrbitTokenBridgeCreated(
        address indexed inbox,
        address indexed owner,
        address router,
        address standardGateway,
        address customGateway,
        address wethGateway,
        address proxyAdmin
    );
    event OrbitTokenBridgeTemplatesUpdated();
    event NonCanonicalRouterSet(address indexed inbox, address indexed router);

    // non-canonical router registry
    mapping(address => address) public inboxToNonCanonicalRouter;

    // Hard-code gas to make sure gas limit is big enough for L2 factory deployment to succeed.
    // If retryable would've reverted due to too low gas limit, nonce 0 would be burned and
    // canonical address for L2 factory would've been unobtainable
    uint256 public gasLimitForL2FactoryDeployment;

    // contract which creates retryables for deploying L2 side of token bridge
    L1TokenBridgeRetryableSender public retryableSender;

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
    // other canonical addresses (dependent on L2 template implementations) can be fetched through `getCanonicalL2***Address` functions
    address public canonicalL2FactoryAddress;
    address public canonicalL2ProxyAdminAddress;
    address public canonicalL2BeaconProxyFactoryAddress;

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();

        // deploy retryableSender only once - its address will be part of salt for L2 contracts
        if (address(retryableSender) == address(0)) {
            retryableSender = L1TokenBridgeRetryableSender(
                address(
                    new TransparentUpgradeableProxy(
                        address(new L1TokenBridgeRetryableSender()),
                        msg.sender,
                        bytes("")
                    )
                )
            );
            retryableSender.initialize();
        }

        canonicalL2FactoryAddress = _computeAddress(AddressAliasHelper.applyL1ToL2Alias(address(this)), 0);
        canonicalL2ProxyAdminAddress = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_PROXY_ADMIN), keccak256(type(ProxyAdmin).creationCode), canonicalL2FactoryAddress
        );
        canonicalL2BeaconProxyFactoryAddress = Create2.computeAddress(
            _getL2Salt(OrbitSalts.BEACON_PROXY_FACTORY),
            keccak256(type(BeaconProxyFactory).creationCode),
            canonicalL2FactoryAddress
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
        address _l1Weth,
        uint256 _gasLimitForL2FactoryDeployment
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

        gasLimitForL2FactoryDeployment = _gasLimitForL2FactoryDeployment;

        emit OrbitTokenBridgeTemplatesUpdated();
    }

    /**
     * @notice Deploy and initialize token bridge, both L1 and L2 sides, as part of a single TX.
     * @dev This is a single entrypoint of L1 token bridge creator. Function deploys L1 side of token bridge and then uses
     *      2 retryable tickets to deploy L2 side. 1st retryable deploys L2 factory. And then 'retryable sender' contract
     *      is called to issue 2nd retryable which deploys and inits the rest of the contracts. L2 chain is determined
     *      by `inbox` parameter.
     *
     *      Token bridge can be deployed only once for certain inbox. Any further calls to `createTokenBridge` will revert
     *      because L1 salts are already used at that point and L1 contracts are already deployed at canonical addresses
     *      for that inbox.
     */
    function createTokenBridge(address inbox, uint256 maxGasForContracts, uint256 gasPriceBid) external payable {
        if (address(routerTemplate) == address(0)) {
            revert L1AtomicTokenBridgeCreator_TemplatesNotSet();
        }

        // deploy L1 side of token bridge
        address owner = _getRollupOwner(inbox);
        (address router, address standardGateway, address customGateway, address wethGateway) =
            _deployL1Contracts(inbox, owner);

        /// deploy factory and then L2 contracts through L2 factory, using 2 retryables calls
        uint256 valueSpentForFactory = _deployL2Factory(inbox, gasPriceBid);
        uint256 fundsRemaining = msg.value - valueSpentForFactory;
        _deployL2Contracts(
            router, standardGateway, customGateway, wethGateway, inbox, maxGasForContracts, gasPriceBid, fundsRemaining
        );
    }

    /**
     * @notice Rollup owner can override canonical router address by registering other non-canonical router.
     * @dev Non-canonical router can be unregistered by re-setting it to address(0) - it makes canonical router the valid one.
     */
    function setNonCanonicalRouter(address inbox, address nonCanonicalRouter) external {
        if (msg.sender != _getRollupOwner(inbox)) {
            revert L1AtomicTokenBridgeCreator_OnlyRollupOwner();
        }
        if (nonCanonicalRouter == getCanonicalL1RouterAddress(inbox)) {
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

        return getCanonicalL1RouterAddress(inbox);
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
            owner, address(standardGateway), address(0), getCanonicalL2RouterAddress(), inbox
        );

        // transfer ownership to owner
        ProxyAdmin(proxyAdmin).transferOwnership(owner);

        // emit it
        emit OrbitTokenBridgeCreated(inbox, owner, router, standardGateway, customGateway, wethGateway, proxyAdmin);
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
            getCanonicalL2StandardGatewayAddress(),
            router,
            inbox,
            keccak256(type(ClonableBeaconProxy).creationCode),
            canonicalL2BeaconProxyFactoryAddress
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

        customGateway.initialize(getCanonicalL2CustomGatewayAddress(), router, inbox, owner);

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

        wethGateway.initialize(getCanonicalL2WethGatewayAddress(), router, inbox, l1Weth, getCanonicalL2WethAddress());

        return address(wethGateway);
    }

    function _deployL2Factory(address inbox, uint256 gasPriceBid) internal returns (uint256) {
        // encode L2 factory bytecode
        bytes memory deploymentData = _creationCodeFor(l2TokenBridgeFactoryTemplate.code);

        uint256 maxSubmissionCost = IInbox(inbox).calculateRetryableSubmissionFee(deploymentData.length, 0);
        uint256 value = maxSubmissionCost + gasLimitForL2FactoryDeployment * gasPriceBid;
        IInbox(inbox).createRetryableTicket{value: value}(
            address(0),
            0,
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            gasLimitForL2FactoryDeployment,
            gasPriceBid,
            deploymentData
        );

        return value;
    }

    function _deployL2Contracts(
        address l1Router,
        address l1StandardGateway,
        address l1CustomGateway,
        address l1WethGateway,
        address inbox,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 availableFunds
    ) internal {
        retryableSender.sendRetryable{value: availableFunds}(
            RetryableParams(inbox, canonicalL2FactoryAddress, msg.sender, msg.sender, maxGas, gasPriceBid),
            L2TemplateAddresses(
                l2RouterTemplate,
                l2StandardGatewayTemplate,
                l2CustomGatewayTemplate,
                l2WethGatewayTemplate,
                l2WethTemplate
            ),
            L1Addresses(l1Router, l1StandardGateway, l1CustomGateway, l1WethGateway, l1Weth),
            getCanonicalL2StandardGatewayAddress(),
            _getRollupOwner(inbox),
            msg.sender
        );
    }

    function getCanonicalL1RouterAddress(address inbox) public view returns (address) {
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

    function getCanonicalL2RouterAddress() public view returns (address) {
        address logicSeedAddress = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_ROUTER_LOGIC),
            keccak256(type(CanonicalAddressSeed).creationCode),
            canonicalL2FactoryAddress
        );

        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_ROUTER),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(logicSeedAddress, canonicalL2ProxyAdminAddress, bytes(""))
                )
            ),
            canonicalL2FactoryAddress
        );
    }

    function getCanonicalL2StandardGatewayAddress() public view returns (address) {
        address logicSeedAddress = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY_LOGIC),
            keccak256(type(CanonicalAddressSeed).creationCode),
            canonicalL2FactoryAddress
        );

        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(logicSeedAddress, canonicalL2ProxyAdminAddress, bytes(""))
                )
            ),
            canonicalL2FactoryAddress
        );
    }

    function getCanonicalL2CustomGatewayAddress() public view returns (address) {
        address logicSeedAddress = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY_LOGIC),
            keccak256(type(CanonicalAddressSeed).creationCode),
            canonicalL2FactoryAddress
        );

        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(logicSeedAddress, canonicalL2ProxyAdminAddress, bytes(""))
                )
            ),
            canonicalL2FactoryAddress
        );
    }

    function getCanonicalL2WethGatewayAddress() public view returns (address) {
        address logicSeedAddress = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_WETH_GATEWAY_LOGIC),
            keccak256(type(CanonicalAddressSeed).creationCode),
            canonicalL2FactoryAddress
        );

        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_WETH_GATEWAY),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(logicSeedAddress, canonicalL2ProxyAdminAddress, bytes(""))
                )
            ),
            canonicalL2FactoryAddress
        );
    }

    function getCanonicalL2WethAddress() public view returns (address) {
        address logicSeedAddress = Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_WETH_LOGIC),
            keccak256(type(CanonicalAddressSeed).creationCode),
            canonicalL2FactoryAddress
        );

        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_WETH),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(logicSeedAddress, canonicalL2ProxyAdminAddress, bytes(""))
                )
            ),
            canonicalL2FactoryAddress
        );
    }

    /**
     * @notice Compute address of contract deployed using CREATE opcode
     * @return computed address
     */
    function _computeAddress(address origin, uint256 nonce) internal pure returns (address) {
        bytes memory data;
        if (nonce == 0x00) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), origin, bytes1(0x80));
        } else if (nonce <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), origin, uint8(nonce));
        } else if (nonce <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), origin, bytes1(0x81), uint8(nonce));
        } else if (nonce <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), origin, bytes1(0x82), uint16(nonce));
        } else if (nonce <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), origin, bytes1(0x83), uint24(nonce));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), origin, bytes1(0x84), uint32(nonce));
        }
        return address(uint160(uint256(keccak256(data))));
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

    function _getRollupOwner(address inbox) internal view returns (address) {
        return IInbox(inbox).bridge().rollup().owner();
    }

    function _getL1Salt(bytes32 prefix, address inbox) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(prefix, inbox));
    }

    function _getL2Salt(bytes32 prefix) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(prefix, AddressAliasHelper.applyL1ToL2Alias(address(retryableSender))));
    }
}
