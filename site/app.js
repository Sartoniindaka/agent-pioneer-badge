// Agent Pioneer Badge — claim site.
// Static page, no build step, no server. Talks only to the injected wallet
// (window.ethereum) and the BNB Chain public RPC through it.
// RED LINES, by design:
//  - No QR-code login, no pairing codes, no sessions stored anywhere.
//  - The user confirms every transaction in their own wallet; nothing is
//    sent until they approve it. The claim costs 0 value (gas only).
//  - The page only ever shows the CONNECTED wallet's own handle and badge.
//    There is no input to look up any other handle or wallet.

"use strict";

// FILL IN AFTER DEPLOYMENT (leave "" until the contract is live on BNB Chain).
const BADGE_CONTRACT = "";
const REGISTRY = "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F";
const BSC_CHAIN_ID = 56; // 0x38
const BSCSCAN = "https://bscscan.com/address/";

// Function selectors (verified with `cast sig`):
const SEL_BALANCE_OF = "0x70a08231"; // balanceOf(address)
const SEL_HANDLE_OF = "0xc50a1514"; // handleOf(address)
const SEL_CLAIM = "0x4e71d92d"; // claim()
const SEL_TOKEN_URI = "0xc87b56dd"; // tokenURI(uint256)
const SEL_TOTAL_CLAIMED = "0xd54ad2a1"; // totalClaimed()

const $ = (id) => document.getElementById(id);
let account = null;

function hexPadAddress(addr) {
  return "000000000000000000000000" + addr.slice(2).toLowerCase();
}

async function ethCall(to, data) {
  return window.ethereum.request({
    method: "eth_call",
    params: [{ to, data }, "latest"],
  });
}

// Decode a single ABI-encoded string return value (offset, length, bytes).
function decodeAbiString(hex) {
  const b = hex.startsWith("0x") ? hex.slice(2) : hex;
  const bytes = new Uint8Array(b.match(/.{1,2}/g).map((x) => parseInt(x, 16)));
  const view = new DataView(bytes.buffer);
  const len = Number(view.getBigUint64(32 + 24)); // length word at offset 32
  const start = 64;
  return new TextDecoder().decode(bytes.slice(start, start + len));
}

function decodeUint256(hex) {
  return BigInt(hex);
}

async function refreshTotalClaimed() {
  if (!BADGE_CONTRACT) {
    $("totalClaimed").textContent = "—";
    return;
  }
  try {
    const raw = await ethCall(BADGE_CONTRACT, SEL_TOTAL_CLAIMED);
    $("totalClaimed").textContent = decodeUint256(raw).toString();
  } catch (e) {
    $("totalClaimed").textContent = "—";
  }
}

async function refreshEligibility() {
  const elig = $("eligLine");
  const handleLine = $("handleLine");
  const claimBtn = $("claimBtn");
  claimBtn.disabled = true;
  $("gasLine").textContent = "";
  if (!account) {
    elig.textContent = "Connect your wallet to see whether it holds an Agent ID.";
    handleLine.textContent = "";
    return;
  }
  try {
    const balRaw = await ethCall(REGISTRY, SEL_BALANCE_OF + hexPadAddress(account));
    const bal = decodeUint256(balRaw);
    if (bal === 0n) {
      elig.innerHTML = '<span class="err">This wallet holds no Agent ID.</span> Only Agent ID holders can claim the badge.';
      handleLine.textContent = "";
      return;
    }
    const handle = decodeAbiString(await ethCall(REGISTRY, SEL_HANDLE_OF + hexPadAddress(account)));
    elig.innerHTML = '<span class="ok">Eligible.</span> This wallet holds Agent ID <b>' + escapeHtml(handle) + '</b>.';
    handleLine.textContent = "handle: " + handle + "  ·  wallet: " + account;
    if (!BADGE_CONTRACT) {
      elig.textContent += " The badge contract is not deployed yet.";
      return;
    }
    // Already claimed? tokenURI reverts when the token does not exist.
    const tokenId = await tokenIdForHandle(handle);
    try {
      const uri = decodeAbiString(await ethCall(BADGE_CONTRACT, SEL_TOKEN_URI + tokenIdHex(tokenId)));
      showBadge(uri, tokenId);
      elig.innerHTML += " You already claimed your badge — it is shown below.";
    } catch (e) {
      claimBtn.disabled = false;
      await estimateClaimGas();
    }
  } catch (e) {
    elig.textContent = "Could not check eligibility: " + (e && e.message ? e.message : e);
  }
}

