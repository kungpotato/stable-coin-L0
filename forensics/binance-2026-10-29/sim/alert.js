#!/usr/bin/env node
// Event-driven alert monitor — the "detect" half of the EIP-7702 defence.
//
// Watches hot wallets for the two things the Binance drain did on-chain:
//   1) code flips from 0x to 0xef0100‖<contract>  = someone delegated it (EIP-7702)
//   2) balance drops sharply                      = funds are being swept out
//
// Unlike a polling loop, this does NOT spin on a timer. It opens ONE long-lived
// WebSocket, subscribes to `newHeads`, and the node PUSHES a message only when a
// block is produced — the script then checks code/balance just for that block.
// No busy loop, no per-tick process spawning; one connection watches many wallets.
// This is the production shape (same idea as chapter 8.9 `npm run alert`).
//
// Usage:  HOT=0xabc,0xdef RPC_WS=ws://127.0.0.1:8545 node alert.js
// Env:    DROP_ALERT_ETH (ETH drop that fires an alarm, default 1)
//         LOG (append log file, default alerts.log)
import { appendFileSync } from "node:fs";

const RPC_WS = process.env.RPC_WS || "ws://127.0.0.1:8545";
const WATCH = (process.env.HOT || "").split(",").map(s => s.trim()).filter(Boolean);
const DROP_WEI = BigInt(Math.round(parseFloat(process.env.DROP_ALERT_ETH || "1") * 1e6)) * 10n ** 12n;
const LOG = process.env.LOG || "alerts.log";
if (WATCH.length === 0) { console.error("set HOT=<addr>[,<addr>...]"); process.exit(1); }

const fmtEth = (wei) => (Number(wei / 10n ** 12n) / 1e6).toFixed(6);
const say = (line) => { const s = `${new Date().toTimeString().slice(0, 8)} ${line}`; console.log(s); try { appendFileSync(LOG, s + "\n"); } catch {} };

const state = new Map();                 // addr -> { code, bal }
let nextId = 1;
const pending = new Map();                // rpc id -> { kind, addr, blk }
const ws = new WebSocket(RPC_WS);

const rpc = (method, params, meta) => { const id = nextId++; if (meta) pending.set(id, meta); ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params })); };
const refresh = (addr, blk) => { rpc("eth_getCode", [addr, "latest"], { kind: "code", addr, blk }); rpc("eth_getBalance", [addr, "latest"], { kind: "bal", addr, blk }); };

ws.onopen = () => {
  say(`=== alert started  rpc=${RPC_WS}  watching=${WATCH.join(",")}  (event-driven: newHeads) ===`);
  rpc("eth_subscribe", ["newHeads"]);     // node pushes a message per new block
  for (const a of WATCH) refresh(a, "init"); // baseline snapshot so the first change is a diff
};

ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data.toString());

  // push notification: a new block arrived — check every watched wallet for it
  if (msg.method === "eth_subscription" && msg.params?.result?.number) {
    const blk = parseInt(msg.params.result.number, 16);
    for (const a of WATCH) refresh(a, blk);
    return;
  }

  // reply to one of our getCode / getBalance requests
  const meta = pending.get(msg.id);
  if (!meta) return;
  pending.delete(msg.id);
  const st = state.get(meta.addr) || {};

  if (meta.kind === "code") {
    const code = msg.result;
    if (st.code !== undefined && code !== st.code) {
      if (code.startsWith("0xef0100")) {
        say(`🔴 CRITICAL blk ${meta.blk}  ${meta.addr} DELEGATED via EIP-7702 -> 0x${code.slice(8)}`);
        say(`            RESPOND: freeze payouts; revoke (--auth 0x0 after burning nonce past the highest signed slip); move residual funds`);
      } else if (code === "0x") {
        say(`🟢 CLEARED  blk ${meta.blk}  ${meta.addr} delegation removed (code back to 0x)`);
      } else {
        say(`🟠 WARN     blk ${meta.blk}  ${meta.addr} code changed -> ${code}`);
      }
    }
    st.code = code;
  } else if (meta.kind === "bal") {
    const bal = BigInt(msg.result);
    if (st.bal !== undefined && st.bal - bal > DROP_WEI) {
      say(`🔴 CRITICAL blk ${meta.blk}  ${meta.addr} balance DROP ${fmtEth(st.bal - bal)} ETH  (${fmtEth(st.bal)} -> ${fmtEth(bal)})`);
      say(`            RESPOND: funds leaving — blacklist destination, alert exchanges, trace recipients`);
    }
    st.bal = bal;
  }
  state.set(meta.addr, st);
};

ws.onerror = (e) => say(`ws error: ${e.message || e.type}`);
ws.onclose = () => { say("ws closed"); process.exit(0); };
process.on("SIGINT", () => ws.close());
process.on("SIGTERM", () => ws.close());
