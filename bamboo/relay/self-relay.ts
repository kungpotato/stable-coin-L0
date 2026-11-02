// bamboo SELF-RELAY — a user rescues ONE stuck message themselves, using the
// attester sigs that are already published. No attester keys needed. This is why
// the relay is not a chokepoint: if every submitter is down or censoring, anyone
// with the published sigs can deliver the message.
//
//   BAMBOO_RELAYER_KEY=0x<funded on dst> node --experimental-strip-types self-relay.ts <msgId>

import { buildChains, GATEWAY_ABI, collectSigs, type Chain } from "./common.ts";
import type { Hex } from "viem";

const msgId = process.argv[2] as Hex;
if (!msgId) { console.error("usage: self-relay.ts <msgId>"); process.exit(1); }
const THRESHOLD = Number(process.env.BAMBOO_THRESHOLD ?? "2");
const relayerKey = process.env.BAMBOO_RELAYER_KEY as Hex;

const { chains, byLogicalId } = await buildChains(relayerKey);

// find the MessageSent across chains (lab: scan from genesis — chains are small)
let ev: any = null; let dst: Chain | undefined;
for (const c of chains) {
  const logs = await c.pub.getContractEvents({
    address: c.cfg.gateway, abi: GATEWAY_ABI, eventName: "MessageSent", fromBlock: 0n, toBlock: "latest",
  });
  const m = logs.find((l) => (l.args as any).msgId === msgId);
  if (m) { ev = m.args; dst = byLogicalId.get(Number(ev.dstChainId)); break; }
}
if (!ev || !dst || !dst.wallet) { console.error("message not found, or no relayer key for its dst"); process.exit(1); }

if (await dst.pub.readContract({ address: dst.cfg.gateway, abi: GATEWAY_ABI, functionName: "processed", args: [msgId] })) {
  console.log("already delivered ✅"); process.exit(0);
}
const sigs = collectSigs(msgId, THRESHOLD);
if (!sigs) { console.error(`not enough published sigs (need ${THRESHOLD})`); process.exit(1); }

console.log(`self-relaying ${msgId.slice(0, 10)} -> ${dst.name} with ${sigs.length} sigs...`);
const hash = await dst.wallet.writeContract({
  address: dst.cfg.gateway, abi: GATEWAY_ABI, functionName: "receiveMessage",
  args: [ev.srcChainId, ev.sender, ev.receiver, ev.payload, ev.nonce, sigs],
  chain: null, account: dst.wallet.account!,
});
await dst.pub.waitForTransactionReceipt({ hash });
console.log(`delivered! tx ${hash} ✅`);