function tokenIdHex(tokenId) {
  return tokenId.toString(16).padStart(64, "0");
}

async function tokenIdForHandle(handle) {
  // keccak256(bytes(handle)) via the wallet: use eth_call to the registry's
  // ownerOfHandle? No — simplest reliable path: keccak in JS.
  // We implement keccak-256 in pure JS below (tiny, no dependency).
  return BigInt("0x" + keccak256Hex(new TextEncoder().encode(handle)));
}

async function estimateClaimGas() {
  if (!BADGE_CONTRACT || !account) return;
  try {
    const gas = await window.ethereum.request({
      method: "eth_estimateGas",
      params: [{ from: account, to: BADGE_CONTRACT, data: SEL_CLAIM, value: "0x0" }],
    });
    const gasPrice = await window.ethereum.request({ method: "eth_gasPrice" });
    const costWei = BigInt(gas) * BigInt(gasPrice);
    const costBnb = Number(costWei) / 1e18;
    $("gasLine").textContent =
      "estimated gas: " + BigInt(gas).toString() + "  ·  ≈ " + costBnb.toFixed(6) + " BNB  ·  value: 0 (free)";
  } catch (e) {
    $("gasLine").textContent = "gas estimate unavailable — your wallet will show it before you confirm.";
  }
}

function showBadge(uri, tokenId) {
  const prefix = "data:application/json;base64,";
  if (!uri.startsWith(prefix)) return;
  let meta;
  try {
    meta = JSON.parse(atob(uri.slice(prefix.length)));
  } catch (e) {
    return;
  }
  $("badgeCard").hidden = false;
  if (meta.image) $("badgeImg").src = meta.image;
  $("badgeMeta").textContent = (meta.name || "") + "  ·  tokenId " + tokenId.toString();
  $("badgeBscScan").href = BSCSCAN + BADGE_CONTRACT + "#readContract";
}

