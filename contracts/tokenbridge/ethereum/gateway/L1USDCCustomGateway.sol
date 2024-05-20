// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./L1ArbitrumExtendedGateway.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title Custom gateway for USDC bridging.
 */
contract L1USDCCustomGateway is L1ArbitrumExtendedGateway, OwnableUpgradeable {
    address public l1USDC;
    address public l2USDC;

    function initialize(
        address _l2Counterpart,
        address _l1Router,
        address _inbox,
        address _l1USDC,
        address _l2USDC,
        address _owner
    ) public {
        L1ArbitrumGateway._initialize(_l2Counterpart, _l1Router, _inbox);
        l1USDC = _l1USDC;
        l2USDC = _l2USDC;
        __Ownable_init();
        transferOwnership(_owner);
    }

    /**
     * @notice Calculate the address used when bridging an ERC20 token
     * @dev the L1 and L2 address oracles may not always be in sync.
     * For example, a custom token may have been registered but not deploy or the contract self destructed.
     * @param l1ERC20 address of L1 token
     * @return L2 address of a bridged ERC20 token
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

    function burnLockedUSDC() external onlyOwner {
        uint256 gatewayBalance = IERC20(l1USDC).balanceOf(address(this));
        Burnable(l1USDC).burn(gatewayBalance);
    }
}

interface Burnable {
    function burn(uint256 _amount) external;
}
