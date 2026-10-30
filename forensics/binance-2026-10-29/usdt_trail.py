# USDT that left Exploiter 2 at 20:30-20:33 (700M to two fresh addresses): what did those addresses do with it?
# Their nonces are small, so find each of their txs by nonce and read its receipt.
import time
from rpc import rpc

USDT = "0xdac17f958d2ee523a2206206994597c13d831ec7"
TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
HOPS = {"0x9749292d74fd460982d0912ea9515ea24736c762": "USDT hop A (500M)",
        "0x0ddf0480016e6bcb2c1f5d190d221fba1320697e": "USDT hop B (200M)"}
START, END = 26300770, int(rpc("eth_blockNumber"), 16)
for addr, label in HOPS.items():
    n_end = int(rpc("eth_getTransactionCount", addr, hex(END)), 16)
    print(f"\n{label} {addr}: {n_end} tx(s)")
    for k in range(n_end):
        lo, hi = START, END
        while hi - lo > 1:
            mid = (lo + hi) // 2
            lo, hi = (lo, mid) if int(rpc("eth_getTransactionCount", addr, hex(mid)), 16) > k else (mid, hi)
            time.sleep(0.05)
        blk = rpc("eth_getBlockByNumber", hex(hi), True)
        t = next(t for t in blk["transactions"] if t["from"].lower() == addr and int(t["nonce"], 16) == k)
        r = rpc("eth_getTransactionReceipt", t["hash"])
        moved = [(int(l["data"], 16) / 1e6, "0x" + l["topics"][2][26:]) for l in r["logs"]
                 if l["address"].lower() == USDT and l["topics"][0] == TRANSFER and l["topics"][1][26:] == addr[2:]]
        when = time.strftime("%m-%d %H:%M:%S", time.gmtime(int(blk["timestamp"], 16)))
        what = "; ".join(f"USDT {a:,.2f} -> {d}" for a, d in moved) or f"to {t['to']} sel {t['input'][:10]} value {int(t['value'],16)/1e18:g} ETH"
        print(f"  nonce {k:2} {when} status {r['status']} {what}")
