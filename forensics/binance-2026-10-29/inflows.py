# Where did a sink's ETH come from? Sample its balance every 30 blocks, then find the exact block of each jump
# and the txs in it that sent value to it (top-level only; internal transfers show as a jump with no direct tx).
#   python3 inflows.py <address> [from_block]
import sys, time
from rpc import rpc

A = sys.argv[1].lower()
start = int(sys.argv[2]) if len(sys.argv) > 2 else 26300770
end = int(rpc("eth_blockNumber"), 16)
bal = lambda b: int(rpc("eth_getBalance", A, hex(b)), 16)
prev_b, prev = start, bal(start)
for b in list(range(start + 30, end, 30)) + [end]:
    cur = bal(b)
    if cur - prev >= 10 ** 20:  # +100 ETH or more in this window
        lo, hi = prev_b, b
        while hi - lo > 1:
            mid = (lo + hi) // 2
            lo, hi = (lo, mid) if bal(mid) > prev else (mid, hi)
        blk = rpc("eth_getBlockByNumber", hex(hi), True)
        direct = [t for t in blk["transactions"] if (t.get("to") or "").lower() == A and int(t["value"], 16) > 0]
        when = time.strftime("%m-%d %H:%M:%S", time.gmtime(int(blk["timestamp"], 16)))
        jump = (bal(hi) - bal(hi - 1)) / 1e18
        if direct:
            for t in direct:
                print(f"{when} block {hi} +{int(t['value'],16)/1e18:,.2f} ETH from {t['from']} tx {t['hash']}")
        else:
            print(f"{when} block {hi} +{jump:,.2f} ETH via an internal transfer (e.g. a swap paying out ETH)")
        prev_b, prev = hi, bal(hi)
    else:
        prev_b, prev = b, cur
    time.sleep(0.05)
print("now", bal(end) / 1e18, "ETH")
