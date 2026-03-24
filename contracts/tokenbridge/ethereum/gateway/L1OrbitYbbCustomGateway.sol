// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import {L1OrbitCustomGateway} from "./L1OrbitCustomGateway.sol";
import {L1CustomGateway} from "./L1CustomGateway.sol";
import {L1ArbitrumGateway} from "./L1ArbitrumGateway.sol";
import {AbsYbbGateway} from "./AbsYbbGateway.sol";
import {IMasterVaultFactory} from "../../libraries/vault/IMasterVaultFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Layer 1 Gateway contract for bridging Custom ERC20s with YBB enabled in ERC20-based rollup
 * @notice Escrows funds into MasterVaults for yield bearing bridging.
 */
contract L1OrbitYbbCustomGateway is L1OrbitCustomGateway, AbsYbbGateway {
    function initialize(
        address _l1Counterpart,
        address _l1Router,
        address _inbox,
        address _owner,
        address _masterVaultFactory
    ) public virtual {
        L1CustomGateway.initialize(_l1Counterpart, _l1Router, _inbox, _owner);
        AbsYbbGateway._initialize(_masterVaultFactory);
    }

    function inboundEscrowTransfer(address _l1Token, address _dest, uint256 _amount)
        internal
        override(AbsYbbGateway, L1ArbitrumGateway)
    {
        AbsYbbGateway.inboundEscrowTransfer(_l1Token, _dest, _amount);
    }

    function outboundEscrowTransfer(address _l1Token, address _from, uint256 _amount)
        internal
        override(AbsYbbGateway, L1ArbitrumGateway)
        returns (uint256 amountReceived)
    {
        return AbsYbbGateway.outboundEscrowTransfer(_l1Token, _from, _amount);
    }
}
