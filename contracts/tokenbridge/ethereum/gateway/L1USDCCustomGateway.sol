// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.4;

import "./L1ArbitrumExtendedGateway.sol";
import {L2USDCCustomGateway} from "../../arbitrum/gateway/L2USDCCustomGateway.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title Custom gateway for USDC bridging.
 */
contract L1USDCCustomGateway is L1ArbitrumExtendedGateway, OwnableUpgradeable {
    address public l1USDC;
    address public l2USDC;
    bool public depositsPaused;

    event DepositsPaused();
    event GatewayUsdcBurned(uint256 amount);

    error L1USDCCustomGateway_DepositsAlreadyPaused();
    error L1USDCCustomGateway_DepositsPaused();
    error L1USDCCustomGateway_DepositsNotPaused();

    function initialize(
        address _l2Counterpart,
        address _l1Router,
        address _inbox,
        address _l1USDC,
        address _l2USDC,
        address _owner
    ) public initializer {
        __Ownable_init();
        L1ArbitrumGateway._initialize(_l2Counterpart, _l1Router, _inbox);
        l1USDC = _l1USDC;
        l2USDC = _l2USDC;
        transferOwnership(_owner);
    }

    function burnLockedUSDC() external onlyOwner {
        if (!depositsPaused) {
            revert L1USDCCustomGateway_DepositsNotPaused();
        }
        uint256 gatewayBalance = IERC20(l1USDC).balanceOf(address(this));
        Burnable(l1USDC).burn(gatewayBalance);

        emit GatewayUsdcBurned(gatewayBalance);
    }

    function pauseDeposits(
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) external payable onlyOwner returns (uint256) {
        if (depositsPaused == true) {
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
