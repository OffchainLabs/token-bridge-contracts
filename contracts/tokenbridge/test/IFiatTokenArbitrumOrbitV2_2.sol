// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

interface IFiatTokenArbitrumOrbitV2_2 {
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
    function initializeArbitrumOrbit(address _l2Gateway, address _l1Token) external;
}
