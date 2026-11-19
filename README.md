# Agent Pioneer Badge

A free, soulbound (non-transferable) ERC-721 badge for Agent ID holders on
BNB Chain — built for the Binance Agent ID Hackathon (submission closes
2026-12-09 08:00 UTC).

## What it does

Any wallet that holds an Agent ID can claim exactly one badge, free (gas
only). The badge is bound to the holder's Agent ID handle: the tokenId is
`uint256(keccak256(bytes(handle)))`, the same scheme the Agent ID registry
itself uses, so a handle can never hold two badges. Metadata and artwork are
fully on-chain — `tokenURI` returns a Base64 data-URI JSON with an SVG that
renders the holder's handle. The badge has no monetary value and promises no
returns.

## How Agent ID is used

- **Access control:** `claim()` reads `handleOf(msg.sender)` on the Agent ID
  registry and reverts for non-holders (`NotAgentIDHolder`).
- **Identity:** the badge tokenId and its on-chain metadata are derived from
  the holder's Agent ID handle, so the badge *is* the holder's Agent ID
  identity, as an NFT.
- **One per Agent ID:** enforced by the tokenId scheme plus an
  `AlreadyClaimed` check.

## Contracts (BNB Chain, chainId 56)

| Contract | Address |
| --- | --- |
| Agent ID registry (SPACE ID Agent ID) | `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` |
| Agent Pioneer Badge | TBD — not deployed yet |

## Owner permissions (disclosed)

The badge contract owner can **only** `pause()` / `unpause()` claiming
(`Ownable2Step` + `Pausable`). There is no mint, burn, transfer, fee, or
fund-withdrawal power, and the contract holds no funds.

## Hackathon red-line compliance

- No web QR-code login for Agentic Wallet; the site uses an injected wallet
  only, no sessions stored anywhere.
- No prompts that bypass user transaction confirmation; claiming is a normal
  wallet transaction the user reviews and confirms.
- No unauthorized transfers; the badge is soulbound (transfers and approvals
  revert) and claiming moves no assets.
- Contract is open-source (MIT) with the owner permissions above.
- No "Binance" / "BNB" in the project, token, or domain names.
- Never collects seed phrases, private keys, API secrets, or pairing codes.
- Promises no returns; the badge is free and has no monetary value.
- The site only ever shows the *connected* wallet's own handle and badge —
  it is not a tool for looking up other people's wallets by name.

## Site

`site/` is a static page (no build step, no server): connect an injected
wallet, check eligibility live against the registry, claim the badge, and view
it. Hosted on GitHub Pages once the contract is deployed.

## Develop

```shell
forge build
forge test   # 14 tests, run against a BSC mainnet fork (real registry)
```

Compiler: solc 0.8.24, optimizer on, 200 runs, EVM Cancun (see
`foundry.toml`; BscScan verification must use these exact settings).

## Deploy

Deploy needs ~2,457,288 gas (simulation on a BSC fork). Two paths:

**Forge script** (needs a deployer private key — not the Binance keyless
wallet path):

```shell
forge script script/Deploy.s.sol --rpc-url bsc --broadcast --private-key $DEPLOYER_PK --slow
```

**Remix** (Binance Wallet in the browser signs the deployment):

1. Open [Remix](https://remix.ethereum.org/), create
   `AgentPioneerBadge.sol`, paste `remix/AgentPioneerBadge.flattened.sol`.
2. Compile with 0.8.24, optimizer ON, 200 runs, EVM Cancun.
3. Deploy with constructor argument `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`
   (the Agent ID registry), connected to BNB Chain mainnet.
4. Verify on BscScan with the same compiler settings and the constructor
   argument above (see the verify command in `script/Deploy.s.sol`).

## License

MIT
