// Real-time alert worker (ADR 0008): watches both chains every few seconds and reports what the incident
// playbook (docs/runbooks/bridge-incident.md) needs to know, instead of waiting for someone to run check-supply.
//   🚨 FORGED_VERIFIED  a destination endpoint committed (PacketVerified) a payload the source never sent.
//                       Raised at COMMIT time, before lzReceive: the owner can still nilify it (see message).
//   🚨 SUPPLY           minted on the other chains > locked on the home chain (minus what the home leg holds)
//   🚨 POISONED         a real packet can never be delivered: its nonce was spent on another payload
//   ⚠️ STUCK            a real packet undelivered for STUCK_SECONDS (DVN / executor down, paused, config mismatch)
//   ⚠️ HELD             a credit was quarantined (inbound cap or blacklist): possible forgery or legit large transfer
//   ⚠️ RPC              a chain did not answer for 3 ticks
//   ℹ️ PAUSED/UNPAUSED, NILIFIED/BURNT/SKIPPED: who intervened, so the alert channel is the incident timeline
// Delivery: console, workers/state/alerts.jsonl, ALERT_WEBHOOK_URL (JSON {text, content}: Slack and Discord
// incoming webhooks), ALERT_DESKTOP=1 (macOS notification). Read-only: holds no key, changes nothing on chain.
// Run: npm run alert          env: TICK_MS (3000), STUCK_SECONDS (120)
import { appendFileSync, mkdirSync, readFileSync } from "node:fs";
import { execFile } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { decodeEventLog, getAddress, parseAbi, parseAbiItem, type Address, type Log } from "viem";
import { loadChains, byEid, scanPacketSent, inboundState, errMsg, log, sleep, type ChainCfg, type Packet } from "./lib.ts";
import { AlertBook, supplyBroken, forgedVerification, isStuck, formatAlert, type Alert, type Severity } from "./alertrules.ts";

const ROLE = "alert";
const TICK_MS = Number(process.env.TICK_MS ?? 3000);
const STUCK_SECONDS = Number(process.env.STUCK_SECONDS ?? 120);
const WEBHOOK = process.env.ALERT_WEBHOOK_URL;
const DESKTOP = process.env.ALERT_DESKTOP === "1";
const STATE = join(dirname(fileURLToPath(import.meta.url)), "..", "state");
const TOPO = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "..", "lz-potato", "config", "topology.json"), "utf8"));

const packetVerifiedEvent = parseAbiItem(
  "event PacketVerified((uint32 srcEid, bytes32 sender, uint64 nonce) origin, address receiver, bytes32 payloadHash)",
);
const endpointEvents = parseAbi([
  "event PacketNilified(uint32 srcEid, bytes32 sender, address receiver, uint64 nonce, bytes32 payloadHash)",
  "event PacketBurnt(uint32 srcEid, bytes32 sender, address receiver, uint64 nonce, bytes32 payloadHash)",
  "event InboundNonceSkipped(uint32 srcEid, bytes32 sender, address receiver, uint64 nonce)",
]);
const legEvents = parseAbi([
  "event Quarantined(address indexed to, uint32 srcEid, uint256 amount)",
  "event InboundCapExceeded(address indexed to, uint32 srcEid, uint256 amount, uint256 available)",
  "event Paused(address account)",
  "event Unpaused(address account)",
]);
const erc20 = parseAbi(["function totalSupply() view returns (uint256)", "function balanceOf(address) view returns (uint256)"]);
const quarantineAbi = parseAbi(["function totalQuarantined() view returns (uint256)"]);

// ---------------------------------------------------------------- what we watch

