// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IMasterVaultFactory} from "../../libraries/vault/IMasterVaultFactory.sol";
import {IMasterVault} from "../../libraries/vault/IMasterVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Abstract contract inherited by all YBB gateways.
///         Inherited directly by L1YbbCustomGateway and L1OrbitYbbCustomGateway, 
///         and inherited indirectly by L1YbbERC20Gateway and L1OrbitYbbERC20Gateway through AbsYbbERC20Gateway.
///         Provides shared logic for initialization and escrow handling.
abstract contract AbsYbbGateway {
    using SafeERC20 for IERC20;

    /// @notice Address of the MasterVaultFactory contract
    address public masterVaultFactory;

    function _initialize(address _masterVaultFactory) internal {
        require(_masterVaultFactory != address(0), "AbsYbbGateway: BAD_MASTER_VAULT_FACTORY");
        require(masterVaultFactory == address(0), "AbsYbbGateway: ALREADY_INITIALIZED");
        masterVaultFactory = _masterVaultFactory;
    }

    function inboundEscrowTransfer(address _l1Token, address _dest, uint256 _amount)
        internal
        virtual
    {
        address masterVault = IMasterVaultFactory(masterVaultFactory).getVault(_l1Token);
        IERC20(masterVault).safeTransfer(_dest, _amount);
    }

    function outboundEscrowTransfer(address _l1Token, address _from, uint256 _amount)
        internal
        virtual
        returns (uint256 amountReceived)
    {
        uint256 prevBalance = IERC20(_l1Token).balanceOf(address(this));
        IERC20(_l1Token).safeTransferFrom(_from, address(this), _amount);
        uint256 postBalance = IERC20(_l1Token).balanceOf(address(this));
        uint256 underlyingReceived = postBalance - prevBalance;

        address masterVault = IMasterVaultFactory(masterVaultFactory).getVault(_l1Token);
        IERC20(_l1Token).safeIncreaseAllowance(masterVault, underlyingReceived);
        amountReceived = IMasterVault(masterVault).deposit(underlyingReceived);
        require(amountReceived > 0, "AbsYbbGateway: ZERO_SHARES");
    }
}