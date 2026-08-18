// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

import "./L2ArbitrumGateway.sol";
import {IFiatToken, IFiatTokenProxy} from "../../ethereum/gateway/L1USDCGateway.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title  Child chain custom gateway for USDC implementing Bridged USDC Standard.
 * @notice Reference to the Circle's Bridged USDC Standard:
 *         https://github.com/circlefin/stablecoin-evm/blob/master/doc/bridged_USDC_standard.md
 *
 * @dev    This contract can be used on new Orbit chains which want to provide USDC
 *         bridging solution and keep the possibility to upgrade to native USDC at
 *         some point later. This solution will NOT be used in existing Arbitrum chains.
 *
 *         Parent chain custom gateway to be used along this child chain custom gateway is
 *         L1USDCGateway (when eth is used to pay fees) or L1OrbitUSDCGateway (when custom fee token is used).
 *         This custom gateway differs from standard gateway in the following ways:
 *         - it supports a single parent chain - child chain USDC token pair
 *         - it is ownable
 *         - withdrawals can be paused by the owner
 *         - owner can set an "transferrer" account which will be able to transfer USDC ownership
 *         - transferrer can transfer USDC owner and proxyAdmin
 *
 *         NOTE: before withdrawing funds, make sure that recipient address is not blacklisted on the parent chain.
 *               Also, make sure that USDC token itself is not paused. Otherwise funds might get stuck.
 */
contract L2USDCGateway is L2ArbitrumGateway {
    using SafeERC20 for IERC20;
    using Address for address;

    address public l1USDC;
    address public l2USDC;
    address public owner;
    address public usdcOwnershipTransferrer;
    bool public withdrawalsPaused;

    event WithdrawalsPaused();
    event WithdrawalsUnpaused();
    event OwnerSet(address indexed owner);
    event USDCOwnershipTransferrerSet(address indexed usdcOwnershipTransferrer);
    event USDCOwnershipTransferred(address indexed newOwner, address indexed newProxyAdmin);

    error L2USDCGateway_WithdrawalsAlreadyPaused();
    error L2USDCGateway_WithdrawalsAlreadyUnpaused();
    error L2USDCGateway_WithdrawalsPaused();
    error L2USDCGateway_InvalidL1USDC();
    error L2USDCGateway_InvalidL2USDC();
    error L2USDCGateway_NotOwner();
    error L2USDCGateway_InvalidOwner();
    error L2USDCGateway_NotUSDCOwnershipTransferrer();

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert L2USDCGateway_NotOwner();
        }
        _;
    }

    function initialize(
        address _l1Counterpart,
        address _router,
        address _l1USDC,
        address _l2USDC,
        address _owner
    ) public {
        if (_l1USDC == address(0)) {
            revert L2USDCGateway_InvalidL1USDC();
        }
        if (_l2USDC == address(0)) {
            revert L2USDCGateway_InvalidL2USDC();
        }
        if (_owner == address(0)) {
            revert L2USDCGateway_InvalidOwner();
        }
        L2ArbitrumGateway._initialize(_l1Counterpart, _router);
        l1USDC = _l1USDC;
        l2USDC = _l2USDC;
        owner = _owner;
    }

    /**
     * @notice Pause all withdrawals. This can only be called by the owner.
     */
    function pauseWithdrawals() external onlyOwner {
        if (withdrawalsPaused) {
            revert L2USDCGateway_WithdrawalsAlreadyPaused();
        }
        withdrawalsPaused = true;
        emit WithdrawalsPaused();
    }

    /**
     * @notice Unpause withdrawals. This can only be called by the owner.
     */
    function unpauseWithdrawals() external onlyOwner {
        if (!withdrawalsPaused) {
            revert L2USDCGateway_WithdrawalsAlreadyUnpaused();
        }
        withdrawalsPaused = false;
        emit WithdrawalsUnpaused();
    }

    /**
     * @notice Sets a new owner.
     */
    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert L2USDCGateway_InvalidOwner();
        }
        owner = newOwner;
        emit OwnerSet(newOwner);
    }

    /**
     * @notice Sets the account which is able to transfer USDC role away from the gateway to some other account.
     */
    function setUsdcOwnershipTransferrer(address _usdcOwnershipTransferrer) external onlyOwner {
        usdcOwnershipTransferrer = _usdcOwnershipTransferrer;
        emit USDCOwnershipTransferrerSet(_usdcOwnershipTransferrer);
    }

    /**
     * @notice In accordance with bridged USDC standard, the ownership of the USDC token contract is transferred
     *         to the new owner, and the proxy admin is transferred to the caller (usdcOwnershipTransferrer).
     * @dev    For transfer to be successful, this gateway should be both the owner and the proxy admin of L2 USDC token.
     */
    function transferUSDCRoles(address _owner) external {
        if (msg.sender != usdcOwnershipTransferrer) {
            revert L2USDCGateway_NotUSDCOwnershipTransferrer();
        }

        IFiatTokenProxy(l2USDC).changeAdmin(msg.sender);
        IFiatToken(l2USDC).transferOwnership(_owner);

        emit USDCOwnershipTransferred(_owner, msg.sender);
    }

    /**
     * @notice Entrypoint for withdrawing USDC, can be used only if withdrawals are not paused.
     */
    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        uint256, /* _maxGas */
        uint256, /* _gasPriceBid */
        bytes calldata _data
    ) public payable override returns (bytes memory res) {
        if (withdrawalsPaused) {
            revert L2USDCGateway_WithdrawalsPaused();
        }
        return super.outboundTransfer(_l1Token, _to, _amount, 0, 0, _data);
    }

    /**
     * @notice Only parent chain - child chain USDC token pair is supported
     */
    function calculateL2TokenAddress(address l1ERC20) public view override returns (address) {
        if (l1ERC20 != l1USDC) {
            // invalid L1 usdc address
            return address(0);
        }
        return l2USDC;
    }

    function inboundEscrowTransfer(address _l2Address, address _dest, uint256 _amount)
        internal
        override
    {
        IFiatToken(_l2Address).mint(_dest, _amount);
    }

    function outboundEscrowTransfer(address _l2Token, address _from, uint256 _amount)
        internal
        override
        returns (uint256)
    {
        // fetch the USDC tokens from the user and then burn them
        IERC20(_l2Token).safeTransferFrom(_from, address(this), _amount);
        IFiatToken(_l2Token).burn(_amount);

        return _amount;
    }

    /**
     * @notice Withdraw back the USDC if child chain side is not set up properly
     */
    function handleNoContract(
        address l1ERC20,
        address, /* expectedL2Address */
        address _from,
        address, /* _to */
        uint256 _amount,
        bytes memory /* deployData */
    ) internal override returns (bool shouldHalt) {
        // it is assumed that the custom token is deployed to child chain before deposits are made
        triggerWithdrawal(l1ERC20, address(this), _from, _amount, "");
        return true;
    }

    /**
     * @notice We need to override this function because base implementation assumes that L2 token implements
     *         `l1Address()` function from IArbToken interface. In the case of USDC gateway IArbToken logic is
     *         part of this contract, so we just check that addresses match the expected L1 and L2 USDC address.
     */
    function _isValidTokenAddress(address _l1Address, address _expectedL2Address)
        internal
        view
        override
        returns (bool)
    {
        return _l1Address == l1USDC && _expectedL2Address == l2USDC;
    }
}
