# Attacker preparation: when the sweeper contract appeared and how the attacker EOA got its first gas money.
import time
from rpc import rpc

X = "0x7c8601d4645b93cea45f71e118a729332e6b5ca0"   # attacker EOA (sent the delegation and the sweep)
C = "0x63e842b054bd624a465454d533c33f573e9c6fae"   # sweeper contract (delegation target)
DELEG_BLOCK = 26300753


def ts(b):
    return time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(int(rpc("eth_getBlockByNumber", hex(b), False)["timestamp"], 16)))


def first_block(pred, lo, hi):
    """smallest block in (lo, hi] where pred(block) is true; pred(lo) false, pred(hi) true"""
    while hi - lo > 1:
        mid = (lo + hi) // 2
        lo, hi = (lo, mid) if pred(mid) else (mid, hi)
        time.sleep(0.15)
    return hi


lo = DELEG_BLOCK - 7200 * 7  # a week before
# contract creation
cb = first_block(lambda b: rpc("eth_getCode", C, hex(b)) != "0x", lo, DELEG_BLOCK)
blk = rpc("eth_getBlockByNumber", hex(cb), True)
for t in blk["transactions"]:
    if t["to"] is None:
        r = rpc("eth_getTransactionReceipt", t["hash"])
        if (r.get("contractAddress") or "").lower() == C:
            print(f"contract {C} deployed in block {cb} ({ts(cb)} UTC) by {t['from']} nonce {int(t['nonce'],16)} tx {t['hash']}")
# attacker EOA: first balance and first own tx
fb = first_block(lambda b: int(rpc("eth_getBalance", X, hex(b)), 16) > 0, lo, DELEG_BLOCK)
bal = int(rpc("eth_getBalance", X, hex(fb)), 16) / 1e18
print(f"attacker EOA first funded in block {fb} ({ts(fb)} UTC): balance {bal} ETH")
blk = rpc("eth_getBlockByNumber", hex(fb), True)
for t in blk["transactions"]:
    if (t.get("to") or "").lower() == X:
        print(f"  direct transfer tx {t['hash']} from {t['from']} value {int(t['value'],16)/1e18} ETH")
    elif t.get("input", "0x") != "0x" and X[2:] in t["input"].lower():
        print(f"  funded inside tx {t['hash']} from {t['from']} to {t['to']} (selector {t['input'][:10]}) - e.g. a relayer withdrawal")
n0 = first_block(lambda b: int(rpc("eth_getTransactionCount", X, hex(b)), 16) > 0, lo, DELEG_BLOCK)
print(f"attacker EOA first tx in block {n0} ({ts(n0)} UTC); nonce at delegation: {int(rpc('eth_getTransactionCount', X, hex(DELEG_BLOCK - 1)), 16)}")
