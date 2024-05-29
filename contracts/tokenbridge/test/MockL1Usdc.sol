// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

/**
 * @title Mock implementation of USDC used for testing custom USDC gateway
 */
contract MockL1Usdc is ERC20BurnableUpgradeable {
    address public owner;
    mapping(address => bool) public minters;

    function initialize() public initializer {
        __ERC20Burnable_init();
        __ERC20_init("Mock USDC", "MUSDC");
        owner = msg.sender;
        _mint(msg.sender, 1_000_000 ether);
    }

    function addMinter(address minter) external {
        if (msg.sender != owner) {
            revert("ONLY_OWNER");
        }
        minters[minter] = true;
    }

    function burn(uint256 value) public override {
        if (!minters[msg.sender]) {
            revert("ONLY_MINTER");
        }
        _burn(msg.sender, value);
    }

    function setOwner(address _owner) external {
        if (msg.sender != owner) {
            revert("ONLY_OWNER");
        }
        owner = _owner;
    }
}
