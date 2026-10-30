# Collect every piece of on-chain evidence used in binance-incident-2026-10-29.html into evidence.json,
# straight from the chain (no hand-copied numbers). Read-only. Takes ~15 minutes on a public RPC.
#   python3 evidence.py            (uses flows.jsonl from follow.py for the post-sweep activity, if present)
import json, os, re, subprocess, time
from rpc import rpc, R

cast = os.path.expanduser("~/.foundry/bin/cast")
B14 = "0x28c6c06298d514db089934071355e5743bf21d60"
B16 = "0xdfd5293d8e347dfe59e90efd55b2956a1343963d"
X = "0x7c8601d4645b93cea45f71e118a729332e6b5ca0"          # attacker EOA
SWEEPER = "0x63e842b054bd624a465454d533c33f573e9c6fae"
EXP2 = "0x5227f603c1ee34ce3c06efe6477003bdfccb2f8c"
LATE = "0xa97bf7836f8a08f9ed91d41453d371493fae8d10"
SMART = "0xee7ae85f2fe2239e27d9c1e23fffe168d63b4055"
USDT, USDC = "0xdac17f958d2ee523a2206206994597c13d831ec7", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
DELEGATION = "0xad99264d5532ae0dd04b2004eebda05f25657e70dacb764f7ac8d4ccd051298b"
B16_TX = "0x51f263fa50966df6bbd7f8c6e6e99e3791c94444f7c4343b2fef1ee2d62fd39f"
REVOKE = "0xafbf94c92a8d749988411669fa14d4f8866d9b4420b4ebd299f28e958dac7209"
FUNDING = "0xd9e59064d7681439e732a5eb0e2a167b9a23f161d3ce4c8ef111ca824fe59008"
TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
ev = {"rpc": R, "collected_at": time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime())}


def retry(f, *a):
    for i in range(6):
        try:
            return f(*a)
        except Exception:
            time.sleep(1 + i)
    return f(*a)


def call(*args):
    return subprocess.run([cast, *args, "--rpc-url", R], capture_output=True, text=True).stdout.strip()


def blk(n, full=False):
    return retry(rpc, "eth_getBlockByNumber", n if isinstance(n, str) else hex(n), full)


def tx_info(h):
    t = retry(rpc, "eth_getTransactionByHash", h)
    r = retry(rpc, "eth_getTransactionReceipt", h)
    b = blk(t["blockNumber"])
    return {"hash": h, "block": int(t["blockNumber"], 16), "ts": int(b["timestamp"], 16), "index": int(t["transactionIndex"], 16),
            "txs_in_block": len(b["transactions"]), "type": int(t["type"], 16), "from": t["from"].lower(), "to": (t.get("to") or "").lower(),
            "nonce": int(t["nonce"], 16), "value_eth": int(t["value"], 16) / 1e18, "selector": t["input"][:10],
            "input_bytes": len(t["input"]) // 2 - 1, "status": r["status"], "gas_used": int(r["gasUsed"], 16),
            "priority_gwei": int(t.get("maxPriorityFeePerGas", t.get("gasPrice", "0x0")), 16) / 1e9,
            "builder": b["miner"].lower(), "builder_tag": bytes.fromhex(b["extraData"][2:]).decode("utf8", "replace").strip(),
            "contract_created": (r.get("contractAddress") or "").lower() or None,
            "authorizations": len(t.get("authorizationList") or [])}


_meta = {}


def token_meta(a):
    if a not in _meta:
        sym = call("call", a, "symbol()(string)").strip('"')
        dec = call("call", a, "decimals()(uint8)").split()
        _meta[a] = (sym or a[:10], int(dec[0]) if dec else 18)
    return _meta[a]


