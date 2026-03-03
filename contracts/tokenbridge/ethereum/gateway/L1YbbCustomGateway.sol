// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {L1CustomGateway} from "./L1CustomGateway.sol";
import {YbbVaultLib} from "../../libraries/vault/YbbVaultLib.sol";
import {IMasterVaultFactory} from "../../libraries/vault/IMasterVaultFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Layer 1 Gateway contract for bridging Custom ERC20s with YBB enabled
 * @notice Escrows funds into MasterVaults for yield bearing bridging.
 */
contract L1YbbCustomGateway is L1CustomGateway {
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
        YbbVaultLib.withdrawFromVault(masterVaultFactory, _l1Token, _dest, _amount);
    }

    function outboundEscrowTransfer(address _l1Token, address _from, uint256 _amount)
        internal
        override
        returns (uint256 amountReceived)
    {
        amountReceived = YbbVaultLib.depositToVault(masterVaultFactory, _l1Token, _from, _amount);
    }

    function _setMasterVaultFactory(address _masterVaultFactory) internal {
        require(_masterVaultFactory != address(0), "BAD_MASTER_VAULT_FACTORY");
        masterVaultFactory = _masterVaultFactory;
    }
}
