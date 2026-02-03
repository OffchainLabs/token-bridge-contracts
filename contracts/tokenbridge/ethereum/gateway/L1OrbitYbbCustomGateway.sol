// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import { L1OrbitCustomGateway } from "./L1OrbitCustomGateway.sol";
import { L1CustomGateway } from "./L1CustomGateway.sol";
import { IMasterVault } from "../../libraries/vault/IMasterVault.sol";
import { IMasterVaultFactory } from "../../libraries/vault/IMasterVaultFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Layer 1 Gateway contract for bridging custom ERC20s in ERC20-based rollups with YBB enabled
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
    ) public {
        L1CustomGateway.initialize(_l1Counterpart, _l1Router, _inbox, _owner);
        _setMasterVaultFactory(_masterVaultFactory);
    }

    function inboundEscrowTransfer(
        address _l1Token,
        address _dest,
        uint256 _amount
    ) internal override {
        address masterVault = IMasterVaultFactory(masterVaultFactory).getVault(_l1Token);
        uint256 assets = IMasterVault(masterVault).redeem(_amount, 0);
        IERC20(_l1Token).safeTransfer(_dest, assets);
    }

    function outboundEscrowTransfer(
        address _l1Token,
        address _from,
        uint256 _amount
    ) internal override returns (uint256 amountReceived) {
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
