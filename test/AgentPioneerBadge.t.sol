// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AgentPioneerBadge} from "../src/AgentPioneerBadge.sol";

/// @notice Fork tests against the REAL Agent ID registry on BSC mainnet.
/// @dev Fork URL: https://bsc-dataseed.binance.org/ (public RPC).
contract AgentPioneerBadgeForkTest is Test {
    AgentPioneerBadge public badge;

    address public constant REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    /// @notice Known real Agent ID holder: handle "tony0x".
    address public constant HOLDER = 0x1b6996B2FD2c6Bd8C684e00426517aFCbaaDFbdf;
    address public constant NON_HOLDER = 0x000000000000000000000000000000000000dEaD;
    address public constant OTHER = 0x0000000000000000000000000000000000001234;

    uint256 public constant TONY0X_TOKEN_ID = uint256(keccak256(bytes("tony0x")));

    function setUp() public {
        vm.createSelectFork("bsc");
        badge = new AgentPioneerBadge(REGISTRY);
    }

    function test_claimSucceedsForRealHolder() public {
        vm.prank(HOLDER);
        uint256 tokenId = badge.claim();
        assertEq(tokenId, TONY0X_TOKEN_ID, "tokenId must be keccak256(handle)");
        assertEq(badge.ownerOf(tokenId), HOLDER);
        assertEq(badge.handleOfToken(tokenId), "tony0x");
        assertEq(badge.totalClaimed(), 1);
        assertEq(badge.balanceOf(HOLDER), 1);
        assertEq(badge.name(), "Agent Pioneer Badge");
        assertEq(badge.symbol(), "APB");
    }

    function test_claimEmitsEvent() public {
        vm.expectEmit(true, false, true, true, address(badge));
        emit AgentPioneerBadge.Claimed(HOLDER, "tony0x", TONY0X_TOKEN_ID);
        vm.prank(HOLDER);
        badge.claim();
    }

    function test_claimRevertsForNonHolder() public {
        vm.prank(NON_HOLDER);
        vm.expectRevert(AgentPioneerBadge.NotAgentIDHolder.selector);
        badge.claim();
    }

    function test_claimRevertsForZeroAddressCaller() public {
        // address(0) holds no Agent ID (handleOf returns "")
        vm.prank(address(0));
        vm.expectRevert(AgentPioneerBadge.NotAgentIDHolder.selector);
        badge.claim();
    }

    function test_doubleClaimReverts() public {
        vm.prank(HOLDER);
        badge.claim();
        vm.prank(HOLDER);
        vm.expectRevert(AgentPioneerBadge.AlreadyClaimed.selector);
        badge.claim();
    }

    function test_transferRevertsSoulbound() public {
        vm.prank(HOLDER);
        uint256 tokenId = badge.claim();
        vm.prank(HOLDER);
        vm.expectRevert(AgentPioneerBadge.Soulbound.selector);
        badge.transferFrom(HOLDER, OTHER, tokenId);
    }

    function test_safeTransferRevertsSoulbound() public {
        vm.prank(HOLDER);
        uint256 tokenId = badge.claim();
        vm.prank(HOLDER);
        vm.expectRevert(AgentPioneerBadge.Soulbound.selector);
        badge.safeTransferFrom(HOLDER, OTHER, tokenId);
    }

    function test_approveRevertsSoulbound() public {
        vm.prank(HOLDER);
        uint256 tokenId = badge.claim();
        vm.prank(HOLDER);
        vm.expectRevert(AgentPioneerBadge.Soulbound.selector);
        badge.approve(OTHER, tokenId);
    }

    function test_setApprovalForAllRevertsSoulbound() public {
        vm.prank(HOLDER);
        vm.expectRevert(AgentPioneerBadge.Soulbound.selector);
        badge.setApprovalForAll(OTHER, true);
    }

    function test_tokenURIIsValidBase64JsonWithHandle() public {
        vm.prank(HOLDER);
        uint256 tokenId = badge.claim();
        string memory uri = badge.tokenURI(tokenId);

        string memory prefix = "data:application/json;base64,";
        assertTrue(_startsWith(uri, prefix), "tokenURI must be a base64 data URI");
        bytes memory jsonBytes = _base64Decode(_slice(uri, bytes(prefix).length, bytes(uri).length));
        string memory json = string(jsonBytes);

        assertTrue(_contains(json, '"name":"Agent Pioneer Badge'), "name missing");
        assertTrue(_contains(json, "tony0x"), "handle missing from metadata");
        assertTrue(_contains(json, "no monetary value"), "no-value disclaimer missing");
        assertTrue(_contains(json, "data:image/svg+xml;base64,"), "SVG image missing");

        // The embedded SVG itself must render the handle.
        string memory svgB64 = _extractAfter(json, "data:image/svg+xml;base64,");
        svgB64 = _cutAt(svgB64, '"');
        string memory svg = string(_base64Decode(svgB64));
        assertTrue(_contains(svg, "tony0x"), "handle missing from SVG");
        assertTrue(_contains(svg, "AGENT PIONEER"), "title missing from SVG");
        assertTrue(_contains(svg, "BNB CHAIN"), "chain label missing from SVG");
    }

    function test_tokenURIRevertsForMissingToken() public {
        vm.expectRevert();
        badge.tokenURI(TONY0X_TOKEN_ID);
    }

    function test_pauseBlocksClaims() public {
        badge.pause();
        vm.prank(HOLDER);
        vm.expectRevert();
        badge.claim();
        badge.unpause();
        vm.prank(HOLDER);
        badge.claim();
        assertEq(badge.totalClaimed(), 1);
    }

    function test_onlyOwnerCanPause() public {
        vm.prank(OTHER);
        vm.expectRevert();
        badge.pause();
    }

    function test_claimGasEstimate() public {
        uint256 gasBefore = gasleft();
        vm.prank(HOLDER);
        badge.claim();
        uint256 gasUsed = gasBefore - gasleft();
        console.log("claim() gas (from test contract, incl. call overhead):", gasUsed);
    }

    // ---- helpers: base64 decode + string utils (test-only) ----

    function _base64Decode(string memory data) internal pure returns (bytes memory) {
        bytes memory b = bytes(data);
        require(b.length % 4 == 0, "bad b64 length");
        bytes memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 outLen = (b.length / 4) * 3;
        if (b[b.length - 1] == "=") outLen -= 1;
        if (b[b.length - 2] == "=") outLen -= 1;
        bytes memory out = new bytes(outLen);
        uint256 j;
        for (uint256 i = 0; i < b.length; i += 4) {
            uint256 n = (_b64Val(table, b[i]) << 18) | (_b64Val(table, b[i + 1]) << 12) | (_b64Val(table, b[i + 2]) << 6)
                | _b64Val(table, b[i + 3]);
            if (j < outLen) out[j++] = bytes1(uint8(n >> 16));
            if (j < outLen) out[j++] = bytes1(uint8(n >> 8));
            if (j < outLen) out[j++] = bytes1(uint8(n));
        }
        return out;
    }

    function _b64Val(bytes memory table, bytes1 c) internal pure returns (uint256) {
        if (c == "=") return 0;
        for (uint256 i = 0; i < 64; i++) {
            if (table[i] == c) return i;
        }
        revert("bad b64 char");
    }

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(prefix);
        if (a.length < b.length) return false;
        for (uint256 i = 0; i < b.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    function _contains(string memory s, string memory needle) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(needle);
        if (b.length == 0 || b.length > a.length) return false;
        for (uint256 i = 0; i + b.length <= a.length; i++) {
            bool found = true;
            for (uint256 k = 0; k < b.length; k++) {
                if (a[i + k] != b[k]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function _slice(string memory s, uint256 from, uint256 to) internal pure returns (string memory) {
        bytes memory a = bytes(s);
        bytes memory out = new bytes(to - from);
        for (uint256 i = from; i < to; i++) {
            out[i - from] = a[i];
        }
        return string(out);
    }

    function _extractAfter(string memory s, string memory marker) internal pure returns (string memory) {
        bytes memory a = bytes(s);
        bytes memory m = bytes(marker);
        for (uint256 i = 0; i + m.length <= a.length; i++) {
            bool found = true;
            for (uint256 k = 0; k < m.length; k++) {
                if (a[i + k] != m[k]) {
                    found = false;
                    break;
                }
            }
            if (found) return _slice(s, i + m.length, a.length);
        }
        revert("marker not found");
    }

    function _cutAt(string memory s, bytes1 stop) internal pure returns (string memory) {
        bytes memory a = bytes(s);
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] == stop) return _slice(s, 0, i);
        }
        return s;
    }
}
