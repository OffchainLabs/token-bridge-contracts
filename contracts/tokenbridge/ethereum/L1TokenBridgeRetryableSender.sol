// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {
    L2AtomicTokenBridgeFactory,
    L2RuntimeCode,
    ProxyAdmin
} from "../arbitrum/L2AtomicTokenBridgeFactory.sol";
import {AddressAliasHelper} from "../libraries/AddressAliasHelper.sol";
import {
    Initializable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Token Bridge Retryable Ticket Sender
 * @notice This contract is intended to simply send out retryable ticket to deploy L2 side of the token bridge.
 *         Ticket data is prepared by L1AtomicTokenBridgeCreator. Retryable ticket issuance is done separately
 *         from L1 creator in order to have different senders for deployment of L2 factory vs. deployment of
 *         rest of L2 contracts. Having same sender can lead to edge cases where retryables are executed out
 *         order - that would prevent us from having canonical set of L2 addresses.
 *
 */
contract L1TokenBridgeRetryableSender is Initializable, OwnableUpgradeable {
    error L1TokenBridgeRetryableSender_RefundFailed();
    error L1TokenBridgeRetryableSender_EthReceivedForFeeToken();

    function initialize() public initializer {
        __Ownable_init();
    }

    /**
     * @notice Creates retryable which deploys L2 side of the token bridge.
     * @dev Function will build retryable data, calculate submission cost and retryable value, create retryable
     *      and then refund the remaining funds to original delpoyer if excess eth was sent.
     */
    function sendRetryable(
        RetryableParams calldata retryableParams,
        L2TemplateAddresses calldata l2,
        L1DeploymentAddresses calldata l1,
        address l2StandardGatewayAddress,
        address rollupOwner,
        address deployer,
        address l1UpgradeExecutor
    ) external payable onlyOwner {
        bool isUsingFeeToken = retryableParams.feeTokenTotalFeeAmount > 0;
        address aliasedL1UpgradeExecutor = AddressAliasHelper.applyL1ToL2Alias(l1UpgradeExecutor);
        if (!isUsingFeeToken) {
            _sendRetryableUsingEth(
                retryableParams,
                l2,
                l1,
                l2StandardGatewayAddress,
                rollupOwner,
                deployer,
                aliasedL1UpgradeExecutor
            );
        } else {
            if (msg.value > 0) revert L1TokenBridgeRetryableSender_EthReceivedForFeeToken();
            _sendRetryableUsingFeeToken(
                retryableParams,
                l2,
                l1,
                l2StandardGatewayAddress,
                rollupOwner,
                aliasedL1UpgradeExecutor
            );
        }
    }

    function _sendRetryableUsingEth(
        RetryableParams calldata retryableParams,
        L2TemplateAddresses calldata l2,
        L1DeploymentAddresses calldata l1,
        address l2StandardGatewayAddress,
        address rollupOwner,
        address deployer,
        address aliasedL1UpgradeExecutor
    ) internal {
        bytes memory data = abi.encodeCall(
            L2AtomicTokenBridgeFactory.deployL2Contracts,
            (
                L2RuntimeCode(
                    l2.routerTemplate.code,
                    l2.standardGatewayTemplate.code,
                    l2.customGatewayTemplate.code,
                    l2.wethGatewayTemplate.code,
                    l2.wethTemplate.code,
                    l2.upgradeExecutorTemplate.code,
                    l2.multicallTemplate.code
                ),
                l1.router,
                l1.standardGateway,
                l1.customGateway,
                l1.wethGateway,
                l1.weth,
                l2StandardGatewayAddress,
                rollupOwner,
                aliasedL1UpgradeExecutor
            )
        );

        uint256 maxSubmissionCost =
            IInbox(retryableParams.inbox).calculateRetryableSubmissionFee(data.length, 0);
        uint256 retryableValue =
            maxSubmissionCost + retryableParams.maxGas * retryableParams.gasPriceBid;
        _createRetryableUsingEth(retryableParams, maxSubmissionCost, retryableValue, data);

        // refund excess value to the deployer
        // it is known that any eth previously in this contract can be extracted
        // tho it is not expected that this contract will have any eth
        (bool success,) = deployer.call{value: address(this).balance}("");
        if (!success) revert L1TokenBridgeRetryableSender_RefundFailed();
    }

    function _sendRetryableUsingFeeToken(
        RetryableParams calldata retryableParams,
        L2TemplateAddresses calldata l2,
        L1DeploymentAddresses calldata l1,
        address l2StandardGatewayAddress,
        address rollupOwner,
        address aliasedL1UpgradeExecutor
    ) internal {
        bytes memory data = abi.encodeCall(
            L2AtomicTokenBridgeFactory.deployL2Contracts,
            (
                L2RuntimeCode(
                    l2.routerTemplate.code,
                    l2.standardGatewayTemplate.code,
                    l2.customGatewayTemplate.code,
                    "",
                    "",
                    l2.upgradeExecutorTemplate.code,
                    l2.multicallTemplate.code
                ),
                l1.router,
                l1.standardGateway,
                l1.customGateway,
                address(0),
                address(0),
                l2StandardGatewayAddress,
                rollupOwner,
                aliasedL1UpgradeExecutor
            )
        );

        _createRetryableUsingFeeToken(retryableParams, data);
    }

    function _createRetryableUsingEth(
        RetryableParams calldata retryableParams,
        uint256 maxSubmissionCost,
        uint256 value,
        bytes memory data
    ) internal {
        IInbox(retryableParams.inbox).createRetryableTicket{value: value}(
            retryableParams.target,
            0,
            maxSubmissionCost,
            retryableParams.excessFeeRefundAddress,
            retryableParams.callValueRefundAddress,
            retryableParams.maxGas,
            retryableParams.gasPriceBid,
            data
        );
    }

    function _createRetryableUsingFeeToken(
        RetryableParams calldata retryableParams,
        bytes memory data
    ) internal {
        IERC20Inbox(retryableParams.inbox).createRetryableTicket(
            retryableParams.target,
            0,
            0,
            retryableParams.excessFeeRefundAddress,
            retryableParams.callValueRefundAddress,
            retryableParams.maxGas,
            retryableParams.gasPriceBid,
            retryableParams.feeTokenTotalFeeAmount,
            data
        );
    }
}

/**
 * retryableParams needed to send retryable ticket
 */
struct RetryableParams {
    address inbox;
    address target;
    address excessFeeRefundAddress;
    address callValueRefundAddress;
    uint256 maxGas;
    uint256 gasPriceBid;
    uint256 feeTokenTotalFeeAmount;
}

/**
 * Addresses of L2 templates deployed on L1
 */
struct L2TemplateAddresses {
    address routerTemplate;
    address standardGatewayTemplate;
    address customGatewayTemplate;
    address wethGatewayTemplate;
    address wethTemplate;
    address upgradeExecutorTemplate;
    address multicallTemplate;
}

/**
 * L1 side of token bridge addresses
 */
struct L1DeploymentAddresses {
    address router;
    address standardGateway;
    address customGateway;
    address wethGateway;
    address weth;
    address masterVaultFactory;
}

struct L2DeploymentAddresses {
    address router;
    address standardGateway;
    address customGateway;
    address wethGateway;
    address weth;
    address proxyAdmin;
    address beaconProxyFactory;
    address upgradeExecutor;
    address multicall;
}

interface IERC20Inbox {
    function createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 tokenTotalFeeAmount,
        bytes calldata data
    ) external returns (uint256);
}
