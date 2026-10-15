// Per-nonce payload-hash audit of one bridged asset's path (shared by audit.ts and snapshot.ts).
//   OK         destination accepted exactly what the source sent, and executed it
//   IN_FLIGHT  sent, not yet verified/executed
//   FORGED     destination accepted a payload the source never sent for that nonce
//   POISONED   the source's real message can never be delivered: its nonce was used by a forgery
//              (FORGED+POISONED when both happened on the same nonce)
import { decodeEventLog, getAddress, parseAbiItem, type Address, type Hex, type Log } from "viem";
import { scanPacketSent, endpointAbi, type ChainCfg } from "./lib.ts";

const packetVerifiedEvent = parseAbiItem(
  "event PacketVerified((uint32 srcEid, bytes32 sender, uint64 nonce) origin, address receiver, bytes32 payloadHash)",
);
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

export type NonceStatus = "OK" | "IN_FLIGHT" | "FORGED" | "FORGED+POISONED" | "POISONED";
export type AuditRow = { nonce: bigint; status: NonceStatus; payload?: Hex }; // payload: the source's real one

/** Per-nonce status of `asset`'s path src -> dst (deployments key on both chains). */
export async function auditPath(asset: string, src: ChainCfg, dst: ChainCfg): Promise<AuditRow[]> {
  const sender = src.deployments[asset] as Address, receiver = dst.deployments[asset] as Address;
  const sent = new Map<bigint, Hex>(), message = new Map<bigint, Hex>();
  for (const e of await scanPacketSent(src, 1n, await src.pub.getBlockNumber())) {
    if (e.packet.dstEid === dst.eid && getAddress(`0x${e.packet.sender.slice(-40)}`) === sender && e.packet.receiver === receiver) {
      sent.set(e.packet.nonce, e.packet.payloadHash);
      message.set(e.packet.nonce, e.packet.message);
    }
  }
  const verified = await verifiedOn(dst, src.eid, sender, receiver);
  const sender32 = `0x${sender.slice(2).toLowerCase().padStart(64, "0")}` as Hex;
  const lazy = await dst.pub.readContract({ address: dst.endpoint, abi: endpointAbi, functionName: "lazyInboundNonce", args: [receiver, src.eid, sender32] });

  const last = [...sent.keys(), ...verified.keys(), lazy].reduce((a, b) => (b > a ? b : a), 0n);
  const rows: AuditRow[] = [];
  for (let n = 1n; n <= last; n++) {
    const s = sent.get(n), v = verified.get(n);
    const slot = await dst.pub.readContract({ address: dst.endpoint, abi: endpointAbi, functionName: "inboundPayloadHash", args: [receiver, src.eid, sender32, n] });
    const executed = n <= lazy && BigInt(slot) === 0n;
    let status: NonceStatus;
    if (v && v !== s) status = s ? "FORGED+POISONED" : "FORGED"; // accepted a payload the source never sent (+ lost the real one)
    else if (s && v === s) status = executed ? "OK" : "IN_FLIGHT";
    else if (s && executed) status = "POISONED";         // its nonce is spent and nothing matching was verified
    else if (s) status = "IN_FLIGHT";
    else if (executed) status = "FORGED";                // executed without any matching send (e.g. skipped)
    else continue;
    rows.push({ nonce: n, status, payload: message.get(n) });
  }
  return rows;
}

