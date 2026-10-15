// Manual attestation by one DVN operator for one packet (topic 3 ops tool).
// Use when a packet stalls because this operator was never assigned it, e.g. after a send/receive config
// mismatch. The packet is re-read from the SOURCE chain's PacketSent: an operator must never attest a header or
// payload it did not find there itself.
// Run: DVN_ID=LabDVN_B DVN_KEY_VAR=DVN_B_KEY npm run attest -- <src chain> <sender OApp address> <nonce>
import { encodeFunctionData, getAddress } from "viem";
import { loadChains, byEid, scanPacketSent, signer, send, envKey, inboundState, log, short, errMsg, labDvnAbi } from "./lib.ts";

const ROLE = "attest";
const [srcName, senderArg, nonceArg] = process.argv.slice(2);
if (!srcName || !senderArg || !nonceArg) {
  console.error("usage: npm run attest -- <src chain> <sender OApp address> <nonce>");
  process.exit(2);
}
const DVN_ID = process.env.DVN_ID ?? "LabDVN";
const chains = loadChains();
const src = chains.find((c) => c.name === srcName);
if (!src) throw new Error(`unknown chain ${srcName}`);
const sender = getAddress(senderArg);
const nonce = BigInt(nonceArg);

try {
  const latest = await src.pub.getBlockNumber();
  const safe = latest - BigInt(src.confirmations);
  const found = (await scanPacketSent(src, 1n, safe)).find(
    (e) => e.packet.nonce === nonce && getAddress(`0x${e.packet.sender.slice(-40)}`) === sender,
  );
  if (!found) throw new Error(`no final PacketSent from ${sender} with nonce ${nonce} on ${src.name}`);
  const p = found.packet;
  const dst = byEid(chains, p.dstEid);
  if (!dst) throw new Error(`dstEid ${p.dstEid} not in topology`);
  log(ROLE, `found on ${src.name} in block ${found.blockNumber} (tx ${short(found.txHash)}), dst ${dst.name}`);

  const state = await inboundState(dst, p);
  if (state !== "pending") {
    log(ROLE, `already ${state} on ${dst.name}, nothing to do`);
    process.exit(0);
  }
  const dvn = dst.deployments[DVN_ID];
  const r = await send(dst, signer(dst, envKey(process.env.DVN_KEY_VAR ?? "DVN_KEY")), dvn,
    encodeFunctionData({ abi: labDvnAbi, functionName: "verify", args: [dst.receiveLib, p.header, p.payloadHash, BigInt(src.confirmations)] }));
  log(ROLE, `${DVN_ID} attested ${src.name}->${dst.name} nonce ${nonce} (tx ${short(r.transactionHash)})`);
} catch (e) {
  log(ROLE, `ERROR ${errMsg(e)}`);
  process.exit(1);
}
