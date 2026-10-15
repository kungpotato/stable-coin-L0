// Shared plumbing for the lab DVN and Executor: topology, clients, packet codec, log scanning, tx sending.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient, createWalletClient, http, parseAbi, parseAbiItem, keccak256, slice,
  hexToNumber, getAddress, decodeEventLog,
  type Address, type Hex, type PublicClient, type WalletClient, type Chain, type Log,
} from "viem";
import { privateKeyToAccount, type PrivateKeyAccount } from "viem/accounts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const LAB = join(ROOT, "lz-potato");

// ---------------------------------------------------------------- topology + deployments

export type ChainCfg = {
  name: string; chainId: number; eid: number; rpc: string; confirmations: number;
  endpoint: Address; receiveLib: Address; dvn: Address; executor: Address;
  deployments: Record<string, Address>; // everything recorded for this chain (e.g. LabDVN_B)
  pub: PublicClient; viemChain: Chain;
};

export function loadChains(): ChainCfg[] {
  const topo = JSON.parse(readFileSync(join(LAB, "config", "topology.json"), "utf8"));
  return Object.entries<any>(topo.chains).map(([name, c]) => {
    const dep = JSON.parse(readFileSync(join(LAB, "deployments", `${c.chainId}.json`), "utf8"));
    const viemChain = {
      id: c.chainId, name, nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
      rpcUrls: { default: { http: [c.rpc] } },
    } as const satisfies Chain;
    return {
      name, chainId: c.chainId, eid: c.eid, rpc: c.rpc, confirmations: c.confirmations,
      endpoint: dep.EndpointV2, receiveLib: dep.ReceiveUln302, dvn: dep.LabDVN, executor: dep.LabExecutor, deployments: dep,
      // 10s timeout: a hung RPC (anvil-home incident, topic 11.9) must surface as an error, not stall the loop
      pub: createPublicClient({ chain: viemChain, transport: http(c.rpc, { timeout: 10_000, retryCount: 1 }) }),
      viemChain,
    };
  });
}

export function byEid(chains: ChainCfg[], eid: number) {
  return chains.find((c) => c.eid === eid);
}

// ---------------------------------------------------------------- ABIs (only what the workers touch)

export const packetSentEvent = parseAbiItem("event PacketSent(bytes encodedPayload, bytes options, address sendLibrary)");
/** LabDVN on the SOURCE chain emits this when SendUln302 assigns (and pays) it for a packet. */
export const jobAssignedEvent = parseAbiItem("event JobAssigned(uint32 dstEid, bytes packetHeader, bytes32 payloadHash, uint64 confirmations, address sender)");

export const endpointAbi = parseAbi([
  "function lazyInboundNonce(address receiver, uint32 srcEid, bytes32 sender) view returns (uint64)",
  "function inboundPayloadHash(address receiver, uint32 srcEid, bytes32 sender, uint64 nonce) view returns (bytes32)",
  "function lzReceive((uint32 srcEid, bytes32 sender, uint64 nonce) origin, address receiver, bytes32 guid, bytes message, bytes extraData) payable",
  "function composeQueue(address from, address to, bytes32 guid, uint16 index) view returns (bytes32 messageHash)",
  "function lzCompose(address from, address to, bytes32 guid, uint16 index, bytes message, bytes extraData) payable",
]);
/** Emitted by the destination endpoint when an OApp (e.g. an OFT with composeMsg) queues a compose call. */
export const composeSentEvent = parseAbiItem("event ComposeSent(address from, address to, bytes32 guid, uint16 index, bytes message)");
export const receiveLibAbi = parseAbi([
  "function hashLookup(bytes32 headerHash, bytes32 payloadHash, address dvn) view returns (bool submitted, uint64 confirmations)",
  "function commitVerification(bytes packetHeader, bytes32 payloadHash)",
]);
export const labDvnAbi = parseAbi([
  "function verify(address receiveLib, bytes packetHeader, bytes32 payloadHash, uint64 confirmations)",
]);

// ---------------------------------------------------------------- packet codec

// PacketV1: version(1) nonce(8) srcEid(4) sender(32) dstEid(4) receiver(32) | guid(32) message(...)
export type Packet = {
  header: Hex; headerHash: Hex; payloadHash: Hex;
  nonce: bigint; srcEid: number; sender: Hex; dstEid: number; receiver: Address; guid: Hex; message: Hex;
};

