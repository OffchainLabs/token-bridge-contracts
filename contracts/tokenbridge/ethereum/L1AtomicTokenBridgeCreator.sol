// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {
    L1TokenBridgeRetryableSender,
    L1DeploymentAddresses,
    L2DeploymentAddresses,
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
    OrbitSalts,
    L2RuntimeCode,
    ProxyAdmin
} from "../arbitrum/L2AtomicTokenBridgeFactory.sol";
import {CreationCodeHelper} from "../libraries/CreationCodeHelper.sol";
import {
    IUpgradeExecutor,
    UpgradeExecutor
} from "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import {AddressAliasHelper} from "../libraries/AddressAliasHelper.sol";
import {IInbox, IBridge, IOwnable} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
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
 * @notice This contract is used to deploy token bridge on custom Orbit chains.
 * @dev Throughout the contract terms L1 and L2 are used, but those can be considered as parent (N) chain and child (N+1) chain.
 */
contract L1AtomicTokenBridgeCreator is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    error L1AtomicTokenBridgeCreator_OnlyRollupOwner();
    error L1AtomicTokenBridgeCreator_TemplatesNotSet();
    error L1AtomicTokenBridgeCreator_RollupOwnershipMisconfig();
    error L1AtomicTokenBridgeCreator_ProxyAdminNotFound();
    error L1AtomicTokenBridgeCreator_L2FactoryCannotBeChanged();

    event OrbitTokenBridgeCreated(
        address indexed inbox,
        address indexed owner,
        L1DeploymentAddresses l1Deployment,
        L2DeploymentAddresses l2Deployment,
        address proxyAdmin,
        address upgradeExecutor
    );
    event OrbitTokenBridgeTemplatesUpdated();
    event OrbitTokenBridgeDeploymentSet(
        address indexed inbox, L1DeploymentAddresses l1, L2DeploymentAddresses l2
    );

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

    // use separate mapping to allow appending to the struct in the future
    // and workaround some stack too deep issues
    mapping(address => L1DeploymentAddresses) public inboxToL1Deployment;
    mapping(address => L2DeploymentAddresses) public inboxToL2Deployment;

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
    address public l2MulticallTemplate;

    // WETH address on L1
    address public l1Weth;

    // Multicall2 address on L1, this should NOT be ArbMulticall2
    address public l1Multicall;

    // immutable canonical address for L2 factory
    // other canonical addresses (dependent on L2 template implementations) can be fetched through `_predictL2***Address` functions
    address public canonicalL2FactoryAddress;

    constructor() {
        _disableInitializers();
    }

    function initialize(L1TokenBridgeRetryableSender _retryableSender) public initializer {
        __Ownable_init();

        // store retryable sender and initialize it. This contract will be set as owner
        retryableSender = _retryableSender;
        retryableSender.initialize();

        canonicalL2FactoryAddress =
            _computeAddressAtNonce0(AddressAliasHelper.applyL1ToL2Alias(address(this)));
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
        address _l2MulticallTemplate,
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
        l2MulticallTemplate = _l2MulticallTemplate;

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
     *      In addition to deploying token bridge contracts, L2 factory will also deploy UpgradeExector on L2 side.
     *      L2 UpgradeExecutor will set 2 accounts to have EXECUTOR role - rollupOwner and alias of L1UpgradeExecutor.
     *      'rollupOwner' can be either EOA or a contract. If it is a contract, address will be aliased before sending to L2
     *      in order to be usable.
     *
     *      Warning: Due to asynchronous communication between parent and child chain, always check child chain contracts are
     *      fully deployed and initialized before sending tokens to the bridge. Otherwise tokens might be permanently lost.
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

        // we allow resending l2 deployment calls
        // this is useful to recover from expired or out-of-order retryables
        // in case of resend, we assume L1 contracts already exist and we just need to deploy L2 contracts
        // deployment mappings should not be updated in case of resend
        bool isResend = (inboxToL1Deployment[inbox].router != address(0));

        bool isUsingFeeToken = _getFeeToken(inbox) != address(0);

        // store L2 addresses before deployments
        L1DeploymentAddresses memory l1Deployment;
        L2DeploymentAddresses memory l2Deployment;

        // if resend, we use the existing l1 deployment
        if (isResend) {
            l1Deployment = inboxToL1Deployment[inbox];
        }

        {
            // store L2 addresses which are proxies
            uint256 chainId = IRollupCore(address(IInbox(inbox).bridge().rollup())).chainId();
            l2Deployment.router = _getProxyAddress(OrbitSalts.L2_ROUTER, chainId);
            l2Deployment.standardGateway = _getProxyAddress(OrbitSalts.L2_STANDARD_GATEWAY, chainId);
            l2Deployment.customGateway = _getProxyAddress(OrbitSalts.L2_CUSTOM_GATEWAY, chainId);
            if (!isUsingFeeToken) {
                l2Deployment.wethGateway = _getProxyAddress(OrbitSalts.L2_WETH_GATEWAY, chainId);
                l2Deployment.weth = _getProxyAddress(OrbitSalts.L2_WETH, chainId);
            }
            l2Deployment.upgradeExecutor = _getProxyAddress(OrbitSalts.L2_EXECUTOR, chainId);

            // store L2 addresses which are not proxies
            l2Deployment.proxyAdmin = _predictL2ProxyAdminAddress(chainId);
            l2Deployment.beaconProxyFactory = _predictL2BeaconProxyFactoryAddress(chainId);
            l2Deployment.multicall = _predictL2Multicall(chainId);
        }

        // deploy L1 side of token bridge
        // get existing proxy admin and upgrade executor
        address proxyAdmin = IInboxProxyAdmin(inbox).getProxyAdmin();
        if (proxyAdmin == address(0)) {
            revert L1AtomicTokenBridgeCreator_ProxyAdminNotFound();
        }

        // if resend, we assume L1 contracts already exist
        if (!isResend) {
            // l1 router deployment block
            {
                address routerTemplate = isUsingFeeToken
                    ? address(l1Templates.feeTokenBasedRouterTemplate)
                    : address(l1Templates.routerTemplate);
                l1Deployment.router = _deployProxyWithSalt(
                    _getL1Salt(OrbitSalts.L1_ROUTER, inbox), routerTemplate, proxyAdmin
                );
            }

            // l1 standard gateway deployment block
            {
                address template = isUsingFeeToken
                    ? address(l1Templates.feeTokenBasedStandardGatewayTemplate)
                    : address(l1Templates.standardGatewayTemplate);

                L1ERC20Gateway standardGateway = L1ERC20Gateway(
                    _deployProxyWithSalt(
                        _getL1Salt(OrbitSalts.L1_STANDARD_GATEWAY, inbox), template, proxyAdmin
                    )
                );

                standardGateway.initialize(
                    l2Deployment.standardGateway,
                    l1Deployment.router,
                    inbox,
                    keccak256(type(ClonableBeaconProxy).creationCode),
                    l2Deployment.beaconProxyFactory
                );

                l1Deployment.standardGateway = address(standardGateway);
            }

            // l1 custom gateway deployment block
            {
                address template = isUsingFeeToken
                    ? address(l1Templates.feeTokenBasedCustomGatewayTemplate)
                    : address(l1Templates.customGatewayTemplate);

                L1CustomGateway customGateway = L1CustomGateway(
                    _deployProxyWithSalt(
                        _getL1Salt(OrbitSalts.L1_CUSTOM_GATEWAY, inbox), template, proxyAdmin
                    )
                );

                customGateway.initialize(
                    l2Deployment.customGateway, l1Deployment.router, inbox, upgradeExecutor
                );

                l1Deployment.customGateway = address(customGateway);
            }

            // l1 weth gateway deployment block
            if (!isUsingFeeToken) {
                L1WethGateway wethGateway = L1WethGateway(
                    payable(
                        _deployProxyWithSalt(
                            _getL1Salt(OrbitSalts.L1_WETH_GATEWAY, inbox),
                            address(l1Templates.wethGatewayTemplate),
                            proxyAdmin
                        )
                    )
                );

                wethGateway.initialize(
                    l2Deployment.wethGateway, l1Deployment.router, inbox, l1Weth, l2Deployment.weth
                );

                l1Deployment.wethGateway = address(wethGateway);
                l1Deployment.weth = l1Weth;
            }

            // init router
            L1GatewayRouter(l1Deployment.router).initialize(
                upgradeExecutor,
                l1Deployment.standardGateway,
                address(0),
                l2Deployment.router,
                inbox
            );
        }

        // deploy factory and then L2 contracts through L2 factory, using 2 retryables calls
        // we do not care if it is a resend or not, if the L2 deployment already exists it will simply fail on L2
        _deployL2Factory(inbox, gasPriceBid, isUsingFeeToken);
        if (isUsingFeeToken) {
            // transfer fee tokens to inbox to pay for 2nd retryable
            address feeToken = _getFeeToken(inbox);
            uint256 fee = maxGasForContracts * gasPriceBid;
            IERC20(feeToken).safeTransferFrom(msg.sender, inbox, fee);
        }

        // alias rollup owner if it is a contract
        address l2RollupOwner = rollupOwner.code.length == 0
            ? rollupOwner
            : AddressAliasHelper.applyL1ToL2Alias(rollupOwner);

        // sweep the balance to send the retryable and refund the difference
        // it is known that any eth previously in this contract can be extracted
        // tho it is not expected that this contract will have any eth
        retryableSender.sendRetryable{value: isUsingFeeToken ? 0 : address(this).balance}(
            RetryableParams(
                inbox,
                canonicalL2FactoryAddress,
                msg.sender,
                msg.sender,
                maxGasForContracts,
                gasPriceBid
            ),
            L2TemplateAddresses(
                l2RouterTemplate,
                l2StandardGatewayTemplate,
                l2CustomGatewayTemplate,
                isUsingFeeToken ? address(0) : l2WethGatewayTemplate,
                isUsingFeeToken ? address(0) : l2WethTemplate,
                address(l1Templates.upgradeExecutor),
                l2MulticallTemplate
            ),
            l1Deployment,
            l2Deployment.standardGateway,
            l2RollupOwner,
            msg.sender,
            upgradeExecutor,
            isUsingFeeToken
        );

        // deployment mappings should not be updated in case of resend
        if (!isResend) {
            emit OrbitTokenBridgeCreated(
                inbox, rollupOwner, l1Deployment, l2Deployment, proxyAdmin, upgradeExecutor
            );
            inboxToL1Deployment[inbox] = l1Deployment;
            inboxToL2Deployment[inbox] = l2Deployment;
        }
    }

    /**
     * @notice Rollup owner can override deployment
     */
    function setDeployment(
        address inbox,
        L1DeploymentAddresses memory l1Deployment,
        L2DeploymentAddresses memory l2Deployment
    ) external {
        if (msg.sender != IInbox(inbox).bridge().rollup().owner()) {
            revert L1AtomicTokenBridgeCreator_OnlyRollupOwner();
        }

        inboxToL1Deployment[inbox] = l1Deployment;
        inboxToL2Deployment[inbox] = l2Deployment;
        emit OrbitTokenBridgeDeploymentSet(inbox, l1Deployment, l2Deployment);
    }

    /**
     * @notice Get the L1 router address for a given inbox
     * @dev    This is kept since its cheaper than accessing the mapping getter
     *         and is useful enough for most onchain purposes
     */
    function getRouter(address inbox) public view returns (address) {
        return inboxToL1Deployment[inbox].router;
    }

    function _deployL2Factory(address inbox, uint256 gasPriceBid, bool isUsingFeeToken) internal {
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
        }
    }

    function _predictL2ProxyAdminAddress(uint256 chainId) internal view returns (address) {
        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_PROXY_ADMIN, chainId),
            keccak256(type(ProxyAdmin).creationCode),
            canonicalL2FactoryAddress
        );
    }

    function _predictL2BeaconProxyFactoryAddress(uint256 chainId) internal view returns (address) {
        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.BEACON_PROXY_FACTORY, chainId),
            keccak256(type(BeaconProxyFactory).creationCode),
            canonicalL2FactoryAddress
        );
    }

    function _predictL2Multicall(uint256 chainId) internal view returns (address) {
        return Create2.computeAddress(
            _getL2Salt(OrbitSalts.L2_MULTICALL, chainId),
            keccak256(CreationCodeHelper.getCreationCodeFor(l2MulticallTemplate.code)),
            canonicalL2FactoryAddress
        );
    }

    function _getFeeToken(address inbox) internal view returns (address) {
        address bridge = address(IInbox(inbox).bridge());
        try IERC20Bridge(bridge).nativeToken() returns (address feeToken) {
            return feeToken;
        } catch {
            return address(0);
        }
    }

    /**
     * @notice Compute address of contract deployed using CREATE opcode at nonce 0
     * @dev The contract address is derived by RLP encoding the deployer's address and the nonce using the Keccak-256 hashing algorithm.
     *      More formally: keccak256(rlp.encode([origin, nonce])[12:]
     *
     *      First part of the function implementation does RLP encoding of [origin, nonce].
     *        - nonce's prefix is encoded depending on its size -> 0x80 + lenInBytes(nonce)
     *        - origin is 20 bytes long so its encoded prefix is 0x80 + 0x14 = 0x94
     *        - prefix of the whole list is 0xc0 + lenInBytes(RLP(list))
     *      After we have RLP encoding in place last step is to hash it, take last 20 bytes and cast is to an address.
     *
     *      This function is an codesize optimized version to only calculate the address for nonce 0.
     * @return computed address
     */
    function _computeAddressAtNonce0(address origin) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), origin, bytes1(0x80)))
                )
            )
        );
    }

    /**
     * @notice L2 contracts are deployed as proxy with dummy seed logic contracts using CREATE2. That enables
     *         us to upfront calculate the expected canonical addresses. This proxy should be upgraded to the
     *         intended logic implementation immediately.
     */
    function _getProxyAddress(bytes memory prefix, uint256 chainId)
        internal
        view
        returns (address)
    {
        return Create2.computeAddress(
            _getL2Salt(prefix, chainId),
            keccak256(
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(
                        canonicalL2FactoryAddress, _predictL2ProxyAdminAddress(chainId), bytes("")
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

    /**
     * @notice Internal method to deploy TransparentUpgradeableProxy with CREATE2 opcode.
     */
    function _deployProxyWithSalt(bytes32 salt, address logic, address admin)
        internal
        returns (address)
    {
        return address(new TransparentUpgradeableProxy{salt: salt}(logic, admin, bytes("")));
    }
}

interface IERC20Bridge {
    function nativeToken() external view returns (address);
}

interface IInboxProxyAdmin {
    function getProxyAdmin() external view returns (address);
}

interface IRollupCore {
    function chainId() external view returns (uint256);
}
