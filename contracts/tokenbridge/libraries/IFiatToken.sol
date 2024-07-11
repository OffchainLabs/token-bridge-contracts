// SPDX-License-Identifier: MIT
// solhint-disable-next-line compiler-version
pragma solidity >0.6.0 <0.9.0;

/**
 * @title IFiatToken
 * @dev Interface contains functions from Circle's referent implementation of the USDC
 *      Ref: https://github.com/circlefin/stablecoin-evm
 *
 *      This interface is used in the L1USDCGateway, L1OrbitUSDCGateway and L2USDCGateway contracts.
 */
interface IFiatToken {
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function blacklist(address _account) external;
    function blacklister() external view returns (address);
    function burn(uint256 _amount) external;
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s)
        external;
    function cancelAuthorization(address authorizer, bytes32 nonce, bytes memory signature)
        external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool);
    function currency() external view returns (string memory);
    function decimals() external view returns (uint8);
    function decreaseAllowance(address spender, uint256 decrement) external returns (bool);
    function increaseAllowance(address spender, uint256 increment) external returns (bool);
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
    function initializeV2(string memory newName) external;
    function initializeV2_1(address lostAndFound) external;
    function initializeV2_2(address[] memory accountsToBlacklist, string memory newSymbol)
        external;
    function isBlacklisted(address _account) external view returns (bool);
    function isMinter(address account) external view returns (bool);
    function masterMinter() external view returns (address);
    function mint(address _to, uint256 _amount) external returns (bool);
    function minterAllowance(address minter) external view returns (uint256);
    function name() external view returns (string memory);
    function nonces(address owner) external view returns (uint256);
    function owner() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function pauser() external view returns (address);
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    ) external;
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external;
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function removeMinter(address minter) external returns (bool);
    function rescueERC20(address tokenContract, address to, uint256 amount) external;
    function rescuer() external view returns (address);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transferOwnership(address newOwner) external;
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) external;
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function unBlacklist(address _account) external;
    function unpause() external;
    function updateBlacklister(address _newBlacklister) external;
    function updateMasterMinter(address _newMasterMinter) external;
    function updatePauser(address _newPauser) external;
    function updateRescuer(address newRescuer) external;
    function version() external pure returns (string memory);
}

/**
 * @title IFiatTokenProxy
 * @dev Interface contains functions from Circle's referent implementation of the USDC proxy
 *      Ref: https://github.com/circlefin/stablecoin-evm
 *
 *      This interface is used in the L1USDCGateway, L1OrbitUSDCGateway and L2USDCGateway contracts.
 */
interface IFiatTokenProxy {
    function admin() external view returns (address);
    function changeAdmin(address newAdmin) external;
    function implementation() external view returns (address);
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}
