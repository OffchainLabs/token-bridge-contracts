// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {L1OrbitCustomGateway} from "./L1OrbitCustomGateway.sol";
import {L1CustomGateway} from "./L1CustomGateway.sol";
import {IMasterVault} from "../../libraries/vault/IMasterVault.sol";
import {IMasterVaultFactory} from "../../libraries/vault/IMasterVaultFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Layer 1 Gateway contract for bridging Custom ERC20s with YBB enabled in ERC20-based rollup
 * @notice Escrows funds into MasterVaults for yield bearing bridging.
 */
contract L1OrbitYbbCustomGateway is L1OrbitCustomGateway {
    using SafeERC20 for IERC20;

    /// @notice Address of the MasterVaultFactory contract
    address public masterVaultFactory;

    function initialize(
        address _l1Counterpart,
        address _l1Router,
        address _inbox,
        address _owner,
        address _masterVaultFactory
    ) public virtual {
        L1CustomGateway.initialize(_l1Counterpart, _l1Router, _inbox, _owner);
        _setMasterVaultFactory(_masterVaultFactory);
    }

    function inboundEscrowTransfer(address _l1Token, address _dest, uint256 _amount)
        internal
        override
    {
        address masterVault = IMasterVaultFactory(masterVaultFactory).getVault(_l1Token);
        IERC20(masterVault).safeTransfer(_dest, _amount);
    }

    function outboundEscrowTransfer(address _l1Token, address _from, uint256 _amount)
        internal
        override
        returns (uint256 amountReceived)
    {
        uint256 prevBalance = IERC20(_l1Token).balanceOf(address(this));
        IERC20(_l1Token).safeTransferFrom(_from, address(this), _amount);
        uint256 postBalance = IERC20(_l1Token).balanceOf(address(this));
        amountReceived = postBalance - prevBalance;

        address masterVault = IMasterVaultFactory(masterVaultFactory).getVault(_l1Token);
        IERC20(_l1Token).safeIncreaseAllowance(masterVault, amountReceived);
        amountReceived = IMasterVault(masterVault).deposit(amountReceived);
        require(amountReceived > 0, "ZERO_SHARES");
    }

    function _setMasterVaultFactory(address _masterVaultFactory) internal {
        require(_masterVaultFactory != address(0), "BAD_MASTER_VAULT_FACTORY");
        masterVaultFactory = _masterVaultFactory;
    }
}
