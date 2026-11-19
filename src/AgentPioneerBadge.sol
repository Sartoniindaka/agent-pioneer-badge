// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Minimal view of the SPACE ID Agent ID registry (BNB Chain).
/// @dev balanceOf(address) > 0 means the address holds an Agent ID.
///      handleOf(address) returns the handle string (empty for non-holders).
interface IAgentIDRegistry {
    function handleOf(address account) external view returns (string memory);
    function balanceOf(address account) external view returns (uint256);
}

/// @title Agent Pioneer Badge
/// @notice Free, soulbound (non-transferable) ERC-721 badge for Agent ID holders.
///         One badge per Agent ID: the tokenId is uint256(keccak256(bytes(handle))),
///         the same scheme the Agent ID registry itself uses, so a handle can never
///         hold two badges. Claiming is free — the caller only pays gas.
/// @dev Owner permissions (disclosed): the owner can ONLY pause() / unpause()
///      claiming (Ownable2Step + Pausable). There is no mint, burn, transfer,
///      fee, or fund-withdrawal power. The contract holds no funds.
contract AgentPioneerBadge is ERC721, Ownable2Step, Pausable {
    IAgentIDRegistry public immutable registry;

    /// @notice Number of badges claimed so far.
    uint256 public totalClaimed;

    /// @notice handle stored per tokenId (the handle cannot be recovered from
    ///         the keccak256 tokenId, so it is stored at claim time).
    mapping(uint256 => string) private _handles;

    event Claimed(address indexed holder, string handle, uint256 indexed tokenId);

    error NotAgentIDHolder();
    error AlreadyClaimed();
    error Soulbound();

    constructor(address registry_) ERC721("Agent Pioneer Badge", "APB") Ownable(msg.sender) {
        registry = IAgentIDRegistry(registry_);
    }

    /// @notice Claim the free badge for the caller's Agent ID.
    /// @dev Reverts when the caller holds no Agent ID, or when this handle
    ///      already claimed (the token already exists).
    function claim() external whenNotPaused returns (uint256 tokenId) {
        string memory handle = registry.handleOf(msg.sender);
        if (bytes(handle).length == 0) revert NotAgentIDHolder();
        tokenId = uint256(keccak256(bytes(handle)));
        if (_ownerOf(tokenId) != address(0)) revert AlreadyClaimed();
        _handles[tokenId] = handle;
        unchecked {
            ++totalClaimed;
        }
        _mint(msg.sender, tokenId);
        emit Claimed(msg.sender, handle, tokenId);
    }

    /// @notice The Agent ID handle bound to a badge tokenId.
    function handleOfToken(uint256 tokenId) external view returns (string memory) {
        _requireOwned(tokenId);
        return _handles[tokenId];
    }

    /// @notice Fully on-chain metadata: Base64 data-URI JSON with an on-chain SVG.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        address holder = _requireOwned(tokenId);
        string memory handle = _handles[tokenId];

        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">',
            '<rect width="512" height="512" fill="#0b0e1a"/>',
            '<rect x="24" y="24" width="464" height="464" rx="24" fill="none" stroke="#f0b90b" stroke-width="4"/>',
            '<text x="256" y="150" font-family="monospace" font-size="34" fill="#f0b90b" text-anchor="middle">AGENT PIONEER</text>',
            '<text x="256" y="268" font-family="monospace" font-size="52" font-weight="bold" fill="#ffffff" text-anchor="middle">',
            handle,
            '</text>',
            '<text x="256" y="330" font-family="monospace" font-size="24" fill="#8a8fa3" text-anchor="middle">AGENT ID HOLDER</text>',
            '<text x="256" y="430" font-family="monospace" font-size="22" fill="#8a8fa3" text-anchor="middle">BNB CHAIN</text>',
            "</svg>"
        );

        string memory json = Base64.encode(
            bytes(
                string.concat(
                    '{"name":"Agent Pioneer Badge \u2014 ',
                    handle,
                    '",',
                    '"description":"A free, non-transferable identity badge for Agent ID holders on BNB Chain. ',
                    "It proves the holder owned an Agent ID at claim time. ",
                    "It has no monetary value and promises no returns.", '",',
                    '"image":"data:image/svg+xml;base64,',
                    Base64.encode(bytes(svg)),
                    '",',
                    '"attributes":[{"trait_type":"Handle","value":"',
                    handle,
                    '"},{"trait_type":"Holder","value":"',
                    Strings.toHexString(holder),
                    '"},{"trait_type":"Transferable","value":"No"}]}'
                )
            )
        );
        return string.concat("data:application/json;base64,", json);
    }

    /// @notice Pause claiming (owner only). Existing badges are unaffected.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume claiming (owner only).
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Soulbound: a token can only ever be minted, never moved.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }
}
