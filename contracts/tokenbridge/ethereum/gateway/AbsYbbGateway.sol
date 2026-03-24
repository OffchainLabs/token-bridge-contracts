// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

abstract contract AbsYbbGateway {
    /// @notice Address of the MasterVaultFactory contract
    address public masterVaultFactory;

    function _initialize(address _masterVaultFactory) internal {
        require(_masterVaultFactory != address(0), "BAD_MASTER_VAULT_FACTORY");
        masterVaultFactory = _masterVaultFactory;
    }
}