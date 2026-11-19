// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentPioneerBadge} from "../src/AgentPioneerBadge.sol";

/// @notice Deploy AgentPioneerBadge to BNB Chain mainnet (chainId 56).
/// @dev DO NOT run with --broadcast without the owner's explicit confirmation.
///      Dry run (simulation only, no transaction is sent):
///        forge script script/Deploy.s.sol --rpc-url bsc -vvvv
///      Real deploy (owner confirms first; needs BNB for gas in the deployer):
///        forge script script/Deploy.s.sol --rpc-url bsc --broadcast \
///          --private-key $DEPLOYER_PK --slow
///      Verification (after deploy, same compiler settings as foundry.toml):
///        forge verify-contract <address> src/AgentPioneerBadge.sol:AgentPioneerBadge \
///          --chain 56 --compiler-version v0.8.24+commit.e11b9ed9 \
///          --optimizer-runs 200 \
///          --constructor-args $(cast abi-encode "constructor(address)" 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F)
contract Deploy is Script {
    address public constant REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    function run() external returns (AgentPioneerBadge badge) {
        vm.startBroadcast();
        badge = new AgentPioneerBadge(REGISTRY);
        vm.stopBroadcast();
        console.log("AgentPioneerBadge deployed at:", address(badge));
        console.log("Agent ID registry:      ", REGISTRY);
        console.log("Owner (deployer):       ", badge.owner());
        console.log("Name / symbol:          ", badge.name(), "/", badge.symbol());
    }
}
