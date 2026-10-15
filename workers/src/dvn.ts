// Lab DVN worker (topic 12): watch PacketSent on every chain, wait the source chain's confirmations,
// then attest the packet on the destination's ReceiveUln302 through this operator's LabDVN.verify.
// Like a real DVN it only works on packets it was assigned (JobAssigned from its contract on the source chain).
// Run: npm run dvn                                      (operator LabDVN, key DVN_KEY)
//      DVN_ID=LabDVN_B DVN_KEY_VAR=DVN_B_KEY npm run dvn  (topic 3: a second, independent operator)
// State: workers/state/dvn.json, or dvn-<DVN_ID>.json for other operators
import { encodeFunctionData, keccak256 } from "viem";
import { loadChains, byEid, scanPacketSent, signer, send, cursorStore, envKey, inboundState, log, short, sleep, errMsg,
  receiveLibAbi, labDvnAbi, jobAssignedEvent, type ChainCfg, type Packet } from "./lib.ts";

const DVN_ID = process.env.DVN_ID ?? "LabDVN";
const ROLE = DVN_ID === "LabDVN" ? "dvn" : `dvn-${DVN_ID}`;
const POLL_MS = 2_000;
const chains = loadChains();
const key = envKey(process.env.DVN_KEY_VAR ?? "DVN_KEY");
const dvnOn = (c: ChainCfg) => {
  const a = c.deployments[DVN_ID];
  if (!a) throw new Error(`${DVN_ID} not deployed on ${c.name}`);
  return a;
};
const signers = new Map(chains.map((c) => [c.name, signer(c, key)]));
const cursor = cursorStore(ROLE);

async function attest(src: ChainCfg, p: Packet) {
  const dst = byEid(chains, p.dstEid);
  const path = `${src.name}->${dst?.name ?? p.dstEid} nonce ${p.nonce}`;
  if (!dst) return log(ROLE, `${path}: skip, dstEid not in topology`);

  // idempotent: anything already verified / committed / delivered needs nothing from us
  const state = await inboundState(dst, p);
  if (state === "poisoned") return log(ROLE, `${path}: ALERT POISONED, ${dst.name} spent this nonce on a different payload (forged message?); not attesting`);
  if (state !== "pending") return log(ROLE, `${path}: already ${state}`);
  const [submitted] = await dst.pub.readContract({
    address: dst.receiveLib, abi: receiveLibAbi, functionName: "hashLookup", args: [p.headerHash, p.payloadHash, dvnOn(dst)],
  });
  if (submitted) return log(ROLE, `${path}: already verified by us`);

  const data = encodeFunctionData({
    abi: labDvnAbi, functionName: "verify", args: [dst.receiveLib, p.header, p.payloadHash, BigInt(src.confirmations)],
  });
  const r = await send(dst, signers.get(dst.name)!, dvnOn(dst), data);
  log(ROLE, `${path}: verified on ${dst.name} (tx ${short(r.transactionHash)}, gas ${r.gasUsed})`);
}

async function tick(src: ChainCfg) {
  const latest = await src.pub.getBlockNumber();
  const safe = latest - BigInt(src.confirmations); // packet in block b is final once latest >= b + confirmations
  const from = cursor.get(src.name) + 1n;
  if (from > safe) return;
  // window by window (cosmos/evm caps getLogs ranges); only packets this operator was assigned on the source
  // chain, i.e. the OApp's send config picked it and SendUln302 paid it
  for (let start = from < 1n ? 1n : from; start <= safe; start += 1_000n) {
    const end = start + 999n < safe ? start + 999n : safe;
    const jobs = await src.pub.getLogs({ address: dvnOn(src), event: jobAssignedEvent, fromBlock: start, toBlock: end });
    const assigned = new Set(jobs.map((j) => keccak256(j.args.packetHeader!)));
    for (const ev of await scanPacketSent(src, start, end)) {
      if (assigned.has(ev.packet.headerHash)) await attest(src, ev.packet);
      else log(ROLE, `${src.name} nonce ${ev.packet.nonce} to eid ${ev.packet.dstEid}: not assigned to ${DVN_ID}, skip`);
    }
  }
  cursor.set(src.name, safe); // only after every packet in the range was handled; a throw retries the range
}

log(ROLE, `${DVN_ID} signer ${signers.values().next().value!.account.address}, chains ${chains.map((c) => `${c.name}(eid ${c.eid}, ${c.confirmations} conf)`).join(", ")}`);
for (;;) {
  for (const src of chains) {
    try { await tick(src); } catch (e) { log(ROLE, `ERROR ${src.name}: ${errMsg(e)}`); }
  }
  await sleep(POLL_MS);
}
