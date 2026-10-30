# Step 17.3: when was the delegation removed (code back to 0x)? Bisect, then show the tx.
import time
from rpc import rpc

B14 = "0x28c6c06298d514db089934071355e5743bf21d60"
SWEEP_TS = 1793305463  # block 26300770
lo, hi = 26300770, int(rpc("eth_blockNumber"), 16)
assert rpc("eth_getCode", B14, hex(hi)) == "0x", "still delegated at the tip"
while hi - lo > 1:
    mid = (lo + hi) // 2
    lo, hi = (lo, mid) if rpc("eth_getCode", B14, hex(mid)) == "0x" else (mid, hi)
    time.sleep(0.2)
blk = rpc("eth_getBlockByNumber", hex(hi), True)
ts = int(blk["timestamp"], 16)
print(f"cleared in block {hi} at {time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(ts))} UTC, {(ts - SWEEP_TS) / 60:.1f} min after the sweep")
for t in blk["transactions"]:
    if t["from"].lower() == B14 and t["type"] == "0x4":
        print("  by", t["hash"], "authorizations ->", [a["address"] for a in t["authorizationList"]])
