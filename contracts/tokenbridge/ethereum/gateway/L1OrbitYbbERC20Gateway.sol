// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {L1OrbitERC20Gateway} from "./L1OrbitERC20Gateway.sol";
import {L1ERC20Gateway} from "./L1ERC20Gateway.sol";
import {IMasterVault} from "../../libraries/vault/IMasterVault.sol";
import {IMasterVaultFactory} from "../../libraries/vault/IMasterVaultFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Layer 1 Gateway contract for bridging standard ERC20s in ERC20-based rollups with YBB enabled
 * @notice Escrows funds into MasterVaults for yield bearing bridging.
 */
contract L1OrbitYbbERC20Gateway is L1OrbitERC20Gateway {
    using SafeERC20 for IERC20;

    /// @notice Address of the MasterVaultFactory contract
    address public masterVaultFactory;

    function initialize(
        address _l2Counterpart,
        address _router,
        address _inbox,
        bytes32 _cloneableProxyHash,
        address _l2BeaconProxyFactory,
        address _masterVaultFactory
    ) public {
        L1ERC20Gateway.initialize(
            _l2Counterpart, _router, _inbox, _cloneableProxyHash, _l2BeaconProxyFactory
        );
        _setMasterVaultFactory(_masterVaultFactory);
    }

    function inboundEscrowTransfer(address _l1Token, address _dest, uint256 _amount)
        internal
        override
    {
        address masterVault = IMasterVaultFactory(masterVaultFactory).getVault(_l1Token);
        uint256 assets = IMasterVault(masterVault).redeem(_amount, 0);
        IERC20(_l1Token).safeTransfer(_dest, assets);
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
        IERC20(_l1Token).safeApprove(masterVault, amountReceived);
        amountReceived = IMasterVault(masterVault).deposit(amountReceived);
    }

    function _setMasterVaultFactory(address _masterVaultFactory) internal {
        require(_masterVaultFactory != address(0), "BAD_MASTER_VAULT_FACTORY");
        masterVaultFactory = _masterVaultFactory;
    }
}