const chains = loadChains();
type Leg = { asset: string; chain: ChainCfg; address: Address; home: boolean };
/** Every bridged asset and its archived versions (POTATO, POTATO_V1, ...) deployed on two or more chains. */
function watchedAssets() {
  const out: { key: string; base: string; legs: Leg[] }[] = [];
  for (const base of Object.keys(TOPO.assets)) {
    const keys = new Set(chains.flatMap((c) => Object.keys(c.deployments).filter((k) => k === base || new RegExp(`^${base}_V\\d+$`).test(k))));
    for (const key of keys) {
      const legs = chains.filter((c) => c.deployments[key])
        .map((c) => ({ asset: key, chain: c, address: getAddress(c.deployments[key]), home: c.name === TOPO.assets[base].home }));
      if (legs.length >= 2) out.push({ key, base, legs });
    }
  }
  return out;
}
const assets = watchedAssets();
const legByAddress = new Map(assets.flatMap((a) => a.legs.map((l) => [`${l.chain.name}:${l.address.toLowerCase()}`, l] as const)));
const legName = (chain: ChainCfg, addr: string) => legByAddress.get(`${chain.name}:${addr.toLowerCase()}`)?.asset ?? `OApp ${addr.slice(0, 10)}…`;
const fmt = (base: string, v: bigint) => {
  const d = BigInt(TOPO.assets[base].decimals);
  const s = (v < 0n ? -v : v).toString().padStart(Number(d) + 1, "0");
  return `${v < 0n ? "-" : ""}${s.slice(0, -Number(d))}.${s.slice(-Number(d)).replace(/0+$/, "") || "0"}`;
};

// ---------------------------------------------------------------- delivery

