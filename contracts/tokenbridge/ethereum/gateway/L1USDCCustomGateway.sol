// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {
    L1ArbitrumExtendedGateway,
    L1ArbitrumGateway,
    IL1ArbitrumGateway,
    ITokenGateway,
    TokenGateway,
    IERC20
} from "./L1ArbitrumExtendedGateway.sol";
import {L2USDCCustomGateway} from "../../arbitrum/gateway/L2USDCCustomGateway.sol";

/**
 * @title Custom gateway for USDC implementing Bridged USDC Standard.
 * @notice Reference to the Circle's Bridged USDC Standard:
 *         https://github.com/circlefin/stablecoin-evm/blob/master/doc/bridged_USDC_standard.md
 *
 * @dev    This contract can be used on new Orbit chains which want to provide USDC
 *         bridging solution and keep the possibility to upgrade to native USDC at
 *         some point later. This solution will NOT be used in existing Arbitrum chains.
 *
 *         Child chain custom gateway to be used along this parent chain custom gateway is L2USDCCustomGateway.
 *         This custom gateway differs from standard gateway in the following ways:
 *         - it supports a single parent chain - child chain USDC token pair
 *         - it is ownable
 *         - owner can one-time permanently pause deposits
 *         - owner can trigger burning all the USDC tokens locked in the gateway
 */
contract L1USDCCustomGateway is L1ArbitrumExtendedGateway {
    address public l1USDC;
    address public l2USDC;
    address public owner;
    bool public depositsPaused;

    event DepositsPaused();
    event GatewayUsdcBurned(uint256 amount);

    error L1USDCCustomGateway_DepositsAlreadyPaused();
    error L1USDCCustomGateway_DepositsPaused();
    error L1USDCCustomGateway_DepositsNotPaused();
    error L1USDCCustomGateway_InvalidL1USDC();
    error L1USDCCustomGateway_InvalidL2USDC();
    error L1USDCCustomGateway_NotOwner();
    error L1USDCCustomGateway_InvalidOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert L1USDCCustomGateway_NotOwner();
        }
        _;
    }

    function initialize(
        address _l2Counterpart,
        address _l1Router,
        address _inbox,
        address _l1USDC,
        address _l2USDC,
        address _owner
    ) public {
        if (_l1USDC == address(0)) {
            revert L1USDCCustomGateway_InvalidL1USDC();
        }
        if (_l2USDC == address(0)) {
            revert L1USDCCustomGateway_InvalidL2USDC();
        }
        if (_owner == address(0)) {
            revert L1USDCCustomGateway_InvalidOwner();
        }
        L1ArbitrumGateway._initialize(_l2Counterpart, _l1Router, _inbox);
        l1USDC = _l1USDC;
        l2USDC = _l2USDC;
        owner = _owner;
    }

    /**
     * @notice Pauses deposits and triggers a retryable ticket to pause withdrawals on the child chain.
     *         Pausing is permanent and can't be undone. Pausing is prerequisite for burning escrowed USDC tokens.
     * @param _maxGas Max gas for retryable ticket
     * @param _gasPriceBid Gas price for retryable ticket
     * @param _maxSubmissionCost Max submission cost for retryable ticket
     * @param _creditBackAddress Address to credit back on the child chain
     * @return seqNum Sequence number of the retryable ticket
     */
    function pauseDeposits(
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) external payable onlyOwner returns (uint256) {
        if (depositsPaused) {
            revert L1USDCCustomGateway_DepositsAlreadyPaused();
        }
        depositsPaused = true;

        emit DepositsPaused();

        // send retryable to pause withdrawals
        bytes memory _data = abi.encodeWithSelector(L2USDCCustomGateway.pauseWithdrawals.selector);
        return sendTxToL2CustomRefund({
            _inbox: inbox,
            _to: counterpartGateway,
            _refundTo: _creditBackAddress,
            _user: _creditBackAddress,
            _l1CallValue: msg.value,
            _l2CallValue: 0,
            _maxSubmissionCost: _maxSubmissionCost,
            _maxGas: _maxGas,
            _gasPriceBid: _gasPriceBid,
            _data: _data
        });
    }

    /**
     * @notice Burns the USDC tokens escrowed in the gateway.
     * @dev    Can be called by owner after deposits are paused.
     *         Function signature complies by Bridged USDC Standard.
     */
    function burnLockedUSDC() external onlyOwner {
        if (!depositsPaused) {
            revert L1USDCCustomGateway_DepositsNotPaused();
        }
        uint256 gatewayBalance = IERC20(l1USDC).balanceOf(address(this));
        Burnable(l1USDC).burn(gatewayBalance);

        emit GatewayUsdcBurned(gatewayBalance);
    }

    /**
     * @notice Sets a new owner.
     */
    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert L1USDCCustomGateway_InvalidOwner();
        }
        owner = newOwner;
    }

    /**
     * @inheritdoc IL1ArbitrumGateway
     */
    function outboundTransferCustomRefund(
        address _l1Token,
        address _refundTo,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) public payable override returns (bytes memory res) {
        if (depositsPaused) {
            revert L1USDCCustomGateway_DepositsPaused();
        }
        return super.outboundTransferCustomRefund(
            _l1Token, _refundTo, _to, _amount, _maxGas, _gasPriceBid, _data
        );
    }

    /**
     * @inheritdoc ITokenGateway
     */
    function calculateL2TokenAddress(address l1ERC20)
        public
        view
        override(ITokenGateway, TokenGateway)
        returns (address)
    {
        if (l1ERC20 != l1USDC) {
            // invalid L1 USDC address
            return address(0);
        }
        return l2USDC;
    }
}

interface Burnable {
    function burn(uint256 _amount) external;
}
