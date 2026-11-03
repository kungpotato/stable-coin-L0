// bamboo ATTESTER — one process per signer (issuer / BOT).
// Watches both chains, signs the domain-bound digest of each message, and
// publishes the signature to the shared store. Holds exactly ONE key.
//
//   BAMBOO_ATTESTER_KEY=0x...  node --experimental-strip-types attester.ts
//
// In production each issuer + BOT runs their own attester with their key in an
// HSM — never one process holding every key (that would break the trust model).

import { buildChains, innerDigest, writeSig, readCkpt, writeCkpt, scanMessages, POLL_MS, type Chain } from "./common.ts";
import { privateKeyToAccount } from "viem/accounts";
import { decodeAbiParameters, type Hex } from "viem";

const key = process.env.BAMBOO_ATTESTER_KEY as Hex;
if (!key) throw new Error("set BAMBOO_ATTESTER_KEY (one key)");
const acct = privateKeyToAccount(key);

// Anti blind-signing (Bybit lesson): validate the message against this attester's
// policy BEFORE signing. In production each issuer/BOT enforces its own policy; here
// we reject unknown message kinds and transfers above an optional amount cap.
const MAX_SIGN_AMOUNT = process.env.BAMBOO_MAX_SIGN_AMOUNT ? BigInt(process.env.BAMBOO_MAX_SIGN_AMOUNT) : 0n;

function refuseReason(payload: Hex): string | null {
  try {
    const [kind, inner] = decodeAbiParameters([{ type: "uint8" }, { type: "bytes" }], payload);
    const k = Number(kind);
    if (k > 4) return `unknown kind ${k}`;
    if (k === 0 && MAX_SIGN_AMOUNT > 0n) { // TRANSFER
      const [, amount] = decodeAbiParameters([{ type: "address" }, { type: "uint256" }], inner as Hex);
      if ((amount as bigint) > MAX_SIGN_AMOUNT) return `amount ${amount} > policy cap ${MAX_SIGN_AMOUNT}`;
    }
    return null;
  } catch { return "undecodable payload"; }
}

const { chains, byLogicalId } = await buildChains();
const ckptFile = `.ckpt-att-${acct.address.toLowerCase()}.json`;
const ckpt = readCkpt(ckptFile);
for (const c of chains) if (ckpt[c.name]) c.lastBlock = BigInt(ckpt[c.name]);

console.log(`attester ${acct.address} up | chains ${chains.map((c) => c.name).join(",")}`);

async function poll(c: Chain) {
  const msgs = await scanMessages(c, ckptFile, chains);
  for (const a of msgs) {
    const dst = byLogicalId.get(Number(a.dstChainId));
    if (!dst) continue;
    const reason = refuseReason(a.payload as Hex);
    if (reason) { console.warn(`  REFUSE ${a.msgId.slice(0, 10)}: ${reason}`); continue; }
    const inner = innerDigest(dst.evmChainId, dst.cfg.gateway, a.msgId);
    const sig = await acct.signMessage({ message: { raw: inner } });
    writeSig(a.msgId, acct.address, sig);
    console.log(`  signed ${a.msgId.slice(0, 10)} (${c.name}->${dst.name})`);
  }
}

while (true) {
  for (const c of chains) {
    try { await poll(c); } catch (e) { console.error(`att ${c.name}:`, (e as Error).message); }
  }
  await new Promise((r) => setTimeout(r, POLL_MS));
}
