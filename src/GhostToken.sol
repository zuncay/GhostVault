// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract GhostToken is ERC20, Ownable {
    uint256 public constant FAUCET_AMOUNT = 1_000 ether;
    mapping(address => bool) public faucetClaimed;

    constructor(address initialOwner) ERC20("Ghost Vault Asset", "GHOST") Ownable(initialOwner) {
        _mint(initialOwner, 1_000_000 ether);
    }

    function claimFaucet() external {
        require(!faucetClaimed[msg.sender], "faucet already claimed");
        faucetClaimed[msg.sender] = true;
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}

