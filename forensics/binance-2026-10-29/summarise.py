# Summarise flows.jsonl (from follow.py): what each watched address sent, to whom, and which assets left it.
import collections, json, os, subprocess, time, urllib.request
from rpc import rpc, R

cast = os.path.expanduser("~/.foundry/bin/cast")
watched = json.load(open("watched.json")) if os.path.exists("watched.json") else {}
rows = [json.loads(l) for l in open("flows.jsonl")]
KNOWN = {  # well-known mainnet contracts (checked against Sourcify where possible)
    "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": "WETH",
    "0xd90e2f925da726b50c4ed8d0fb90ad053324f31b": "Tornado Cash Router",
    "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2": "Aave V3 Pool",
    "0x9008d19f58aabd9ed0d60971565aa8510560ab41": "CoW Protocol Settlement",
    "0x111111125421ca6dc452d289314280a0f8842a65": "1inch Router v6",
    "0x66a9893cc07d91d95644aedd05d03f95e1dba8af": "Uniswap Universal Router",
    "0xd37bbe5744d730a1d98d8dc97c42f0ca46ad7146": "THORChain Router",
}
_names, _tok = {}, {}


def name(addr):
    if addr in KNOWN:
        return KNOWN[addr]
    if addr in watched:
        return f"[{watched[addr]}]"
    if addr not in _names:
        label = None
        try:
            with urllib.request.urlopen(f"https://sourcify.dev/server/v2/contract/1/{addr}?fields=compilation", timeout=20) as r:
                label = json.load(r).get("compilation", {}).get("name")
        except Exception:
            pass
        if not label:
            label = "EOA" if rpc("eth_getCode", addr, "latest") == "0x" else "contract (unverified)"
        _names[addr] = f"{label} {addr[:8]}…{addr[-4:]}"
        time.sleep(0.2)
    return _names[addr]


def token(addr):
    if addr not in _tok:
        sym = subprocess.run([cast, "call", addr, "symbol()(string)", "--rpc-url", R], capture_output=True, text=True).stdout.strip().strip('"')
        dec = subprocess.run([cast, "call", addr, "decimals()(uint8)", "--rpc-url", R], capture_output=True, text=True).stdout.split()
        _tok[addr] = (sym or addr[:8], int(dec[0]) if dec else 18)
    return _tok[addr]


print(f"{len(rows)} txs from {len({r['from'] for r in rows})} watched addresses, "
      f"{time.strftime('%m-%d %H:%M', time.gmtime(rows[0]['ts']))} .. {time.strftime('%m-%d %H:%M', time.gmtime(rows[-1]['ts']))} UTC")
by_from = collections.defaultdict(list)
for r in rows:
    by_from[r["from"]].append(r)
for frm, txs in by_from.items():
    print(f"\n### {watched.get(frm, frm)} {frm}: {len(txs)} txs, failed {sum(r['status'] != '0x1' for r in txs)}")
    dest = collections.Counter(r["to"] for r in txs)
    for to, n in dest.most_common(8):
        eth = sum(r["value"] for r in txs if r["to"] == to) / 1e18
        print(f"   {n:4} tx -> {name(to)}{f'  ETH {eth:,.2f}' if eth else ''}")
    out = collections.defaultdict(int)
    for r in txs:
        for t in r["transfers"]:
            if t["from"] == frm:
                out[t["token"]] += t["amount"]
    print("   tokens sent out:", ", ".join(f"{token(k)[0]} {v / 10 ** token(k)[1]:,.2f}" for k, v in sorted(out.items(), key=lambda kv: -kv[1])[:8]) or "none")
    eth_out = sum(r["value"] for r in txs) / 1e18
    print(f"   ETH sent as tx value: {eth_out:,.2f}")
