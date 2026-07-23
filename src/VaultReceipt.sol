// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { ERC721URIStorage } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultReceipt is ERC721URIStorage, Ownable {
    constructor(address initialOwner) ERC721("GhostVault Release Receipt", "GHOST-KEY") Ownable(initialOwner) { }

    function mint(address beneficiary, uint256 vaultId, string calldata uri) external onlyOwner {
        _safeMint(beneficiary, vaultId);
        _setTokenURI(vaultId, uri);
    }

    function transferFrom(address, address, uint256) public pure override(ERC721, IERC721) {
        revert("receipt is soulbound");
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure override(ERC721, IERC721) {
        revert("receipt is soulbound");
    }
}