export function decodePacket(encoded: Hex): Packet {
  const header = slice(encoded, 0, 81);
  const payload = slice(encoded, 81); // guid ++ message
  return {
    header,
    headerHash: keccak256(header),
    payloadHash: keccak256(payload),
    nonce: BigInt(slice(encoded, 1, 9)),
    srcEid: hexToNumber(slice(encoded, 9, 13)),
    sender: slice(encoded, 13, 45),
    dstEid: hexToNumber(slice(encoded, 45, 49)),
    receiver: getAddress(slice(encoded, 61, 81)), // last 20 bytes of the bytes32 receiver
    guid: slice(encoded, 81, 113),
    message: encoded.length > 2 + 113 * 2 ? slice(encoded, 113) : "0x",
  };
}

// ---------------------------------------------------------------- log scanning

const CHUNK = 1_000n;

/** PacketSent logs on `chain` in [from, to]. Never queries from block 0: cosmos/evm returns the tip's
 *  logs twice for fromBlock 0 (potato-chain/docs/known-issues.md). Callers also dedupe by on-chain state. */
export async function scanPacketSent(chain: ChainCfg, from: bigint, to: bigint) {
  const out: { blockNumber: bigint; txHash: Hex; logIndex: number; packet: Packet }[] = [];
  for (let start = from < 1n ? 1n : from; start <= to; start += CHUNK) {
    const end = start + CHUNK - 1n < to ? start + CHUNK - 1n : to;
    const logs: Log[] = await chain.pub.getLogs({ address: chain.endpoint, event: packetSentEvent, fromBlock: start, toBlock: end });
    for (const log of logs) {
      const { args } = decodeEventLog({ abi: [packetSentEvent], data: log.data, topics: log.topics });
      out.push({ blockNumber: log.blockNumber!, txHash: log.transactionHash!, logIndex: log.logIndex!, packet: decodePacket(args.encodedPayload) });
    }
  }
  return out;
}

// ---------------------------------------------------------------- sending txs

export type Signer = { account: PrivateKeyAccount; wallet: WalletClient };

export function signer(chain: ChainCfg, key: Hex): Signer {
  const account = privateKeyToAccount(key);
  return { account, wallet: createWalletClient({ account, chain: chain.viemChain, transport: http(chain.rpc, { timeout: 10_000 }) }) };
}

/** WORKAROUND_GAS=0 disables the workaround to reproduce the cosmos/evm eth_fillTransaction bug (topic 12). */
const GAS_WORKAROUND = process.env.WORKAROUND_GAS !== "0";

/** Send a call and wait for it. With the workaround, gas comes from a raw eth_estimateGas at latest: viem with a
 *  local account otherwise fills the tx via eth_fillTransaction, which cosmos/evm v0.7.3 estimates against block 0
 *  (intrinsic gas only -> out of gas). Same fix as potato-chain/web/src/burner.ts. */
export async function send(chain: ChainCfg, s: Signer, to: Address, data: Hex) {
  let gas: bigint | undefined;
  if (GAS_WORKAROUND) {
    const est = BigInt(await chain.pub.request({
      method: "eth_estimateGas", params: [{ from: s.account.address, to, data }, "latest"],
    } as never) as Hex);
    gas = (est * 12n) / 10n;
  }
  const hash = await s.wallet.sendTransaction({ account: s.account, chain: chain.viemChain, to, data, gas });
  const receipt = await chain.pub.waitForTransactionReceipt({ hash, timeout: 60_000 });
  if (receipt.status !== "success") {
    const tx = await chain.pub.getTransaction({ hash });
    const oog = receipt.gasUsed === tx.gas ? " = out of gas" : "";
    throw new Error(`tx ${hash} reverted on ${chain.name} (used ${receipt.gasUsed} of gas limit ${tx.gas}${oog})`);
  }
  return receipt;
}

// ---------------------------------------------------------------- cursor store (restart-safe)

export function cursorStore(role: string) {
  const file = join(ROOT, "workers", "state", `${role}.json`);
  const data: Record<string, string> = existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : {};
  return {
    /** Last fully processed block for `chain`; 0 = nothing yet (scan starts at block 1). */
    get: (chain: string) => BigInt(data[chain] ?? "0"),
    set: (chain: string, block: bigint) => {
      data[chain] = block.toString();
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
    },
  };
}

export function log(role: string, msg: string) {
  console.log(`${new Date().toISOString().slice(11, 19)} [${role}] ${msg}`);
}

export const short = (h: string) => `${h.slice(0, 10)}…`;
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Key from the environment, else from lz-potato/config/dev-keys.env (public lab keys). */
export function envKey(name: string): Hex {
  if (process.env[name]) return process.env[name] as Hex;
  const line = readFileSync(join(LAB, "config", "dev-keys.env"), "utf8").split("\n").find((l) => l.startsWith(`${name}=`));
  if (!line) throw new Error(`${name} not set and not in dev-keys.env`);
  return line.slice(name.length + 1).split(/\s/)[0] as Hex;
}