def replay(h):
    """cast run the tx; native value calls and ERC-20 Transfer events (attributed to the proxy, not the implementation)"""
    trace = subprocess.run([cast, "run", h, "--rpc-url", R, "--quick"], capture_output=True, text=True).stdout
    current, eth, toks = None, [], []
    for line in trace.splitlines():
        m = re.search(r"\] (0x[0-9a-fA-F]{40})::", line)
        if m and "[delegatecall]" not in line:
            current = m.group(1).lower()
        v = re.search(r"(0x[0-9a-fA-F]{40})::\w*\{value: (\d+)\}", line)
        if v and int(v.group(2)) > 0:
            eth.append({"to": v.group(1).lower(), "eth": int(v.group(2)) / 1e18})
        t = re.search(r"emit Transfer\(from: (0x[0-9a-fA-F]{40}), to: (0x[0-9a-fA-F]{40}), (?:value|amount|wad|tokens|_value): (\d+)", line)
        if t and current:
            sym, dec = token_meta(current)
            toks.append({"token": current, "symbol": sym, "from": t.group(1).lower(), "to": t.group(2).lower(), "amount": int(t.group(3)) / 10 ** dec})
    top = trace.splitlines()[1].strip() if len(trace.splitlines()) > 1 else ""
    return {"call": re.sub(r"^\[\d+\] ", "", top)[:300], "eth": eth, "tokens": toks}


# --- 1. funding, deployment, attacker txs -------------------------------------------------------------------------
print("attacker txs…", flush=True)
ev["funding"] = tx_info(FUNDING)
ev["funding"]["attacker_balance_after"] = int(rpc("eth_getBalance", X, hex(ev["funding"]["block"])), 16) / 1e18
START, END = 26289786, int(rpc("eth_blockNumber"), 16)
ev["snapshot_block"] = END
attacker = []
for k in range(int(rpc("eth_getTransactionCount", X, hex(END)), 16)):
    lo, hi = START, END
    while hi - lo > 1:
        mid = (lo + hi) // 2
        lo, hi = (lo, mid) if int(retry(rpc, "eth_getTransactionCount", X, hex(mid)), 16) > k else (mid, hi)
    t = next(t for t in blk(hi, True)["transactions"] if t["from"].lower() == X and int(t["nonce"], 16) == k)
    info = tx_info(t["hash"])
    if t.get("authorizationList"):
        info["delegated_accounts_target"] = sorted({a["address"].lower() for a in t["authorizationList"]})
    attacker.append(info)
ev["attacker_txs"] = attacker

# --- 2. the delegation and its 50 authorizations ---------------------------------------------------------------------
print("authorizations…", flush=True)
ev["delegation"] = tx_info(DELEGATION)
dtx = rpc("eth_getTransactionByHash", DELEGATION)
own = [t for t in blk(ev["delegation"]["block"], True)["transactions"] if t["from"].lower() == B14]
ev["delegation"]["b14_own_txs_same_block"] = [{"hash": t["hash"], "index": int(t["transactionIndex"], 16), "nonce": int(t["nonce"], 16)} for t in own]
nonce_at_delegation = max([int(t["nonce"], 16) for t in own if int(t["transactionIndex"], 16) < ev["delegation"]["index"]], default=-1) + 1
auths = []
for a in dtx["authorizationList"]:
    payload = {"chainId": a["chainId"], "address": a["address"], "nonce": a["nonce"], "yParity": a.get("yParity", a.get("v")), "r": a["r"], "s": a["s"]}
    signer = subprocess.run([cast, "recover-authority", json.dumps(payload)], capture_output=True, text=True).stdout.strip().lower()
    auths.append({"nonce": int(a["nonce"], 16), "chainId": int(a["chainId"], 16), "address": a["address"].lower(), "yParity": int(payload["yParity"], 16),
                  "r": a["r"], "s": a["s"], "signer": signer, "used": int(a["nonce"], 16) == nonce_at_delegation})
ev["authorizations"] = auths

# --- 3. wallet state over the incident -------------------------------------------------------------------------------
print("state…", flush=True)
state = []
for b in (26300752, 26300753, 26300769, 26300770, 26300800, 26301895, 26301896):
    usdt = int(rpc("eth_call", {"to": USDT, "data": "0x70a08231" + B14[2:].rjust(64, "0")}, hex(b)), 16) / 1e6
    state.append({"block": b, "ts": int(blk(b)["timestamp"], 16), "code": rpc("eth_getCode", B14, hex(b)),
                  "nonce": int(rpc("eth_getTransactionCount", B14, hex(b)), 16), "eth": int(rpc("eth_getBalance", B14, hex(b)), 16) / 1e18, "usdt": usdt})