async function claim() {
  const status = $("claimStatus");
  if (!BADGE_CONTRACT || !account) return;
  $("claimBtn").disabled = true;
  status.textContent = "Waiting for you to confirm the transaction in your wallet…";
  try {
    const txHash = await window.ethereum.request({
      method: "eth_sendTransaction",
      params: [{ from: account, to: BADGE_CONTRACT, data: SEL_CLAIM, value: "0x0" }],
    });
    status.textContent = "Transaction sent: " + txHash + " — waiting for confirmation…";
    let receipt = null;
    for (let i = 0; i < 60; i++) {
      await new Promise((r) => setTimeout(r, 2000));
      receipt = await window.ethereum.request({ method: "eth_getTransactionReceipt", params: [txHash] });
      if (receipt) break;
    }
    if (!receipt) {
      status.textContent = "Still waiting for confirmation. Check the transaction on BscScan: " + txHash;
      return;
    }
    if (receipt.status !== "0x1") {
      status.innerHTML = '<span class="err">Transaction failed.</span> See BscScan for details: ' + escapeHtml(txHash);
      $("claimBtn").disabled = false;
      return;
    }
    status.innerHTML = '<span class="ok">Badge claimed!</span> Transaction: ' + escapeHtml(txHash);
    // The Claimed event's tokenId is topic[2] of the first log from the badge contract.
    const log = (receipt.logs || []).find((l) => l.address && l.address.toLowerCase() === BADGE_CONTRACT.toLowerCase());
    if (log && log.topics && log.topics[2]) {
      const tokenId = BigInt(log.topics[2]);
      try {
        const uri = decodeAbiString(await ethCall(BADGE_CONTRACT, SEL_TOKEN_URI + tokenIdHex(tokenId)));
        showBadge(uri, tokenId);
      } catch (e) { /* badge shows after a refresh */ }
    }
    await refreshEligibility();
    await refreshTotalClaimed();
  } catch (e) {
    status.textContent = "Claim cancelled or failed: " + (e && e.message ? e.message : e);
    $("claimBtn").disabled = false;
  }
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

async function connect() {
  if (!window.ethereum) {
    $("accountLine").textContent = "No injected wallet found. Open this page in Binance Wallet or MetaMask.";
    return;
  }
  try {
    const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
    account = accounts[0];
    $("accountLine").textContent = account;
    const chainIdHex = await window.ethereum.request({ method: "eth_chainId" });
    const chainId = parseInt(chainIdHex, 16);
    if (chainId !== BSC_CHAIN_ID) {
      $("chainLine").innerHTML =
        '<span class="warn">You are on chain ' + chainId + ', not BNB Chain (56).</span> ';
      const switchBtn = document.createElement("button");
      switchBtn.className = "secondary";
      switchBtn.textContent = "Switch to BNB Chain";
      switchBtn.onclick = async () => {
        try {
          await window.ethereum.request({
            method: "wallet_switchEthereumChain",
            params: [{ chainId: "0x38" }],
          });
          $("chainLine").textContent = "On BNB Chain (56).";
        } catch (e) {
          $("chainLine").textContent = "Could not switch networks: " + (e && e.message ? e.message : e);
        }
      };
      $("chainLine").appendChild(switchBtn);
    } else {
      $("chainLine").textContent = "On BNB Chain (56).";
    }
    await refreshEligibility();
  } catch (e) {
    $("accountLine").textContent = "Connection cancelled or failed: " + (e && e.message ? e.message : e);
  }
}

// Minimal keccak-256 (pure JS, no dependency) — needed to compute
// tokenId = uint256(keccak256(bytes(handle))) for the eligibility check.
function keccak256Hex(bytes) {
  const MASK = (1n << 64n) - 1n;
  const R64 = [
    [0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61],
    [28, 55, 25, 21, 56], [27, 20, 39, 8, 14],
  ];
  const RC64 = [
    0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an,
    0x8000000080008000n, 0x000000000000808bn, 0x0000000080000001n,
    0x8000000080008081n, 0x8000000000008009n, 0x000000000000008an,
    0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
    0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n,
    0x8000000000008003n, 0x8000000000008002n, 0x8000000000000080n,
    0x000000000000800an, 0x800000008000000an, 0x8000000080008081n,
    0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
  ];
  const PI = [10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1];
  function rotl64(x, n) { n = BigInt(n); return ((x << n) | (x >> (64n - n))) & MASK; }
  function keccakF(state) {
    for (let round = 0; round < 24; round++) {
      const C = [];
      for (let x = 0; x < 5; x++) C[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20];
      for (let x = 0; x < 5; x++) {
        const d = C[(x + 4) % 5] ^ rotl64(C[(x + 1) % 5], 1);
        for (let y = 0; y < 5; y++) state[x + 5 * y] ^= d;
      }
      const B = new Array(25);
      for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) {
        B[y + 5 * ((2 * x + 3 * y) % 5)] = rotl64(state[x + 5 * y], R64[x][y]);
      }
      for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) {
        state[x + 5 * y] = B[x + 5 * y] ^ (~B[(x + 1) % 5 + 5 * y] & B[(x + 2) % 5 + 5 * y]);
      }
      state[0] ^= RC64[round];
    }
  }
  const rate = 136; // keccak-256 rate in bytes
  const state = new Array(25).fill(0n);
  const padded = new Uint8Array(Math.ceil((bytes.length + 1) / rate) * rate);
  padded.set(bytes);
  padded[bytes.length] = 0x01;
  padded[padded.length - 1] |= 0x80;
  for (let off = 0; off < padded.length; off += rate) {
    for (let i = 0; i < rate / 8; i++) {
      let lane = 0n;
      for (let b = 0; b < 8; b++) lane |= BigInt(padded[off + i * 8 + b]) << BigInt(8 * b);
      state[i] ^= lane;
    }
    keccakF(state);
  }
  let out = "";
  for (let i = 0; i < 4; i++) {
    // Lanes are little-endian: emit the low byte first.
    for (let b = 0; b < 8; b++) {
      out += Number((state[i] >> BigInt(8 * b)) & 0xffn).toString(16).padStart(2, "0");
    }
  }
  return out;
}

$("connectBtn").addEventListener("click", connect);
$("claimBtn").addEventListener("click", claim);
if (window.ethereum) {
  window.ethereum.on("accountsChanged", (accs) => {
    account = accs[0] || null;
    $("accountLine").textContent = account || "";
    $("badgeCard").hidden = true;
    refreshEligibility();
  });
  window.ethereum.on("chainChanged", () => window.location.reload());
}
if (!BADGE_CONTRACT) {
  $("deployCard").hidden = false;
} else {
  $("badgeAddr").innerHTML =
    '<a href="' + BSCSCAN + BADGE_CONTRACT + '" target="_blank" rel="noopener">' + BADGE_CONTRACT + "</a>";
}
refreshTotalClaimed();
