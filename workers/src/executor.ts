// Lab Executor worker (topic 12): for every PacketSent, wait until the DVN has verified it on the destination,
// commit the verification to the endpoint, then deliver it with EndpointV2.lzReceive.
// Run: npm run executor     State: workers/state/executor.json (all packets up to this block are delivered)
import { encodeFunctionData } from "viem";
import { loadChains, byEid, scanPacketSent, signer, send, cursorStore, envKey, inboundState, log, short, sleep,
  endpointAbi, receiveLibAbi, type ChainCfg, type Packet } from "./lib.ts";

const ROLE = "executor";
const POLL_MS = 2_000;
const chains = loadChains();
const key = envKey("EXECUTOR_KEY");
const signers = new Map(chains.map((c) => [c.name, signer(c, key)]));
const cursor = cursorStore(ROLE);
const waiting = new Set<string>(); // log "waiting for DVN" once per packet, not every poll

/** Push one packet as far as it can go. Returns true once it is delivered (or can never be). */
async function progress(src: ChainCfg, p: Packet): Promise<boolean> {
  const dst = byEid(chains, p.dstEid);
  const path = `${src.name}->${dst?.name ?? p.dstEid} nonce ${p.nonce}`;
  if (!dst) { log(ROLE, `${path}: skip, dstEid not in topology`); return true; }
  const s = signers.get(dst.name)!;

  let state = await inboundState(dst, p);
  if (state === "delivered") return true;

  if (state === "pending") {
    // commitVerification is permissionless but reverts (LZ_ULN_Verifying) until the required DVNs have attested;
    // send() estimates gas first, so a revert here just means "not verified yet"
    try {
      const r = await send(dst, s, dst.receiveLib,
        encodeFunctionData({ abi: receiveLibAbi, functionName: "commitVerification", args: [p.header, p.payloadHash] }));
      log(ROLE, `${path}: committed on ${dst.name} (tx ${short(r.transactionHash)})`);
      state = "committed";
    } catch {
      if (!waiting.has(path)) log(ROLE, `${path}: waiting for DVN verification`);
      waiting.add(path);
      return false;
    }
  }

  const r = await send(dst, s, dst.endpoint, encodeFunctionData({
    abi: endpointAbi, functionName: "lzReceive",
    args: [{ srcEid: p.srcEid, sender: p.sender, nonce: p.nonce }, p.receiver, p.guid, p.message, "0x"],
  }));
  waiting.delete(path);
  log(ROLE, `${path}: delivered to ${p.receiver} (tx ${short(r.transactionHash)}, gas ${r.gasUsed})`);
  return true;
}

async function tick(src: ChainCfg) {
  const latest = await src.pub.getBlockNumber();
  const from = cursor.get(src.name) + 1n;
  if (from > latest) return;
  // the cursor may only pass a block once every packet in it is delivered; an undelivered packet is retried
  // next tick without holding back the ones after it (endpoint enforces nonce order itself)
  let done = latest;
  for (const ev of await scanPacketSent(src, from, latest)) {
    let ok = false;
    try { ok = await progress(src, ev.packet); }
    catch (e) { log(ROLE, `ERROR ${src.name} nonce ${ev.packet.nonce}: ${(e as Error).message.split("\n")[0]}`); }
    if (!ok && ev.blockNumber - 1n < done) done = ev.blockNumber - 1n;
  }
  if (done >= from) cursor.set(src.name, done);
}

log(ROLE, `signer ${signers.values().next().value!.account.address}, chains ${chains.map((c) => `${c.name}(eid ${c.eid})`).join(", ")}`);
for (;;) {
  for (const src of chains) {
    try { await tick(src); } catch (e) { log(ROLE, `ERROR ${src.name}: ${(e as Error).message.split("\n")[0]}`); }
  }
  await sleep(POLL_MS);
}