const book = new AlertBook();
function notify(a: Alert | undefined) {
  if (!a) return;
  const line = formatAlert(a);
  log(ROLE, line);
  mkdirSync(STATE, { recursive: true });
  appendFileSync(join(STATE, "alerts.jsonl"), JSON.stringify(a) + "\n");
  if (WEBHOOK) {
    fetch(WEBHOOK, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text: line, content: line }) })
      .catch((e) => log(ROLE, `webhook failed: ${errMsg(e)}`));
  }
  if (DESKTOP && a.severity !== "info") {
    const text = line.replace(/["\\]/g, "'");
    execFile("osascript", ["-e", `display notification "${text}" with title "LayerZero lab alert"`], () => {});
  }
}
const raise = (id: string, sev: Severity, msg: string) => notify(book.raise(id, sev, msg));
const resolve = (id: string, msg: string) => notify(book.resolve(id, msg));
const event = (id: string, sev: Severity, msg: string) => notify(book.event(id, sev, msg));

// ---------------------------------------------------------------- state

/** Real packets by path+nonce -> payload hash, from every PacketSent seen on every chain. */
const sent = new Map<string, string>();
const key = (srcEid: number, sender: string, receiver: string, nonce: bigint) =>
  `${srcEid}-${sender.slice(-40).toLowerCase()}-${receiver.slice(-40).toLowerCase()}-${nonce}`;
/** Real packets not yet seen delivered, with the time this worker first saw them (not block time: chain clocks differ). */
const pending = new Map<string, { packet: Packet; firstSeen: number; poisonedTicks?: number }>();
const cursor = new Map<string, bigint>();
const rpcFails = new Map<string, number>();

async function logsOf(c: ChainCfg, from: bigint, to: bigint, address: Address | Address[], events: readonly any[]) {
  const out: Log[] = [];
  for (let start = from; start <= to; start += 1_000n) {
    const end = start + 999n < to ? start + 999n : to;
    out.push(...await c.pub.getLogs({ address, events, fromBlock: start, toBlock: end } as any));
  }
  return out;
}

// ---------------------------------------------------------------- per-tick checks

async function scanChain(c: ChainCfg, latest: bigint) {
  const from = cursor.get(c.name)! + 1n;
  if (from > latest) return;
  // 1. real packets leaving this chain
  for (const e of await scanPacketSent(c, from, latest)) {
    const k = key(e.packet.srcEid, e.packet.sender, e.packet.receiver, e.packet.nonce);
    sent.set(k, e.packet.payloadHash);
    pending.set(k, { packet: e.packet, firstSeen: Date.now() });
  }
  // 2. what this chain's endpoint accepted, and who intervened
  for (const l of await logsOf(c, from, latest, c.endpoint, [packetVerifiedEvent, ...endpointEvents])) {
    const ev = decodeEventLog({ abi: [packetVerifiedEvent, ...endpointEvents], data: l.data, topics: l.topics }) as any;
    const a = ev.args;
    if (ev.eventName === "PacketVerified") {
      const src = byEid(chains, a.origin.srcEid)?.name ?? `eid ${a.origin.srcEid}`;
      const k = key(a.origin.srcEid, a.origin.sender, a.receiver, a.origin.nonce);
      if (forgedVerification(sent.get(k), a.payloadHash)) {
        raise(`FORGED_VERIFIED:${c.name}:${k}`, "critical",
          `${legName(c, a.receiver)} ${src}->${c.name} nonce ${a.origin.nonce}: ${c.name} committed payload ${a.payloadHash.slice(0, 10)}… ` +
          `that ${src} never sent (tx ${l.transactionHash}). Before anyone executes it: pause the leg, then the OApp ` +
          `delegate calls endpoint.nilify(${a.receiver}, ${a.origin.srcEid}, ${a.origin.sender}, ${a.origin.nonce}, ${a.payloadHash}) on ${c.name}`);
      }
    } else {
      const what = ev.eventName === "PacketNilified" ? "NILIFIED" : ev.eventName === "PacketBurnt" ? "BURNT" : "SKIPPED";
      event(`${what}:${c.name}`, "info", `${legName(c, a.receiver)} on ${c.name}: nonce ${a.nonce} from eid ${a.srcEid} ${what.toLowerCase()} (tx ${l.transactionHash})`);
      if (what === "NILIFIED") {
        resolve(`FORGED_VERIFIED:${c.name}:${key(a.srcEid, a.sender, a.receiver, a.nonce)}`,
          `${legName(c, a.receiver)} nonce ${a.nonce} nilified on ${c.name}: the forged payload can no longer execute; the real packet can still be verified at that nonce`);
      }
    }
  }
  // 3. controls firing on our legs
  const legs = assets.flatMap((a) => a.legs).filter((l) => l.chain === c).map((l) => l.address);
  if (legs.length) {
    const logs = await logsOf(c, from, latest, legs, legEvents);
    const decoded = logs.map((l) => ({ l, ev: decodeEventLog({ abi: legEvents, data: l.data, topics: l.topics }) as any }));
    // a cap hold emits Quarantined + InboundCapExceeded in the same tx; a Quarantined alone is the blacklist
    const capTxs = new Set(decoded.filter((d) => d.ev.eventName === "InboundCapExceeded").map((d) => d.l.transactionHash));
    for (const { l, ev } of decoded) {
      const asset = legName(c, l.address);
      const base = asset.replace(/_V\d+$/, "");
      if (ev.eventName === "InboundCapExceeded") {
        event(`HELD:${c.name}:${asset}`, "warning", `${asset} on ${c.name}: ${fmt(base, ev.args.amount)} for ${ev.args.to} held, above the inbound cap ` +
          `(available ${fmt(base, ev.args.available)}). Forged message or legit large transfer: check FORGED_VERIFIED, then releaseQuarantined or keep it`);
      } else if (ev.eventName === "Quarantined") {
        if (!capTxs.has(l.transactionHash)) {
          event(`HELD:${c.name}:${asset}`, "warning", `${asset} on ${c.name}: ${fmt(base, ev.args.amount)} for blacklisted ${ev.args.to} quarantined (from eid ${ev.args.srcEid})`);
        }
      } else {
        event(`${ev.eventName.toUpperCase()}:${c.name}:${asset}`, "info", `${asset} on ${c.name} ${ev.eventName.toLowerCase()} by ${ev.args.account} (tx ${l.transactionHash})`);
      }
    }
  }
  cursor.set(c.name, latest);
}

async function checkSupply() {
  for (const a of assets) {
    const home = a.legs.find((l) => l.home);
    if (!home) continue;
    const c = home.chain;
    let locked: bigint;
    if (a.base === "POTATO") locked = await c.pub.getBalance({ address: home.address });
    else {
      const token = c.deployments[a.base === "USDC" ? "IssuerUSDC" : `${a.base}Token`];
      locked = await c.pub.readContract({ address: token, abi: erc20, functionName: "balanceOf", args: [home.address] });
    }
    let held = 0n;
    try { held = await c.pub.readContract({ address: home.address, abi: quarantineAbi, functionName: "totalQuarantined" }); } catch { /* legs before ADR 0005/0006 */ }
    let minted = 0n;
    for (const l of a.legs.filter((x) => !x.home)) minted += await l.chain.pub.readContract({ address: l.address, abi: erc20, functionName: "totalSupply" });
    const id = `SUPPLY:${a.key}`;
    if (supplyBroken(locked, held, minted)) {
      raise(id, "critical", `${a.key}: minted ${fmt(a.base, minted)} > locked ${fmt(a.base, locked - held)} on ${c.name} ` +
        `(unbacked ${fmt(a.base, minted - (locked - held))}). Pause every leg, then follow docs/runbooks/bridge-incident.md`);
    } else {
      resolve(id, `${a.key}: locked ${fmt(a.base, locked - held)} >= minted ${fmt(a.base, minted)} again`);
    }
  }
}

async function checkPending() {
  for (const [k, p] of pending) {
    const dst = byEid(chains, p.packet.dstEid);
    if (!dst) { pending.delete(k); continue; }
    const state = await inboundState(dst, p.packet);
    const src = byEid(chains, p.packet.srcEid)?.name ?? p.packet.srcEid;
    const name = `${legName(dst, p.packet.receiver)} ${src}->${dst.name} nonce ${p.packet.nonce}`;
    if (state !== "poisoned") p.poisonedTicks = 0;
    if (state === "delivered") {
      pending.delete(k);
      resolve(`STUCK:${k}`, `${name} delivered`);
    } else if (state === "poisoned" && (p.poisonedTicks = (p.poisonedTicks ?? 0) + 1) < 2) {
      continue; // confirm on the next tick: a log at the chain tip may not be indexed yet
    } else if (state === "poisoned") {
      pending.delete(k);
      resolve(`STUCK:${k}`, `${name} no longer stuck: see POISONED`);
      raise(`POISONED:${k}`, "critical", `${name}: ${dst.name} spent this nonce on a different payload, the real message can never be delivered. ` +
        `Refund the sender on ${src} (playbook step 4)`);
    } else if (isStuck(p.firstSeen, Date.now(), STUCK_SECONDS)) {
      raise(`STUCK:${k}`, "warning", `${name} ${state} for over ${STUCK_SECONDS}s (DVN or executor down? leg paused? send/receive config mismatch?)`);
    }
  }
}

// ---------------------------------------------------------------- main loop

async function main() {
  log(ROLE, `watching ${assets.map((a) => a.key).join(", ")} on ${chains.map((c) => c.name).join(", ")}; tick ${TICK_MS}ms, stuck after ${STUCK_SECONDS}s` +
    `${WEBHOOK ? ", webhook on" : ""}${DESKTOP ? ", desktop on" : ""}`);
  // history: index every real packet ever sent, so verifications of older packets can be matched; alert only on new blocks
  for (const c of chains) {
    const latest = await c.pub.getBlockNumber();
    for (const e of await scanPacketSent(c, 1n, latest)) sent.set(key(e.packet.srcEid, e.packet.sender, e.packet.receiver, e.packet.nonce), e.packet.payloadHash);
    cursor.set(c.name, latest);
  }
  log(ROLE, `indexed ${sent.size} past packets`);
  for (;;) {
    // sources first: a real packet is always indexed before its verification shows up on the other chain
    const latest = new Map<string, bigint>();
    for (const c of chains) {
      try {
        latest.set(c.name, await c.pub.getBlockNumber());
        if ((rpcFails.get(c.name) ?? 0) >= 3) resolve(`RPC:${c.name}`, `${c.name} answers again`);
        rpcFails.set(c.name, 0);
      } catch (e) {
        const n = (rpcFails.get(c.name) ?? 0) + 1;
        rpcFails.set(c.name, n);
        if (n >= 3) raise(`RPC:${c.name}`, "warning", `${c.name} RPC not answering for ${n} ticks: ${errMsg(e)}`);
      }
    }
    try {
      for (const c of chains) if (latest.has(c.name)) await scanChain(c, latest.get(c.name)!);
      if (latest.size === chains.length) {
        await checkSupply();
        await checkPending();
      }
    } catch (e) {
      log(ROLE, `ERROR ${errMsg(e)}`);
    }
    await sleep(TICK_MS);
  }
}

main();
