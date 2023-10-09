// SPDX-License-Identifier: Apache-2.0

// solhint-disable-next-line compiler-version
pragma solidity >=0.6.9 <0.9.0;

interface IERC20Bridge {
    /**
     * @dev token that is escrowed in bridge on L1 side and minted on L2 as native currency. Also fees are paid in this token.
     */
    function nativeToken() external view returns (address);
}
