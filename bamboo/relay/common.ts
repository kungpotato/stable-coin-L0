// Shared helpers for the bamboo relay mesh.
//
// Separation of concerns (the whole point of permissionless relaying):
//   - attesters PRODUCE signatures (they hold the trust) and publish them to a
//     shared signature store.
//   - submitters (anyone, incl. a user via self-relay) COLLECT >= threshold
//     published sigs and submit receiveMessage. They hold NO attester keys and
//     cannot forge — so running many of them is pure redundancy, and a user can
//     rescue a stuck message themselves.
//
// Lab store = a local directory (relay/sigs/<msgId>.json). Production = an API /
// gossip layer the attesters publish to; the submission path is identical.

import {
  createPublicClient, createWalletClient, http, parseAbi,
  keccak256, encodeAbiParameters, type Address, type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

export const __dir = dirname(fileURLToPath(import.meta.url));

export type ChainCfg = { rpc: string; logicalChainId: number; token: Address; gateway: Address; oft?: Address };
export const deployments = JSON.parse(
  readFileSync(join(__dir, "..", "deployments", "local.json"), "utf8"),
) as { chains: Record<string, ChainCfg> };

export const GATEWAY_ABI = parseAbi([
  "event MessageSent(bytes32 indexed msgId, uint64 srcChainId, uint64 dstChainId, address sender, address receiver, bytes payload, uint64 nonce)",
  "function receiveMessage(uint64 srcChainId, address sender, address receiver, bytes payload, uint64 nonce, bytes[] sigs)",
  "function processed(bytes32) view returns (bool)",
]);

export const CONFIRMATIONS = BigInt(process.env.BAMBOO_CONFIRMATIONS ?? "2");
export const POLL_MS = Number(process.env.BAMBOO_POLL_MS ?? "1500");

export type Chain = {
  name: string; cfg: ChainCfg;
  pub: ReturnType<typeof createPublicClient>;
  wallet?: ReturnType<typeof createWalletClient>;
  evmChainId: number; lastBlock: bigint;
};

export async function buildChains(relayerKey?: Hex) {
  const chains: Chain[] = [];
  for (const [name, cfg] of Object.entries(deployments.chains)) {
    const transport = http(cfg.rpc);
    const pub = createPublicClient({ transport });
    const key = (process.env[`BAMBOO_RELAYER_KEY_${name.toUpperCase()}`] ?? relayerKey) as Hex | undefined;
    const wallet = key ? createWalletClient({ account: privateKeyToAccount(key), transport }) : undefined;
    const evmChainId = await pub.getChainId();
    chains.push({ name, cfg, pub, wallet, evmChainId, lastBlock: 0n });
  }
  return { chains, byLogicalId: new Map(chains.map((c) => [c.cfg.logicalChainId, c])) };
}

// H-1 domain-bound digest (binds to dst gateway + its EVM chain)
export function innerDigest(evmChainId: number, gateway: Address, msgId: Hex): Hex {
  return keccak256(encodeAbiParameters(
    [{ type: "uint256" }, { type: "address" }, { type: "bytes32" }],
    [BigInt(evmChainId), gateway, msgId],
  ));
}

// --- shared signature store (lab = filesystem) ---
// One file per (msgId, signer) so concurrent attesters never clobber each other.
const SIGDIR = join(__dir, "sigs");
export function readSigs(msgId: string): Record<string, Hex> {
  const d = join(SIGDIR, msgId);
  const out: Record<string, Hex> = {};
  try {
    for (const f of readdirSync(d)) {
      if (f.endsWith(".sig")) out[f.slice(0, -4)] = readFileSync(join(d, f), "utf8").trim() as Hex;
    }
  } catch { /* none yet */ }
  return out;
}
export function writeSig(msgId: string, signer: string, sig: Hex) {
  const d = join(SIGDIR, msgId);
  if (!existsSync(d)) mkdirSync(d, { recursive: true });
  writeFileSync(join(d, signer.toLowerCase() + ".sig"), sig);
}

// sorted (ascending signer) sigs ready for the gateway, or null if below threshold
export function collectSigs(msgId: string, threshold: number): Hex[] | null {
  const m = readSigs(msgId);
  const signers = Object.keys(m).sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
  if (signers.length < threshold) return null;
  return signers.slice(0, threshold).map((s) => m[s]);
}

// --- checkpoints ---
export function readCkpt(file: string): Record<string, string> {
  try { return JSON.parse(readFileSync(join(__dir, file), "utf8")); } catch { return {}; }
}
export function writeCkpt(file: string, chains: Chain[]) {
  const o: Record<string, string> = {};
  for (const c of chains) o[c.name] = c.lastBlock.toString();
  try { writeFileSync(join(__dir, file), JSON.stringify(o)); } catch { /* ignore */ }
}

// scan a chain for new MessageSent up to (head - confirmations); returns decoded events
export async function scanMessages(c: Chain, ckptFile: string, chains: Chain[]) {
  const head = await c.pub.getBlockNumber();
  const safe = head > CONFIRMATIONS ? head - CONFIRMATIONS : 0n;
  if (c.lastBlock === 0n) { c.lastBlock = safe; writeCkpt(ckptFile, chains); return []; }
  if (safe <= c.lastBlock) return [];
  const logs = await c.pub.getContractEvents({
    address: c.cfg.gateway, abi: GATEWAY_ABI, eventName: "MessageSent",
    fromBlock: c.lastBlock + 1n, toBlock: safe,
  });
  c.lastBlock = safe; writeCkpt(ckptFile, chains);
  return logs.map((l) => l.args as any);
}
