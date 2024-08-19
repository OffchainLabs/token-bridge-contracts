// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import {
    L1ArbitrumExtendedGateway,
    L1ArbitrumGateway,
    ITokenGateway,
    TokenGateway
} from "./L1ArbitrumExtendedGateway.sol";
import {IFiatToken, IFiatTokenProxy} from "../../libraries/IFiatToken.sol";

/**
 * @title Custom gateway for USDC implementing Bridged USDC Standard.
 * @notice Reference to the Circle's Bridged USDC Standard:
 *         https://github.com/circlefin/stablecoin-evm/blob/master/doc/bridged_USDC_standard.md
 *
 * @dev    This contract can be used on new Orbit chains which want to provide USDC
 *         bridging solution and keep the possibility to upgrade to native USDC at
 *         some point later. This solution will NOT be used in existing Arbitrum chains.
 *
 *         Child chain custom gateway to be used along this parent chain custom gateway is L2USDCGateway.
 *         This custom gateway differs from standard gateway in the following ways:
 *         - it supports a single parent chain - child chain USDC token pair
 *         - it is ownable
 *         - owner can pause and unpause deposits
 *         - owner can set a burner address
 *         - owner can set the amount of USDC tokens to be burned by burner. Owner is trusted to this correctly and not frontrun the burning.
 *         - burner can trigger burning the amount of USDC tokens locked in the gateway that matches the L2 supply
 *
 *         This contract is to be used on chains where ETH is the native token. If chain is using
 *         custom fee token then use L1OrbitUSDCGateway instead.
 *
 *         NOTE: before depositing funds, make sure that recipient address is not blacklisted on the child chain.
 *               Also, make sure that USDC token itself is not paused. Otherwise funds might get stuck.
 */
contract L1USDCGateway is L1ArbitrumExtendedGateway {
    address public l1USDC;
    address public l2USDC;
    address public owner;
    address public burner;
    bool public depositsPaused;
    uint256 public burnAmount;

    event DepositsPaused();
    event DepositsUnpaused();
    event GatewayUsdcBurned(uint256 amount);
    event BurnerSet(address indexed burner);
    event BurnAmountSet(uint256 amount);

    error L1USDCGateway_DepositsAlreadyPaused();
    error L1USDCGateway_DepositsAlreadyUnpaused();
    error L1USDCGateway_DepositsPaused();
    error L1USDCGateway_DepositsNotPaused();
    error L1USDCGateway_InvalidL1USDC();
    error L1USDCGateway_InvalidL2USDC();
    error L1USDCGateway_NotOwner();
    error L1USDCGateway_InvalidOwner();
    error L1USDCGateway_NotBurner();
    error L1USDCGateway_BurnAmountNotSet();

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert L1USDCGateway_NotOwner();
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
            revert L1USDCGateway_InvalidL1USDC();
        }
        if (_l2USDC == address(0)) {
            revert L1USDCGateway_InvalidL2USDC();
        }
        if (_owner == address(0)) {
            revert L1USDCGateway_InvalidOwner();
        }
        L1ArbitrumGateway._initialize(_l2Counterpart, _l1Router, _inbox);
        l1USDC = _l1USDC;
        l2USDC = _l2USDC;
        owner = _owner;
    }

    /**
     * @notice Pauses deposits. This can only be called by the owner.
     * @dev    Pausing is prerequisite for burning escrowed USDC tokens.  Incoming withdrawals are not affected.
     *         Pausing the withdrawals needs to be done separately on the child chain.
     */
    function pauseDeposits() external onlyOwner {
        if (depositsPaused) {
            revert L1USDCGateway_DepositsAlreadyPaused();
        }
        depositsPaused = true;

        emit DepositsPaused();
    }

    /**
     * @notice Unpauses deposits. This can only be called by the owner.
     */
    function unpauseDeposits() external onlyOwner {
        if (!depositsPaused) {
            revert L1USDCGateway_DepositsAlreadyUnpaused();
        }
        depositsPaused = false;

        emit DepositsUnpaused();
    }

    /**
     * @notice Owner sets a new burner.
     */
    function setBurner(address newBurner) external onlyOwner {
        burner = newBurner;
        emit BurnerSet(newBurner);
    }

    /**
     * @notice Owner sets the amount of USDC tokens to be burned by burner account.
     * @dev    This amount should match the L2 supply of bridged USDC. But it's not enforced, so burner
     *         should verify that correct amount is set before proceeding with burning.
     */
    function setBurnAmount(uint256 _burnAmount) external onlyOwner {
        burnAmount = _burnAmount;
        emit BurnAmountSet(_burnAmount);
    }

    /**
     * @notice Burns the USDC tokens escrowed in the gateway.
     * @dev    Can be called by burner when deposits are paused and when owner has set the burn amount.
     *         Owner is trusted to correctly set the burn amount and to not frontrun the burning by
     *         modifying the burn amount.
     *         Function signature complies by Bridged USDC Standard.
     */
    function burnLockedUSDC() external {
        if (msg.sender != burner) {
            revert L1USDCGateway_NotBurner();
        }
        if (!depositsPaused) {
            revert L1USDCGateway_DepositsNotPaused();
        }
        uint256 _burnAmount = burnAmount;
        if (_burnAmount == 0) {
            revert L1USDCGateway_BurnAmountNotSet();
        }

        burnAmount = 0;
        IFiatToken(l1USDC).burn(_burnAmount);
        emit GatewayUsdcBurned(_burnAmount);
    }

    /**
     * @notice Sets a new owner.
     */
    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert L1USDCGateway_InvalidOwner();
        }
        owner = newOwner;
    }

    /**
     * @notice entrypoint for depositing USDC, can be used only if deposits are not paused.
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
            revert L1USDCGateway_DepositsPaused();
        }
        return super.outboundTransferCustomRefund(
            _l1Token, _refundTo, _to, _amount, _maxGas, _gasPriceBid, _data
        );
    }

    /**
     * @notice only parent chain - child chain USDC token pair is supported
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
