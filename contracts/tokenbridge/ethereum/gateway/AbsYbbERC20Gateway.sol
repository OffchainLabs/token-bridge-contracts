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
    /// @notice Set once at initialization to the rollup's UpgradeExecutor and never changes.
    ///         No transfer or renounce path is provided by design.
    address public owner;
    string public tokenNamePrefix;
    string public tokenNameSuffix;
    string public tokenSymbolPrefix;
    string public tokenSymbolSuffix;

    event TokenPrefixSuffixSet(
        string namePrefix, string nameSuffix, string symbolPrefix, string symbolSuffix
    );

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

    /// @notice Set strings that wrap every subsequently-bridged token's L2 name and symbol.
    /// @dev    Changing prefix/suffix does NOT rename tokens that have already been bridged:
    ///         StandardArbERC20.bridgeInit runs only on the first deposit of a given L1 token,
    ///         so new values only apply to tokens bridged for the first time after this call.
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
        emit TokenPrefixSuffixSet(_namePrefix, _nameSuffix, _symbolPrefix, _symbolSuffix);
    }

    function getOutboundCalldata(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public virtual view returns (bytes memory outboundCalldata) {
        address vault = IMasterVaultFactory(masterVaultFactory).calculateVaultAddress(_token);

        bytes memory nameBytes = _applyPrefixSuffix(
            callStatic(_token, ERC20.name.selector), tokenNamePrefix, tokenNameSuffix
        );
        bytes memory symbolBytes = _applyPrefixSuffix(
            callStatic(_token, ERC20.symbol.selector), tokenSymbolPrefix, tokenSymbolSuffix
        );

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

    /// @dev If BytesParser.toString returns success=false (empty returndata from a failed
    ///      name()/symbol() call, or a non-null-terminated bytes32 return), the original
    ///      bytes pass through unchanged and the configured prefix/suffix is silently
    ///      skipped.
    function _applyPrefixSuffix(bytes memory data, string memory prefix, string memory suffix)
        private
        pure
        returns (bytes memory)
    {
        if (bytes(prefix).length == 0 && bytes(suffix).length == 0) {
            return data;
        }
        (bool parseSuccess, string memory value) = BytesParser.toString(data);
        if (!parseSuccess) {
            return data;
        }
        return abi.encode(string(abi.encodePacked(prefix, value, suffix)));
    }
}