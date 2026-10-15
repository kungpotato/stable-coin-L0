// Path audit (topic 3/8): for one bridged asset, compare every nonce's payload hash on the source (PacketSent)
// with what the destination accepted (PacketVerified). Nonce counts alone miss a forgery once real traffic
// catches up with the forged nonce; payload hashes don't.
//   OK         destination accepted exactly what the source sent, and executed it
//   IN_FLIGHT  sent, not yet verified/executed
//   FORGED     destination accepted a payload the source never sent for that nonce
//   POISONED   the source's real message can never be delivered: its nonce was used by a forgery
//              (FORGED+POISONED when both happened on the same nonce)
// Run: npm run audit -- <deployments key, e.g. DEMOWEAK>      exit 0 clean / 1 in flight / 2 FORGED or POISONED
import { decodeEventLog, getAddress, parseAbiItem, type Address, type Hex, type Log } from "viem";
import { loadChains, scanPacketSent, endpointAbi, errMsg, type ChainCfg } from "./lib.ts";

const packetVerifiedEvent = parseAbiItem(
  "event PacketVerified((uint32 srcEid, bytes32 sender, uint64 nonce) origin, address receiver, bytes32 payloadHash)",
);
const asset = process.argv[2];
if (!asset) {
  console.error("usage: npm run audit -- <asset deployments key>");
  process.exit(3);
}

/** PacketVerified on `dst` for packets from `srcEid`/`sender` to `receiver`: nonce -> payload hash (last one wins). */
async function verifiedOn(dst: ChainCfg, srcEid: number, sender: Address, receiver: Address) {
  const out = new Map<bigint, Hex>();
  const latest = await dst.pub.getBlockNumber();
  for (let start = 1n; start <= latest; start += 1_000n) {
    const end = start + 999n < latest ? start + 999n : latest;
    const logs: Log[] = await dst.pub.getLogs({ address: dst.endpoint, event: packetVerifiedEvent, fromBlock: start, toBlock: end });
    for (const l of logs) {
      const { args } = decodeEventLog({ abi: [packetVerifiedEvent], data: l.data, topics: l.topics });
      if (args.origin.srcEid === srcEid && getAddress(`0x${args.origin.sender.slice(-40)}`) === sender && getAddress(args.receiver) === receiver) {
        out.set(args.origin.nonce, args.payloadHash);
      }
    }
  }
  return out;
}

async function auditPath(src: ChainCfg, dst: ChainCfg) {
  const sender = src.deployments[asset] as Address, receiver = dst.deployments[asset] as Address;
  const sent = new Map<bigint, Hex>();
  for (const e of await scanPacketSent(src, 1n, await src.pub.getBlockNumber())) {
    if (e.packet.dstEid === dst.eid && getAddress(`0x${e.packet.sender.slice(-40)}`) === sender && e.packet.receiver === receiver) {
      sent.set(e.packet.nonce, e.packet.payloadHash);
    }
  }
  const verified = await verifiedOn(dst, src.eid, sender, receiver);
  const sender32 = `0x${sender.slice(2).toLowerCase().padStart(64, "0")}` as Hex;
  const lazy = await dst.pub.readContract({ address: dst.endpoint, abi: endpointAbi, functionName: "lazyInboundNonce", args: [receiver, src.eid, sender32] });

  const last = [...sent.keys(), ...verified.keys(), lazy].reduce((a, b) => (b > a ? b : a), 0n);
  const rows: { nonce: bigint; status: string }[] = [];
  for (let n = 1n; n <= last; n++) {
    const s = sent.get(n), v = verified.get(n);
    const slot = await dst.pub.readContract({ address: dst.endpoint, abi: endpointAbi, functionName: "inboundPayloadHash", args: [receiver, src.eid, sender32, n] });
    const executed = n <= lazy && BigInt(slot) === 0n;
    let status: string;
    if (v && v !== s) status = s ? "FORGED+POISONED" : "FORGED"; // accepted a payload the source never sent (+ lost the real one)
    else if (s && v === s) status = executed ? "OK" : "IN_FLIGHT";
    else if (s && executed) status = "POISONED";         // its nonce is spent and nothing matching was verified
    else if (s) status = "IN_FLIGHT";
    else if (executed) status = "FORGED";                // executed without any matching send (e.g. skipped)
    else continue;
    rows.push({ nonce: n, status });
  }
  return rows;
}

const chains = loadChains().filter((c) => c.deployments[asset]);
if (chains.length < 2) {
  console.error(`${asset} is not deployed on two chains`);
  process.exit(3);
}
let worst = 0;
try {
  for (const src of chains) {
    for (const dst of chains) {
      if (src === dst) continue;
      const rows = await auditPath(src, dst);
      const bad = rows.filter((r) => r.status !== "OK");
      console.log(`${asset} ${src.name}->${dst.name}: ${rows.length} nonce(s), ${rows.length - bad.length} OK` +
        (bad.length ? ` | ${bad.map((r) => `nonce ${r.nonce} ${r.status}`).join(", ")}` : ""));
      for (const r of bad) worst = Math.max(worst, r.status === "IN_FLIGHT" ? 1 : 2);
    }
  }
} catch (e) {
  console.error(`audit failed: ${errMsg(e)}`);
  process.exit(3);
}
process.exit(worst);
