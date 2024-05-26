// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20Upgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IArbToken} from "contracts/tokenbridge/arbitrum/IArbToken.sol";

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

contract MockL2Usdc is ERC20Upgradeable, IArbToken {
    address public l2Gateway;
    address public override l1Address;

    modifier onlyGateway() {
        require(msg.sender == l2Gateway, "ONLY_L2GATEWAY");
        _;
    }

    function initialize(address _l2Gateway, address _l1Address) public initializer {
        l2Gateway = _l2Gateway;
        l1Address = _l1Address;
        __ERC20_init("Mock L2 USDC", "L2MUSDC");
    }

    function bridgeMint(address account, uint256 amount) external virtual override onlyGateway {
        _mint(account, amount);
    }

    function bridgeBurn(address account, uint256 amount) external virtual override onlyGateway {
        _burn(account, amount);
    }
}
