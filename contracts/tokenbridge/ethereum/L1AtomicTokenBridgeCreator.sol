// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {
    L1TokenBridgeRetryableSender,
    L1DeploymentAddresses,
    RetryableParams,
    L2TemplateAddresses,
    IERC20Inbox,
    IERC20,
    SafeERC20
} from "./L1TokenBridgeRetryableSender.sol";
import {L1GatewayRouter} from "./gateway/L1GatewayRouter.sol";
import {L1ERC20Gateway} from "./gateway/L1ERC20Gateway.sol";
import {L1CustomGateway} from "./gateway/L1CustomGateway.sol";
import {L1WethGateway} from "./gateway/L1WethGateway.sol";
import {L1OrbitGatewayRouter} from "./gateway/L1OrbitGatewayRouter.sol";
import {L1OrbitERC20Gateway} from "./gateway/L1OrbitERC20Gateway.sol";
import {L1OrbitCustomGateway} from "./gateway/L1OrbitCustomGateway.sol";
import {
    L2AtomicTokenBridgeFactory,
    CanonicalAddressSeed,
    OrbitSalts,
    L2RuntimeCode,
    ProxyAdmin
} from "../arbitrum/L2AtomicTokenBridgeFactory.sol";
import {CreationCodeHelper} from "../libraries/CreationCodeHelper.sol";
import {BytesLib} from "../libraries/BytesLib.sol";
import {
    IUpgradeExecutor,
    UpgradeExecutor
} from "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import {AddressAliasHelper} from "../libraries/AddressAliasHelper.sol";
import {IInbox, IBridge, IOwnable} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {AddressAliasHelper} from "../libraries/AddressAliasHelper.sol";
import {ArbMulticall2} from "../../rpc-utils/MulticallV2.sol";
import {BeaconProxyFactory, ClonableBeaconProxy} from "../libraries/ClonableBeaconProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {
    Initializable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";

/**
 * @title Layer1 token bridge creator
 * @notice This contract is used to deploy token bridge on custom L2 chains.
 * @dev Throughout the contract terms L1 and L2 are used, but those can be considered as base (N) chain and child (N+1) chain
 */