// PacketVerified index per destination chain, extended incrementally: which payload the endpoint accepted per nonce
const packetVerifiedEvent = parseAbiItem(
  "event PacketVerified((uint32 srcEid, bytes32 sender, uint64 nonce) origin, address receiver, bytes32 payloadHash)",
);
const verifiedIndex = new Map<string, { scannedTo: bigint; byKey: Map<string, Hex> }>();
const vKey = (srcEid: number, sender: Hex, receiver: Address, nonce: bigint) =>
  `${srcEid}-${sender.toLowerCase()}-${receiver.toLowerCase()}-${nonce}`;

async function acceptedPayload(dst: ChainCfg, p: Packet): Promise<Hex | undefined> {
  let idx = verifiedIndex.get(dst.name);
  if (!idx) verifiedIndex.set(dst.name, (idx = { scannedTo: 0n, byKey: new Map() }));
  const latest = await dst.pub.getBlockNumber();
  for (let start = idx.scannedTo + 1n; start <= latest; start += 1_000n) {
    const end = start + 999n < latest ? start + 999n : latest;
    const logs: Log[] = await dst.pub.getLogs({ address: dst.endpoint, event: packetVerifiedEvent, fromBlock: start, toBlock: end });
    for (const l of logs) {
      const { args } = decodeEventLog({ abi: [packetVerifiedEvent], data: l.data, topics: l.topics });
      idx.byKey.set(vKey(args.origin.srcEid, args.origin.sender, args.receiver, args.origin.nonce), args.payloadHash);
    }
    idx.scannedTo = end;
  }
  return idx.byKey.get(vKey(p.srcEid, p.sender, p.receiver, p.nonce));
}

/** Inbound state of a packet on its destination endpoint.
 *  "poisoned": the destination spent this nonce on a DIFFERENT payload (a forgery). The real packet can never be
 *  delivered; a nonce <= lazyInboundNonce with an empty slot is not proof that *this* packet arrived. */
export async function inboundState(dst: ChainCfg, p: Packet): Promise<"delivered" | "committed" | "pending" | "poisoned"> {
  const args = [p.receiver, p.srcEid, p.sender] as const;
  const [lazy, hash] = await Promise.all([
    dst.pub.readContract({ address: dst.endpoint, abi: endpointAbi, functionName: "lazyInboundNonce", args }),
    dst.pub.readContract({ address: dst.endpoint, abi: endpointAbi, functionName: "inboundPayloadHash", args: [...args, p.nonce] }),
  ]);
  if (BigInt(hash) !== 0n) return hash.toLowerCase() === p.payloadHash.toLowerCase() ? "committed" : "poisoned";
  if (p.nonce > lazy) return "pending";
  return (await acceptedPayload(dst, p))?.toLowerCase() === p.payloadHash.toLowerCase() ? "delivered" : "poisoned";
}

// Revert selectors an operator meets on these paths (cast sig "<error>()")
const KNOWN_ERRORS: Record<string, string> = {
  "0xd93c0665": "EnforcedPause (receiver paused)",
  "0xa74c1c5f": "RateLimitExceeded",
  "0x679f6e3d": "CreditFailed (recipient cannot take native coin)",
  "0x4c3118d4": "LZ_ULN_Verifying (DVN has not verified yet)",
  "0xc09b6350": "LZ_InvalidNonce",
  "0x7182306f": "LZ_PayloadHashNotFound",
  "0x118cdaa7": "OwnableUnauthorizedAccount",
  "0x14c84ce0": "UntrustedOApp (composer refused a compose not queued by our OFT)",
  "0x571f7b49": "AccountBlacklisted",
};

/** One-line reason for a failed call: viem's details (the node's revert text) with known selectors named. */
export function errMsg(e: unknown): string {
  const err = e as { details?: string; shortMessage?: string; message?: string };
  let msg = (err.details || err.shortMessage || err.message || String(e)).split("\n")[0];
  // the revert data (selector + args) sits on the RPC error somewhere down the cause chain, not in the text
  for (let c: any = e; c; c = c.cause) {
    const data = typeof c.data === "string" ? c.data : typeof c.data?.data === "string" ? c.data.data : undefined;
    if (data?.startsWith("0x") && data.length >= 10) { msg += ` (data ${data.slice(0, 10)})`; break; }
  }
  for (const [sel, name] of Object.entries(KNOWN_ERRORS)) if (msg.includes(sel)) msg += ` = ${name}`;
  return msg;
}
