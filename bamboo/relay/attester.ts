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
import type { Hex } from "viem";

const key = process.env.BAMBOO_ATTESTER_KEY as Hex;
if (!key) throw new Error("set BAMBOO_ATTESTER_KEY (one key)");
const acct = privateKeyToAccount(key);

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
