// bamboo relay + attester (lab)
//
// Plays "D" — the UNTRUSTED transport — plus the attester set. It can carry and
// reorder messages but can NEVER mint on its own (mint authority is behind the
// gateway's threshold check).
//
// Hardening (self-audit):
//   H-1 domain separation: sign a digest bound to the DESTINATION gateway + its
//       EVM chainid, so a signature can't be replayed on another gateway/chain.
//   H-2 finality: only act on logs up to (head - CONFIRMATIONS), so a source
//       reorg cannot cause a double-mint.
//   H-5 checkpoint: persist the last scanned block per chain and resume from it,
//       so messages emitted during downtime are not missed.
//
// L-1: keys still come from env here (lab only). Production = HSM / MPC, and each
// issuer runs its OWN attester — never one process holding every key.

import {
  createPublicClient, createWalletClient, http, parseAbi,
  keccak256, encodeAbiParameters,
  type Address, type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dir = dirname(fileURLToPath(import.meta.url));

// --- config -------------------------------------------------------------
type ChainCfg = { rpc: string; logicalChainId: number; token: Address; gateway: Address };
const deployments = JSON.parse(
  readFileSync(join(__dir, "..", "deployments", "local.json"), "utf8"),
) as { chains: Record<string, ChainCfg> };

const THRESHOLD = Number(process.env.BAMBOO_THRESHOLD ?? "2");
const POLL_MS = Number(process.env.BAMBOO_POLL_MS ?? "2000");
const CONFIRMATIONS = BigInt(process.env.BAMBOO_CONFIRMATIONS ?? "2"); // H-2
const CKPT = join(__dir, ".checkpoint.json");                          // H-5

const attesterKeys = (process.env.BAMBOO_ATTESTER_KEYS ?? "")
  .split(",").map((s) => s.trim()).filter(Boolean) as Hex[];
if (attesterKeys.length < THRESHOLD)
  throw new Error(`need >= ${THRESHOLD} attester keys, got ${attesterKeys.length}`);
const attesters = attesterKeys.map((k) => privateKeyToAccount(k));
attesters.sort((a, b) => (BigInt(a.address) < BigInt(b.address) ? -1 : 1)); // gateway needs sorted sigs

const defaultRelayerKey = process.env.BAMBOO_RELAYER_KEY as Hex | undefined;

const GATEWAY_ABI = parseAbi([
  "event MessageSent(bytes32 indexed msgId, uint64 srcChainId, uint64 dstChainId, address sender, address receiver, bytes payload, uint64 nonce)",
  "function receiveMessage(uint64 srcChainId, address sender, address receiver, bytes payload, uint64 nonce, bytes[] sigs)",
  "function processed(bytes32) view returns (bool)",
]);

// --- per-chain clients --------------------------------------------------
type Chain = {
  name: string; cfg: ChainCfg;
  pub: ReturnType<typeof createPublicClient>;
  wallet: ReturnType<typeof createWalletClient>;
  evmChainId: number;
  lastBlock: bigint;
};

const chains: Chain[] = [];
for (const [name, cfg] of Object.entries(deployments.chains)) {
  const relayerKey = (process.env[`BAMBOO_RELAYER_KEY_${name.toUpperCase()}`] ??
    defaultRelayerKey) as Hex | undefined;
  if (!relayerKey) throw new Error(`no relayer key for chain ${name}`);
  const transport = http(cfg.rpc);
  chains.push({
    name, cfg,
    pub: createPublicClient({ transport }),
    wallet: createWalletClient({ account: privateKeyToAccount(relayerKey), transport }),
    evmChainId: 0, lastBlock: 0n,
  });
}
const byLogicalId = new Map(chains.map((c) => [c.cfg.logicalChainId, c]));

// --- checkpoint (H-5) ---------------------------------------------------
function loadCheckpoint(): Record<string, string> {
  try { return JSON.parse(readFileSync(CKPT, "utf8")); } catch { return {}; }
}
function saveCheckpoint() {
  const o: Record<string, string> = {};
  for (const c of chains) o[c.name] = c.lastBlock.toString();
  try { writeFileSync(CKPT, JSON.stringify(o)); } catch (e) { console.error("checkpoint save:", (e as Error).message); }
}

// --- H-1: domain-bound digest the attesters sign ------------------------
//   inner = keccak256(abi.encode(dstEvmChainId, dstGateway, msgId))
//   then EIP-191 personal_sign over `inner` (matches gateway.digest()).
function innerDigest(dst: Chain, msgId: Hex): Hex {
  return keccak256(encodeAbiParameters(
    [{ type: "uint256" }, { type: "address" }, { type: "bytes32" }],
    [BigInt(dst.evmChainId), dst.cfg.gateway, msgId],
  ));
}

const seen = new Set<string>();

async function handleMessage(src: Chain, ev: {
  msgId: Hex; srcChainId: bigint; dstChainId: bigint;
  sender: Address; receiver: Address; payload: Hex; nonce: bigint;
}) {
  if (seen.has(ev.msgId)) return;
  const dst = byLogicalId.get(Number(ev.dstChainId));
  if (!dst) { console.warn(`  ! unknown dst chain ${ev.dstChainId} for ${ev.msgId}`); return; }

  const done = await dst.pub.readContract({
    address: dst.cfg.gateway, abi: GATEWAY_ABI, functionName: "processed", args: [ev.msgId],
  });
  if (done) { seen.add(ev.msgId); return; }

  // (1) attesters sign the domain-bound digest; already addr-sorted
  const inner = innerDigest(dst, ev.msgId);
  const sigs: Hex[] = [];
  for (const a of attesters.slice(0, THRESHOLD)) {
    sigs.push(await a.signMessage({ message: { raw: inner } }));
  }

  console.log(`  -> relaying ${ev.msgId.slice(0, 10)} ${src.name}->${dst.name}  ${ev.payload.length - 2} hex payload to app ${ev.receiver}`);
  const hash = await dst.wallet.writeContract({
    address: dst.cfg.gateway, abi: GATEWAY_ABI, functionName: "receiveMessage",
    args: [ev.srcChainId, ev.sender, ev.receiver, ev.payload, ev.nonce, sigs],
    chain: null, account: dst.wallet.account!,
  });
  await dst.pub.waitForTransactionReceipt({ hash });
  seen.add(ev.msgId);
  console.log(`  <- delivered on ${dst.name}  tx ${hash.slice(0, 10)}`);
}

async function poll(c: Chain) {
  const head = await c.pub.getBlockNumber();
  const safeHead = head > CONFIRMATIONS ? head - CONFIRMATIONS : 0n; // H-2
  if (c.lastBlock === 0n) { c.lastBlock = safeHead; saveCheckpoint(); return; } // first boot: no history replay
  if (safeHead <= c.lastBlock) return;
  const logs = await c.pub.getContractEvents({
    address: c.cfg.gateway, abi: GATEWAY_ABI, eventName: "MessageSent",
    fromBlock: c.lastBlock + 1n, toBlock: safeHead,
  });
  for (const log of logs) {
    const a = log.args as any;
    await handleMessage(c, {
      msgId: a.msgId, srcChainId: a.srcChainId, dstChainId: a.dstChainId,
      sender: a.sender, receiver: a.receiver, payload: a.payload, nonce: a.nonce,
    });
  }
  c.lastBlock = safeHead;
  saveCheckpoint();
}

// --- init + main loop ---------------------------------------------------
const ckpt = loadCheckpoint();
for (const c of chains) {
  c.evmChainId = await c.pub.getChainId();
  if (ckpt[c.name]) c.lastBlock = BigInt(ckpt[c.name]); // H-5: resume from checkpoint
}

console.log(`bamboo relay up | threshold ${THRESHOLD}/${attesters.length} | confirmations ${CONFIRMATIONS}`);
console.log(`chains: ${chains.map((c) => `${c.name}(logical=${c.cfg.logicalChainId},evm=${c.evmChainId},from=${c.lastBlock})`).join(", ")}`);
console.log(`attesters: ${attesters.map((a) => a.address).join(", ")}`);

while (true) {
  for (const c of chains) {
    try { await poll(c); }
    catch (e) { console.error(`poll ${c.name} error:`, (e as Error).message); }
  }
  await new Promise((r) => setTimeout(r, POLL_MS));
}
