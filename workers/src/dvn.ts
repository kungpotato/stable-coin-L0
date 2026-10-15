// Lab DVN worker (topic 12): watch PacketSent on every chain, wait the source chain's confirmations,
// then attest the packet on the destination's ReceiveUln302 through LabDVN.verify.
// Run: npm run dvn          State: workers/state/dvn.json (last processed block per source chain)
import { encodeFunctionData } from "viem";
import { loadChains, byEid, scanPacketSent, signer, send, cursorStore, envKey, inboundState, log, short, sleep, errMsg,
  receiveLibAbi, labDvnAbi, type ChainCfg, type Packet } from "./lib.ts";

const ROLE = "dvn";
const POLL_MS = 2_000;
const chains = loadChains();
const key = envKey("DVN_KEY");
const signers = new Map(chains.map((c) => [c.name, signer(c, key)]));
const cursor = cursorStore(ROLE);

async function attest(src: ChainCfg, p: Packet) {
  const dst = byEid(chains, p.dstEid);
  const path = `${src.name}->${dst?.name ?? p.dstEid} nonce ${p.nonce}`;
  if (!dst) return log(ROLE, `${path}: skip, dstEid not in topology`);

  // idempotent: anything already verified / committed / delivered needs nothing from us
  const state = await inboundState(dst, p);
  if (state !== "pending") return log(ROLE, `${path}: already ${state}`);
  const [submitted] = await dst.pub.readContract({
    address: dst.receiveLib, abi: receiveLibAbi, functionName: "hashLookup", args: [p.headerHash, p.payloadHash, dst.dvn],
  });
  if (submitted) return log(ROLE, `${path}: already verified by us`);

  const data = encodeFunctionData({
    abi: labDvnAbi, functionName: "verify", args: [dst.receiveLib, p.header, p.payloadHash, BigInt(src.confirmations)],
  });
  const r = await send(dst, signers.get(dst.name)!, dst.dvn, data);
  log(ROLE, `${path}: verified on ${dst.name} (tx ${short(r.transactionHash)}, gas ${r.gasUsed})`);
}

async function tick(src: ChainCfg) {
  const latest = await src.pub.getBlockNumber();
  const safe = latest - BigInt(src.confirmations); // packet in block b is final once latest >= b + confirmations
  const from = cursor.get(src.name) + 1n;
  if (from > safe) return;
  for (const ev of await scanPacketSent(src, from, safe)) await attest(src, ev.packet);
  cursor.set(src.name, safe); // only after every packet in the range was handled; a throw retries the range
}

log(ROLE, `signer ${signers.values().next().value!.account.address}, chains ${chains.map((c) => `${c.name}(eid ${c.eid}, ${c.confirmations} conf)`).join(", ")}`);
for (;;) {
  for (const src of chains) {
    try { await tick(src); } catch (e) { log(ROLE, `ERROR ${src.name}: ${errMsg(e)}`); }
  }
  await sleep(POLL_MS);
}
