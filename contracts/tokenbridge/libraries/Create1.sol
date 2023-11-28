// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

/**
 * @dev Helper to make usage of the `CREATE1` EVM opcode easier and safer.
 *      Modified from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.8/contracts/utils/Create2.sol
 */
library Create1 {
    /**
     * @dev Deploys a contract using `CREATE`. The address where the contract
     * will be deployed can be known in advance via {computeAddress}.
     *
     * The bytecode for a contract can be obtained from Solidity with
     * `type(contractName).creationCode`.
     *
     * Requirements:
     *
     * - `bytecode` must not be empty.
     * - the factory must have a balance of at least `amount`.
     * - if `amount` is non-zero, `bytecode` must have a `payable` constructor.
     */
    function deploy(
        uint256 amount,
        bytes memory bytecode
    ) internal returns (address addr) {
        require(address(this).balance >= amount, "Create1: insufficient balance");
        require(bytecode.length != 0, "Create1: bytecode length is zero");
        /// @solidity memory-safe-assembly
        assembly {
            addr := create(amount, add(bytecode, 0x20), mload(bytecode))
        }
        require(addr != address(0), "Create1: Failed on deploy");
    }

    /**
     * @notice Compute address of contract deployed using CREATE opcode
     * @dev The contract address is derived by RLP encoding the deployer's address and the nonce using the Keccak-256 hashing algorithm.
     *      More formally: keccak256(rlp.encode([deployer, nonce])[12:]
     *
     *      First part of the function implementation does RLP encoding of [deployer, nonce].
     *        - nonce's prefix is encoded depending on its size -> 0x80 + lenInBytes(nonce)
     *        - deployer is 20 bytes long so its encoded prefix is 0x80 + 0x14 = 0x94
     *        - prefix of the whole list is 0xc0 + lenInBytes(RLP(list))
     *      After we have RLP encoding in place last step is to hash it, take last 20 bytes and cast is to an address.
     *
     * @return computed address
     */
    function computeAddress(address deployer, uint256 nonce) internal pure returns (address) {
        bytes memory data;
        if (nonce == 0x00) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, bytes1(0x80));
        } else if (nonce <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, uint8(nonce));
        } else if (nonce <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), deployer, bytes1(0x81), uint8(nonce));
        } else if (nonce <= 0xffff) {
            data = abi.encodePacked(bytes1(0xd8), bytes1(0x94), deployer, bytes1(0x82), uint16(nonce));
        } else if (nonce <= 0xffffff) {
            data = abi.encodePacked(bytes1(0xd9), bytes1(0x94), deployer, bytes1(0x83), uint24(nonce));
        } else {
            data = abi.encodePacked(bytes1(0xda), bytes1(0x94), deployer, bytes1(0x84), uint32(nonce));
        }
        return address(uint160(uint256(keccak256(data))));
    }
}