ev["b14_state"] = state
ev["sweeper"] = {"address": SWEEPER, "code_bytes": len(rpc("eth_getCode", SWEEPER, "latest")) // 2 - 1,
                 "selectors": call("selectors", rpc("eth_getCode", SWEEPER, "latest")).splitlines()}
ev["smart_wallet"] = {"address": SMART, "code_bytes": len(rpc("eth_getCode", SMART, "latest")) // 2 - 1}

# --- 4. replays: main sweep, follow-up sweeps, USDC pulls, rehearsals --------------------------------------------------
print("replays…", flush=True)
ev["replays"] = {}
for t in attacker:
    if t["selector"] in ("0x8a179be4", "0x043ff9d2", "0x4782f779"):
        ev["replays"][t["hash"]] = replay(t["hash"])
        print("  replayed nonce", t["nonce"], flush=True)

# --- 5. Binance 16 and the revoke ------------------------------------------------------------------------------------
ev["b16_tx"] = tx_info(B16_TX)
ev["b16_tx"]["b16_code_before"] = rpc("eth_getCode", B16, hex(ev["b16_tx"]["block"] - 1))
ev["b16_tx"]["b16_eth_before"] = int(rpc("eth_getBalance", B16, hex(ev["b16_tx"]["block"] - 1)), 16) / 1e18
ev["b16_tx"]["b16_eth_after"] = int(rpc("eth_getBalance", B16, hex(ev["b16_tx"]["block"])), 16) / 1e18
ev["revoke"] = tx_info(REVOKE)
ev["revoke"]["auth_targets"] = [a["address"].lower() for a in rpc("eth_getTransactionByHash", REVOKE)["authorizationList"]]

# --- 6. money trail --------------------------------------------------------------------------------------------------
print("money trail…", flush=True)
if os.path.exists("flows.jsonl"):
    rows = [json.loads(l) for l in open("flows.jsonl")]
    ev["post_sweep_activity"] = {
        "scanned_to_block": max(r["block"] for r in rows),
        "tx_count": {a: sum(r["from"] == a for r in rows) for a in {r["from"] for r in rows}},
        "eth_moves": [{k: r[k] for k in ("hash", "block", "ts", "from", "to")} | {"eth": r["value"] / 1e18} for r in rows if r["value"] >= 10 ** 18],
        "routers": {}}
    for r in rows:
        key = f"{r['from']}|{r['to']}"
        ev["post_sweep_activity"]["routers"][key] = ev["post_sweep_activity"]["routers"].get(key, 0) + 1
    usdt_out = [{"hash": r["hash"], "ts": r["ts"], "to": t["to"], "amount": t["amount"] / 1e6}
                for r in rows for t in r["transfers"] if t["from"] == EXP2 and t["token"] == USDT]
    ev["exp2_usdt_out"] = usdt_out
# USDT hops: every tx of the two hop addresses
hops = {"0x9749292d74fd460982d0912ea9515ea24736c762": "hop A", "0x0ddf0480016e6bcb2c1f5d190d221fba1320697e": "hop B"}
ev["usdt_hops"] = {}
for addr, label in hops.items():
    txs = []
    for k in range(int(rpc("eth_getTransactionCount", addr, "latest"), 16)):
        lo, hi = 26300770, END
        while hi - lo > 1:
            mid = (lo + hi) // 2
            lo, hi = (lo, mid) if int(retry(rpc, "eth_getTransactionCount", addr, hex(mid)), 16) > k else (mid, hi)
        t = next(t for t in blk(hi, True)["transactions"] if t["from"].lower() == addr and int(t["nonce"], 16) == k)
        info = tx_info(t["hash"])
        rc = rpc("eth_getTransactionReceipt", t["hash"])
        info["usdt_out"] = [{"to": "0x" + l["topics"][2][26:], "amount": int(l["data"], 16) / 1e6} for l in rc["logs"]
                            if l["address"].lower() == USDT and l["topics"][0] == TRANSFER and l["topics"][1][26:] == addr[2:]]
        txs.append(info)
    ev["usdt_hops"][label] = {"address": addr, "txs": txs}
# ETH chain into 0x897c (verified hop by hop with balances)
chain = ["0x8d53903625b8e839b9df4bd28b0efb1cd6b8639a", "0x77edef23fbd05921c26fe29fcc3a65e14d2ac3eb", "0x7aa4d3029e4c6a8e916300014ad95b6d6c03bfd1",
         "0xccbef95633adb5cd2b5038db5a38d77e726ca263", "0xb171ca86f82070282138352ff7111b494060c8c3", "0x897c80d1a9729e94460e2bd93178bd5215158df3"]
ev["chain_897c"] = [tx_info(h) for h in ("0x9e776556cf486ec516e12eeaf38fbd4ddd820f3f7e19cb999f9465a14c0c4673", "0x1171d7baec803ba6b62efb979e49e9dc6183235060af54570a7630e54737ceea",
                                          "0x6d7e5cde8cc83e22052eec4dd2aa4239f8f97af0630a7bc34a2f9d8ffd991996", "0x3ccb1b3b05611a5c588e32deffbbb553650a97def0e9d129540cfd9fe68e2c5a",
                                          "0x2552fea8c4e4e9e9251ef4ec82ea8cfc214feda8c21e77f4ce07779b1d561fb1", "0x1ef5fae0b671cb2727238df3b51a376d4bb944352a0fad1402b930166e09699c",
                                          "0x654cb44f9b09321cc86fab010323473b33da2e5a8f6d362ba0d751ee8c158dd2")]
for a in chain:
    ev.setdefault("chain_codes", {})[a] = rpc("eth_getCode", a, "latest")

# --- 7. balances and freezes now -------------------------------------------------------------------------------------
print("balances…", flush=True)
watch = {EXP2: "Exploiter 2", LATE: "late-sweep sink", "0x8532fa14acaf483729c449b8458aeddb900543d4": "ETH sink 1",
         "0xc887af690e0301cd4edbbce8f8d31b4ec65b286a": "ETH sink 2", "0x897c80d1a9729e94460e2bd93178bd5215158df3": "ETH sink 3",
         "0xc2096a12ebe0944f4d39e59979f485afd92d850a": "ETH sink 4", "0x9749292d74fd460982d0912ea9515ea24736c762": "USDT hop A",
         "0x0ddf0480016e6bcb2c1f5d190d221fba1320697e": "USDT hop B", "0x8d53903625b8e839b9df4bd28b0efb1cd6b8639a": "USDT→ETH hop",
         "0x811f15855476156ebf86ba3b84fafb8ceaa4e84c": "175M USDT hop", "0x5c23023ca6633f91ded909b4a753a3ca00fea4fc": "RLUSD hop",
         X: "attacker EOA", B14: "Binance 14", B16: "Binance 16"}
bal = []
for a, label in watch.items():
    bal.append({"address": a, "label": label, "eth": int(rpc("eth_getBalance", a, hex(END)), 16) / 1e18,
                "nonce": int(rpc("eth_getTransactionCount", a, hex(END)), 16), "code": rpc("eth_getCode", a, hex(END))[:48],
                "usdt": int(call("call", USDT, "balanceOf(address)(uint256)", a).split()[0]) / 1e6,
                "usdc": int(call("call", USDC, "balanceOf(address)(uint256)", a).split()[0]) / 1e6,
                "tether_blacklisted": call("call", USDT, "isBlackListed(address)(bool)", a) == "true",
                "circle_blacklisted": call("call", USDC, "isBlacklisted(address)(bool)", a) == "true"})
ev["balances"] = bal
json.dump(ev, open("evidence.json", "w"), indent=1)
print("wrote evidence.json", flush=True)
