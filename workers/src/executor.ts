// Lab Executor worker (topic 12): for every PacketSent, wait until the DVN has verified it on the destination,
// commit the verification to the endpoint, then deliver it with EndpointV2.lzReceive.
// Topic 7: then run any compose the receiver queued (ComposeSent) with EndpointV2.lzCompose, as its own tx.
// Run: npm run executor     State: workers/state/executor.json (all packets up to this block are delivered)
import { encodeFunctionData, keccak256, type Log, decodeEventLog } from "viem";
import { loadChains, byEid, scanPacketSent, signer, send, cursorStore, envKey, inboundState, log, short, sleep, errMsg,
  endpointAbi, receiveLibAbi, composeSentEvent, type ChainCfg, type Packet } from "./lib.ts";

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
  if (state === "poisoned") { // terminal: can never be delivered; alert once, let the cursor move on
    log(ROLE, `${path}: ALERT POISONED, ${dst.name} spent this nonce on a different payload (forged message?); undeliverable`);
    return true;
  }

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
    catch (e) { log(ROLE, `ERROR ${src.name} nonce ${ev.packet.nonce}: ${errMsg(e)}`); }
    if (!ok && ev.blockNumber - 1n < done) done = ev.blockNumber - 1n;
  }
  if (done >= from) cursor.set(src.name, done);
}

const RECEIVED = `0x${"0".repeat(63)}1`; // composeQueue value once lzCompose ran

/** Run every compose queued on `dst` (ComposeSent) that has not run yet. Cursor "compose-<chain>" only passes
 *  blocks whose composes all ran; a failing compose (the composer reverted) is retried next tick. */
async function composeTick(dst: ChainCfg) {
  const key = `compose-${dst.name}`;
  const latest = await dst.pub.getBlockNumber();
  const from = cursor.get(key) + 1n;
  if (from > latest) return;
  let done = latest;
  for (let start = from < 1n ? 1n : from; start <= latest; start += 1_000n) {
    const end = start + 999n < latest ? start + 999n : latest;
    const logs: Log[] = await dst.pub.getLogs({ address: dst.endpoint, event: composeSentEvent, fromBlock: start, toBlock: end });
    for (const l of logs) {
      const { args } = decodeEventLog({ abi: [composeSentEvent], data: l.data, topics: l.topics });
      const what = `compose on ${dst.name} ${args.from.slice(0, 8)}… -> ${args.to.slice(0, 8)}… guid ${short(args.guid)}`;
      try {
        const queued = await dst.pub.readContract({ address: dst.endpoint, abi: endpointAbi, functionName: "composeQueue",
          args: [args.from, args.to, args.guid, args.index] });
        if (queued === RECEIVED) continue;
        if (queued !== keccak256(args.message)) { log(ROLE, `${what}: queue holds a different message, skip`); continue; }
        const r = await send(dst, signers.get(dst.name)!, dst.endpoint, encodeFunctionData({
          abi: endpointAbi, functionName: "lzCompose", args: [args.from, args.to, args.guid, args.index, args.message, "0x"],
        }));
        log(ROLE, `${what}: composed (tx ${short(r.transactionHash)}, gas ${r.gasUsed})`);
      } catch (e) {
        log(ROLE, `ERROR ${what}: ${errMsg(e)}`);
        if (l.blockNumber! - 1n < done) done = l.blockNumber! - 1n;
      }
    }
  }
  if (done >= from) cursor.set(key, done);
}

log(ROLE, `signer ${signers.values().next().value!.account.address}, chains ${chains.map((c) => `${c.name}(eid ${c.eid})`).join(", ")}`);
for (;;) {
  for (const src of chains) {
    try { await tick(src); } catch (e) { log(ROLE, `ERROR ${src.name}: ${errMsg(e)}`); }
    try { await composeTick(src); } catch (e) { log(ROLE, `ERROR compose ${src.name}: ${errMsg(e)}`); }
  }
  await sleep(POLL_MS);
}
