// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {AbsYbbGateway} from "./AbsYbbGateway.sol";
import {IMasterVaultFactory} from "../../libraries/vault/IMasterVaultFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITokenGateway} from "../../libraries/gateway/ITokenGateway.sol";
import {GatewayMessageHandler} from "../../libraries/gateway/GatewayMessageHandler.sol";
import {BytesParser} from "../../libraries/BytesParser.sol";

/// @notice Abstract contract inherited by L1OrbitYbbERC20Gateway and L1YbbERC20Gateway.
///         Provides shared logic for getOutboundCalldata and inherits escrow handling and slippage checking from AbsYbbGateway.
abstract contract AbsYbbERC20Gateway is AbsYbbGateway {
    address public owner;
    string public tokenNamePrefix;
    string public tokenNameSuffix;
    string public tokenSymbolPrefix;
    string public tokenSymbolSuffix;

    modifier onlyOwner() {
        require(msg.sender == owner, "AbsYbbERC20Gateway: NOT_OWNER");
        _;
    }

    function __AbsYbbERC20Gateway_init(address _masterVaultFactory, address _owner) internal {
        __AbsYbbGateway_init(_masterVaultFactory);
        require(_owner != address(0), "AbsYbbERC20Gateway: ZERO_OWNER");
        require(owner == address(0), "AbsYbbERC20Gateway: ALREADY_INITIALIZED");
        owner = _owner;
    }

    function setTokenPrefixSuffix(
        string calldata _namePrefix,
        string calldata _nameSuffix,
        string calldata _symbolPrefix,
        string calldata _symbolSuffix
    ) external onlyOwner {
        tokenNamePrefix = _namePrefix;
        tokenNameSuffix = _nameSuffix;
        tokenSymbolPrefix = _symbolPrefix;
        tokenSymbolSuffix = _symbolSuffix;
    }

    function getOutboundCalldata(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public virtual view returns (bytes memory outboundCalldata) {
        address vault = IMasterVaultFactory(masterVaultFactory).calculateVaultAddress(_token);

        bytes memory nameBytes = callStatic(_token, ERC20.name.selector);
        bytes memory symbolBytes = callStatic(_token, ERC20.symbol.selector);

        if (bytes(tokenNamePrefix).length > 0 || bytes(tokenNameSuffix).length > 0) {
            (, string memory name) = BytesParser.toString(nameBytes);
            nameBytes = abi.encode(string(abi.encodePacked(tokenNamePrefix, name, tokenNameSuffix)));
        }
        if (bytes(tokenSymbolPrefix).length > 0 || bytes(tokenSymbolSuffix).length > 0) {
            (, string memory symbol) = BytesParser.toString(symbolBytes);
            symbolBytes = abi.encode(string(abi.encodePacked(tokenSymbolPrefix, symbol, tokenSymbolSuffix)));
        }

        bytes memory deployData = abi.encode(
            nameBytes,
            symbolBytes,
            callStatic(vault, ERC20.decimals.selector)
        );

        outboundCalldata = abi.encodeWithSelector(
            ITokenGateway.finalizeInboundTransfer.selector,
            _token,
            _from,
            _to,
            _amount,
            GatewayMessageHandler.encodeToL2GatewayMsg(deployData, _data)
        );
    }

    function callStatic(address targetContract, bytes4 targetFunction)
        internal
        virtual
        view
        returns (bytes memory);
}