contract L1AtomicTokenBridgeCreator is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    error L1AtomicTokenBridgeCreator_OnlyRollupOwner();
    error L1AtomicTokenBridgeCreator_InvalidRouterAddr();
    error L1AtomicTokenBridgeCreator_TemplatesNotSet();
    error L1AtomicTokenBridgeCreator_RollupOwnershipMisconfig();
    error L1AtomicTokenBridgeCreator_ProxyAdminNotFound();
    error L1AtomicTokenBridgeCreator_L2FactoryCannotBeChanged();

    event OrbitTokenBridgeCreated(
        address indexed inbox,
        address indexed owner,
        address router,
        address standardGateway,
        address customGateway,
        address wethGateway,
        address proxyAdmin,
        address upgradeExecutor
    );
    event OrbitTokenBridgeTemplatesUpdated();
    event NonCanonicalRouterSet(address indexed inbox, address indexed router);

    struct L1Templates {
        L1GatewayRouter routerTemplate;
        L1ERC20Gateway standardGatewayTemplate;
        L1CustomGateway customGatewayTemplate;
        L1WethGateway wethGatewayTemplate;
        L1OrbitGatewayRouter feeTokenBasedRouterTemplate;
        L1OrbitERC20Gateway feeTokenBasedStandardGatewayTemplate;
        L1OrbitCustomGateway feeTokenBasedCustomGatewayTemplate;
        IUpgradeExecutor upgradeExecutor;
    }

    // non-canonical router registry
    mapping(address => address) public inboxToNonCanonicalRouter;

    // Hard-code gas to make sure gas limit is big enough for L2 factory deployment to succeed.
    // If retryable would've reverted due to too low gas limit, nonce 0 would be burned and
    // canonical address for L2 factory would've been unobtainable
    uint256 public gasLimitForL2FactoryDeployment;

    // contract which creates retryables for deploying L2 side of token bridge
    L1TokenBridgeRetryableSender public retryableSender;

    // L1 logic contracts shared by all token bridges
    L1Templates public l1Templates;

    // L2 contracts deployed to L1 as bytecode placeholders
    address public l2TokenBridgeFactoryTemplate;
    address public l2RouterTemplate;
    address public l2StandardGatewayTemplate;
    address public l2CustomGatewayTemplate;
    address public l2WethGatewayTemplate;
    address public l2WethTemplate;

    // WETH address on L1
    address public l1Weth;

    // Multicall2 address on L1, this should NOT be ArbMulticall2
    address public l1Multicall;

    // immutable canonical address for L2 factory
    // other canonical addresses (dependent on L2 template implementations) can be fetched through `getCanonicalL2***Address` functions
    address public canonicalL2FactoryAddress;

    // immutable ArbMulticall2 template deployed on L1
    // Note - due to contract size limits, multicall template and its bytecode hash are set in constructor as immutables
    address public immutable l2MulticallTemplate;
    // code hash used for calculation of L2 multicall address
    bytes32 public immutable ARB_MULTICALL_CODE_HASH;

    constructor(address _l2MulticallTemplate) {
        l2MulticallTemplate = _l2MulticallTemplate;
        ARB_MULTICALL_CODE_HASH =
            keccak256(CreationCodeHelper.getCreationCodeFor(l2MulticallTemplate.code));
        _disableInitializers();
    }

    function initialize(L1TokenBridgeRetryableSender _retryableSender) public initializer {
        __Ownable_init();

        // store retryable sender and initialize it. This contract will be set as owner
        retryableSender = _retryableSender;
        retryableSender.initialize();

        canonicalL2FactoryAddress =
            _computeAddress(AddressAliasHelper.applyL1ToL2Alias(address(this)), 0);
    }

    /**
     * @notice Set addresses of L1 logic contracts and L2 contracts which are deployed on L1.
     * @dev L2 contracts are deployed to L1 as bytecode placeholders - that bytecode will be part of retryable
     *      payload used to deploy contracts on L2 side.
     */
    function setTemplates(
        L1Templates calldata _l1Templates,
        address _l2TokenBridgeFactoryTemplate,
        address _l2RouterTemplate,
        address _l2StandardGatewayTemplate,
        address _l2CustomGatewayTemplate,
        address _l2WethGatewayTemplate,
        address _l2WethTemplate,
        address _l1Weth,
        address _l1Multicall,
        uint256 _gasLimitForL2FactoryDeployment
    ) external onlyOwner {
        l1Templates = _l1Templates;

        if (
            l2TokenBridgeFactoryTemplate != address(0)
                && l2TokenBridgeFactoryTemplate != _l2TokenBridgeFactoryTemplate
        ) {
            revert L1AtomicTokenBridgeCreator_L2FactoryCannotBeChanged();
        }
        l2TokenBridgeFactoryTemplate = _l2TokenBridgeFactoryTemplate;
        l2RouterTemplate = _l2RouterTemplate;
        l2StandardGatewayTemplate = _l2StandardGatewayTemplate;
        l2CustomGatewayTemplate = _l2CustomGatewayTemplate;
        l2WethGatewayTemplate = _l2WethGatewayTemplate;
        l2WethTemplate = _l2WethTemplate;

        l1Weth = _l1Weth;
        l1Multicall = _l1Multicall;

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
    function createTokenBridge(
        address inbox,
        address rollupOwner,
        uint256 maxGasForContracts,
        uint256 gasPriceBid
    ) external payable {
        // templates have to be in place
        if (address(l1Templates.routerTemplate) == address(0)) {
            revert L1AtomicTokenBridgeCreator_TemplatesNotSet();
        }

        // Check that the rollupOwner account has EXECUTOR role
        // on the upgrade executor which is the owner of the rollup
        address upgradeExecutor = IInbox(inbox).bridge().rollup().owner();
        if (
            !IAccessControlUpgradeable(upgradeExecutor).hasRole(
                UpgradeExecutor(upgradeExecutor).EXECUTOR_ROLE(), rollupOwner
            )
        ) {
            revert L1AtomicTokenBridgeCreator_RollupOwnershipMisconfig();
        }

        uint256 rollupChainId = IRollupCore(address(IInbox(inbox).bridge().rollup())).chainId();

        /// deploy L1 side of token bridge
        bool isUsingFeeToken = _getFeeToken(inbox) != address(0);
        L1DeploymentAddresses memory l1DeploymentAddresses =
            _deployL1Contracts(inbox, rollupOwner, upgradeExecutor, isUsingFeeToken, rollupChainId);

        /// deploy factory and then L2 contracts through L2 factory, using 2 retryables calls
        if (isUsingFeeToken) {
            _deployL2Factory(inbox, gasPriceBid, isUsingFeeToken);
            _deployL2ContractsUsingFeeToken(
                l1DeploymentAddresses,
                inbox,
                maxGasForContracts,
                gasPriceBid,
                rollupOwner,
                upgradeExecutor,
                rollupChainId
            );
        } else {
            uint256 valueSpentForFactory = _deployL2Factory(inbox, gasPriceBid, isUsingFeeToken);
            uint256 fundsRemaining = msg.value - valueSpentForFactory;
            _deployL2ContractsUsingEth(
                l1DeploymentAddresses,
                inbox,
                maxGasForContracts,
                gasPriceBid,
                fundsRemaining,
                rollupOwner,
                upgradeExecutor,
                rollupChainId
            );
        }
    }

    /**
     * @notice Rollup owner can override canonical router address by registering other non-canonical router.
     * @dev Non-canonical router can be unregistered by re-setting it to address(0) - it makes canonical router the valid one.
     */
    function setNonCanonicalRouter(address inbox, address nonCanonicalRouter) external {
        if (msg.sender != IInbox(inbox).bridge().rollup().owner()) {
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

    function _deployL1Contracts(
        address inbox,
        address rollupOwner,
        address upgradeExecutor,
        bool isUsingFeeToken,
        uint256 chainId
    ) internal returns (L1DeploymentAddresses memory l1Addresses) {
        // get existing proxy admin and upgrade executor
        address proxyAdmin = IInbox_ProxyAdmin(inbox).getProxyAdmin();
        if (proxyAdmin == address(0)) {
            revert L1AtomicTokenBridgeCreator_ProxyAdminNotFound();
        }

        // deploy router
        address routerTemplate = isUsingFeeToken
            ? address(l1Templates.feeTokenBasedRouterTemplate)
            : address(l1Templates.routerTemplate);
        l1Addresses.router = address(
            new TransparentUpgradeableProxy{ salt: _getL1Salt(OrbitSalts.L1_ROUTER, inbox) }(
                routerTemplate,
                proxyAdmin,
                bytes("")
            )
        );

        // deploy and init gateways
        l1Addresses.standardGateway = _deployL1StandardGateway(
            proxyAdmin, l1Addresses.router, inbox, isUsingFeeToken, chainId
        );
        l1Addresses.customGateway = _deployL1CustomGateway(
            proxyAdmin, l1Addresses.router, inbox, upgradeExecutor, isUsingFeeToken, chainId
        );
        l1Addresses.wethGateway = isUsingFeeToken
            ? address(0)
            : _deployL1WethGateway(proxyAdmin, l1Addresses.router, inbox, chainId);
        l1Addresses.weth = isUsingFeeToken ? address(0) : l1Weth;

        // init router
        L1GatewayRouter(l1Addresses.router).initialize(
            upgradeExecutor,
            l1Addresses.standardGateway,
            address(0),
            getCanonicalL2RouterAddress(chainId),
            inbox
        );

        // emit it
        emit OrbitTokenBridgeCreated(
            inbox,
            rollupOwner,
            l1Addresses.router,
            l1Addresses.standardGateway,
            l1Addresses.customGateway,
            l1Addresses.wethGateway,
            proxyAdmin,
            upgradeExecutor
        );
    }

    function _deployL1StandardGateway(
        address proxyAdmin,
        address router,
        address inbox,
        bool isUsingFeeToken,
        uint256 chainId
    ) internal returns (address) {
        address template = isUsingFeeToken
            ? address(l1Templates.feeTokenBasedStandardGatewayTemplate)
            : address(l1Templates.standardGatewayTemplate);

        L1ERC20Gateway standardGateway = L1ERC20Gateway(
            address(
                new TransparentUpgradeableProxy{
                    salt: _getL1Salt(OrbitSalts.L1_STANDARD_GATEWAY, inbox)
                }(template, proxyAdmin, bytes(""))
            )
        );

        standardGateway.initialize(
            getCanonicalL2StandardGatewayAddress(chainId),
            router,
            inbox,
            keccak256(type(ClonableBeaconProxy).creationCode),
            getCanonicalL2BeaconProxyFactoryAddress(chainId)
        );

        return address(standardGateway);
    }

    function _deployL1CustomGateway(
        address proxyAdmin,
        address router,
        address inbox,
        address upgradeExecutor,
        bool isUsingFeeToken,
        uint256 chainId
    ) internal returns (address) {
        address template = isUsingFeeToken
            ? address(l1Templates.feeTokenBasedCustomGatewayTemplate)
            : address(l1Templates.customGatewayTemplate);

        L1CustomGateway customGateway = L1CustomGateway(
            address(
                new TransparentUpgradeableProxy{
                    salt: _getL1Salt(OrbitSalts.L1_CUSTOM_GATEWAY, inbox)
                }(template, proxyAdmin, bytes(""))
            )
        );

        customGateway.initialize(
            getCanonicalL2CustomGatewayAddress(chainId), router, inbox, upgradeExecutor
        );

        return address(customGateway);
    }

    function _deployL1WethGateway(
        address proxyAdmin,
        address router,
        address inbox,
        uint256 chainId
    ) internal returns (address) {
        L1WethGateway wethGateway = L1WethGateway(
            payable(
                address(
                    new TransparentUpgradeableProxy{
                        salt: _getL1Salt(OrbitSalts.L1_WETH_GATEWAY, inbox)
                    }(address(l1Templates.wethGatewayTemplate), proxyAdmin, bytes(""))
                )
            )
        );

        wethGateway.initialize(
            getCanonicalL2WethGatewayAddress(chainId),
            router,
            inbox,
            l1Weth,
            getCanonicalL2WethAddress(chainId)
        );

        return address(wethGateway);
    }

    function _deployL2Factory(address inbox, uint256 gasPriceBid, bool isUsingFeeToken)
        internal
        returns (uint256)
    {
        // encode L2 factory bytecode
        bytes memory deploymentData =
            CreationCodeHelper.getCreationCodeFor(l2TokenBridgeFactoryTemplate.code);

        if (isUsingFeeToken) {
            // transfer fee tokens to inbox to pay for 1st retryable
            address feeToken = _getFeeToken(inbox);
            uint256 retryableFee = gasLimitForL2FactoryDeployment * gasPriceBid;
            IERC20(feeToken).safeTransferFrom(msg.sender, inbox, retryableFee);

            IERC20Inbox(inbox).createRetryableTicket(
                address(0),
                0,
                0,
                msg.sender,
                msg.sender,
                gasLimitForL2FactoryDeployment,
                gasPriceBid,
                retryableFee,
                deploymentData
            );
            return 0;
        } else {
            uint256 maxSubmissionCost =
                IInbox(inbox).calculateRetryableSubmissionFee(deploymentData.length, 0);
            uint256 retryableFee = maxSubmissionCost + gasLimitForL2FactoryDeployment * gasPriceBid;

            IInbox(inbox).createRetryableTicket{value: retryableFee}(
                address(0),
                0,
                maxSubmissionCost,
                msg.sender,
                msg.sender,
                gasLimitForL2FactoryDeployment,
                gasPriceBid,
                deploymentData
            );
            return retryableFee;
        }
    }

    function _deployL2ContractsUsingEth(
        L1DeploymentAddresses memory l1Addresses,
        address inbox,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 availableFunds,
        address rollupOwner,
        address upgradeExecutor,
        uint256 chainId
    ) internal {
        retryableSender.sendRetryableUsingEth{value: availableFunds}(
            RetryableParams(
                inbox, canonicalL2FactoryAddress, msg.sender, msg.sender, maxGas, gasPriceBid
            ),
            L2TemplateAddresses(
                l2RouterTemplate,
                l2StandardGatewayTemplate,
                l2CustomGatewayTemplate,
                l2WethGatewayTemplate,
                l2WethTemplate,
                address(l1Templates.upgradeExecutor),
                l2MulticallTemplate
            ),
            l1Addresses,
            getCanonicalL2StandardGatewayAddress(chainId),
            rollupOwner,
            msg.sender,
            AddressAliasHelper.applyL1ToL2Alias(upgradeExecutor)
        );
    }

    function _deployL2ContractsUsingFeeToken(
        L1DeploymentAddresses memory l1Addresses,
        address inbox,
        uint256 maxGas,
        uint256 gasPriceBid,
        address rollupOwner,
        address upgradeExecutor,
        uint256 chainId
    ) internal {
        // transfer fee tokens to inbox to pay for 2nd retryable
        address feeToken = _getFeeToken(inbox);
        uint256 fee = maxGas * gasPriceBid;
        IERC20(feeToken).safeTransferFrom(msg.sender, inbox, fee);

        retryableSender.sendRetryableUsingFeeToken(
            RetryableParams(
                inbox, canonicalL2FactoryAddress, msg.sender, msg.sender, maxGas, gasPriceBid
            ),
            L2TemplateAddresses(
                l2RouterTemplate,
                l2StandardGatewayTemplate,
                l2CustomGatewayTemplate,
                address(0),
                address(0),
                address(l1Templates.upgradeExecutor),
                l2MulticallTemplate
            ),
            l1Addresses,
            getCanonicalL2StandardGatewayAddress(chainId),
            rollupOwner,
            AddressAliasHelper.applyL1ToL2Alias(upgradeExecutor)
        );
    }

    function getCanonicalL1RouterAddress(address inbox) public view returns (address) {
        address proxyAdminAddress = IInbox_ProxyAdmin(inbox).getProxyAdmin();

        bool isUsingFeeToken = _getFeeToken(inbox) != address(0);
        address template = isUsingFeeToken
            ? address(l1Templates.feeTokenBasedRouterTemplate)
            : address(l1Templates.routerTemplate);

        return Create2.computeAddress(
            _getL1Salt(OrbitSalts.L1_ROUTER, inbox),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(template, proxyAdminAddress, bytes(""))
                )
            ),
            address(this)
        );
    }

    function getCanonicalL2RouterAddress(uint256 chainId) public view returns (address) {
        return _getProxyAddress(
            _getL2Salt(OrbitSalts.L2_ROUTER_LOGIC, chainId),
            _getL2Salt(OrbitSalts.L2_ROUTER, chainId),
            chainId
        );
    }

    function getCanonicalL2StandardGatewayAddress(uint256 chainId) public view returns (address) {
        return _getProxyAddress(
            _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY_LOGIC, chainId),
            _getL2Salt(OrbitSalts.L2_STANDARD_GATEWAY, chainId),
            chainId
        );
    }

    function getCanonicalL2CustomGatewayAddress(uint256 chainId) public view returns (address) {
        return _getProxyAddress(
            _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY_LOGIC, chainId),
            _getL2Salt(OrbitSalts.L2_CUSTOM_GATEWAY, chainId),
            chainId
        );
    }

    function getCanonicalL2WethGatewayAddress(uint256 chainId) public view returns (address) {
        return _getProxyAddress(
            _getL2Salt(OrbitSalts.L2_WETH_GATEWAY_LOGIC, chainId),
            _getL2Salt(OrbitSalts.L2_WETH_GATEWAY, chainId),
            chainId
        );
    }

    function getCanonicalL2WethAddress(uint256 chainId) public view returns (address) {
        return _getProxyAddress(
            _getL2Salt(OrbitSalts.L2_WETH_LOGIC, chainId),
            _getL2Salt(OrbitSalts.L2_WETH, chainId),
            chainId
        );
    }

    function getCanonicalL2ProxyAdminAddress(uint256 chainId) public view returns (address) {
        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_PROXY_ADMIN, chainId),
            keccak256(type(ProxyAdmin).creationCode),
            canonicalL2FactoryAddress
        );
    }

    function getCanonicalL2BeaconProxyFactoryAddress(uint256 chainId)
        public
        view
        returns (address)
    {
        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.BEACON_PROXY_FACTORY, chainId),
            keccak256(type(BeaconProxyFactory).creationCode),
            canonicalL2FactoryAddress
        );
    }

    function getCanonicalL2UpgradeExecutorAddress(uint256 chainId) public view returns (address) {
        return _getProxyAddress(
            _getL2Salt(OrbitSalts.L2_EXECUTOR_LOGIC, chainId),
            _getL2Salt(OrbitSalts.L2_EXECUTOR, chainId),
            chainId
        );
    }

    function getCanonicalL2Multicall(uint256 chainId) public view returns (address) {
        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_MULTICALL, chainId),
            ARB_MULTICALL_CODE_HASH,
            canonicalL2FactoryAddress
        );
    }

    function _getFeeToken(address inbox) internal view returns (address) {
        address bridge = address(IInbox(inbox).bridge());

        (bool success, bytes memory feeTokenAddressData) =
            bridge.staticcall(abi.encodeWithSelector(IERC20Bridge.nativeToken.selector));

        if (!success || feeTokenAddressData.length < 32) {
            return address(0);
        }

        return BytesLib.toAddress(feeTokenAddressData, 12);
    }

    /**
     * @notice Compute address of contract deployed using CREATE opcode
     * @dev The contract address is derived by RLP encoding the deployer's address and the nonce using the Keccak-256 hashing algorithm.
     *      More formally: keccak256(rlp.encode([origin, nonce])[12:]
     *
     *      First part of the function implementation does RLP encoding of [origin, nonce].
     *        - nonce's prefix is encoded depending on its size -> 0x80 + lenInBytes(nonce)
     *        - origin is 20 bytes long so its encoded prefix is 0x80 + 0x14 = 0x94
     *        - prefix of the whole list is 0xc0 + lenInBytes(RLP(list))
     *      After we have RLP encoding in place last step is to hash it, take last 20 bytes and cast is to an address.
     *
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
     * @notice L2 contracts are deployed as proxy with dummy seed logic contracts using CREATE2. That enables
     *         us to upfront calculate the expected canonical addresses.
     */
    function _getProxyAddress(bytes32 logicSalt, bytes32 proxySalt, uint256 chainId)
        internal
        view
        returns (address)
    {
        address logicSeedAddress = Create2.computeAddress(
            logicSalt, keccak256(type(CanonicalAddressSeed).creationCode), canonicalL2FactoryAddress
        );

        return Create2.computeAddress(
            proxySalt,
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(
                        logicSeedAddress, getCanonicalL2ProxyAdminAddress(chainId), bytes("")
                    )
                )
            ),
            canonicalL2FactoryAddress
        );
    }

    /**
     * @notice We want to have exactly one set of canonical token bridge contracts for every rollup. For that
     *         reason we make rollup's inbox address part of the salt. It prevents deploying more than one
     *         token bridge.
     */
    function _getL1Salt(bytes memory prefix, address inbox) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(prefix, inbox));
    }

    /**
     * @notice Salt for L2 token bridge contracts depends on the chainId and caller's address. Canonical token bridge
     *         will be deployed by retryable ticket which is created by `retryableSender` contract. That
     *         means `retryableSender`'s alias will be used on L2 side to calculate the salt for deploying
     *         L2 contracts, in addition to chainId (_getL2Salt function in L2AtomicTokenBridgeFactory).
     */
    function _getL2Salt(bytes memory prefix, uint256 chainId) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                prefix, chainId, AddressAliasHelper.applyL1ToL2Alias(address(retryableSender))
            )
        );
    }
}

interface IERC20Bridge {
    function nativeToken() external view returns (address);
}

interface IInbox_ProxyAdmin {
    function getProxyAdmin() external view returns (address);
}

interface IRollupCore {
    function chainId() external view returns (uint256);
}
