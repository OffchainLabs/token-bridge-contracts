// SPDX-License-Identifier: MIT
// solhint-disable-next-line compiler-version
pragma solidity >0.6.0 <0.9.0;

/**
 * @title IFiatToken
 * @dev Part of the interface that is used in Circle's referent implementation of the USDC
 *      Ref: https://github.com/circlefin/stablecoin-evm
 *
 *      This interface is used in the L1USDCGateway, L1OrbitUSDCGateway and L2USDCGateway contracts.
 */
interface IFiatToken {
    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        string memory tokenCurrency,
        uint8 tokenDecimals,
        address newMasterMinter,
        address newPauser,
        address newBlacklister,
        address newOwner
    ) external;
    function initializeV2(string calldata newName) external;
    function initializeV2_1(address lostAndFound) external;
    function initializeV2_2(address[] calldata accountsToBlacklist, string calldata newSymbol)
        external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function burn(uint256 _amount) external;
    function mint(address _to, uint256 _amount) external;
}
