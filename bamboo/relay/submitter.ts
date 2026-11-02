// bamboo SUBMITTER (permissionless relayer) — collects >= threshold published
// attester sigs and submits receiveMessage. Holds NO attester key; cannot forge.
// Run as many as you like for redundancy — they race, losers see "replay" and skip.
//
//   BAMBOO_SUBMITTER_ID=0 BAMBOO_RELAYER_KEY=0x... node --experimental-strip-types submitter.ts

import { buildChains, GATEWAY_ABI, collectSigs, readCkpt, scanMessages, POLL_MS, type Chain } from "./common.ts";
import type { Address, Hex } from "viem";

const THRESHOLD = Number(process.env.BAMBOO_THRESHOLD ?? "2");
const relayerKey = process.env.BAMBOO_RELAYER_KEY as Hex;
const id = process.env.BAMBOO_SUBMITTER_ID ?? "0";

const { chains, byLogicalId } = await buildChains(relayerKey);
const ckptFile = `.ckpt-sub-${id}.json`;
const ckpt = readCkpt(ckptFile);
for (const c of chains) if (ckpt[c.name]) c.lastBlock = BigInt(ckpt[c.name]);

type Pending = { dstLogical: number; srcChainId: bigint; sender: Address; receiver: Address; payload: Hex; nonce: bigint };
const pending = new Map<string, Pending>();

console.log(`submitter #${id} up | threshold ${THRESHOLD}`);

async function trySubmit(msgId: string, p: Pending) {
  const dst = byLogicalId.get(p.dstLogical);
  if (!dst || !dst.wallet) { pending.delete(msgId); return; }
  if (await dst.pub.readContract({ address: dst.cfg.gateway, abi: GATEWAY_ABI, functionName: "processed", args: [msgId as Hex] })) {
    pending.delete(msgId); return;
  }
  const sigs = collectSigs(msgId, THRESHOLD);
  if (!sigs) return; // not enough published sigs yet
  try {
    await new Promise((r) => setTimeout(r, Math.random() * 300)); // jitter so redundant submitters don't always collide
    if (await dst.pub.readContract({ address: dst.cfg.gateway, abi: GATEWAY_ABI, functionName: "processed", args: [msgId as Hex] })) {
      pending.delete(msgId); return;
    }
    const hash = await dst.wallet.writeContract({
      address: dst.cfg.gateway, abi: GATEWAY_ABI, functionName: "receiveMessage",
      args: [p.srcChainId, p.sender, p.receiver, p.payload, p.nonce, sigs],
      chain: null, account: dst.wallet.account!,
    });
    await dst.pub.waitForTransactionReceipt({ hash });
    pending.delete(msgId);
    console.log(`  #${id} delivered ${msgId.slice(0, 10)} on ${dst.name}  tx ${hash.slice(0, 10)}`);
  } catch (e) {
    const m = (e as Error).message;
    if (m.includes("replay") || m.includes("processed")) {
      pending.delete(msgId);
      console.log(`  #${id} ${msgId.slice(0, 10)} already delivered by another relayer`);
    } else {
      console.error(`  #${id} submit ${msgId.slice(0, 10)}:`, m.split("\n")[0]);
    }
  }
}

while (true) {
  for (const c of chains) {
    try {
      const msgs = await scanMessages(c, ckptFile, chains);
      for (const a of msgs) pending.set(a.msgId, {
        dstLogical: Number(a.dstChainId), srcChainId: a.srcChainId,
        sender: a.sender, receiver: a.receiver, payload: a.payload, nonce: a.nonce,
      });
    } catch (e) { console.error(`sub scan ${c.name}:`, (e as Error).message); }
  }
  for (const [msgId, p] of [...pending]) {
    try { await trySubmit(msgId, p); } catch (e) { console.error("submit:", (e as Error).message); }
  }
  await new Promise((r) => setTimeout(r, POLL_MS));
}
