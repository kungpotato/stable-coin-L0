# Every tx the attacker EOA sent (nonce by nonce), plus how the delegation and sweep got into their blocks.
import time
from rpc import rpc

X = "0x7c8601d4645b93cea45f71e118a729332e6b5ca0"
START, END = 26289786, int(rpc("eth_blockNumber"), 16)


def nonce_at(b):
    return int(rpc("eth_getTransactionCount", X, hex(b)), 16)


def block_of_nonce(k):
    """block that contains the attacker's tx with nonce k (first block where nonce > k)"""
    lo, hi = START, END
    while hi - lo > 1:
        mid = (lo + hi) // 2
        lo, hi = (lo, mid) if nonce_at(mid) > k else (mid, hi)
        time.sleep(0.1)
    return hi


final = nonce_at(END)
seen = {}
for k in range(final):
    b = block_of_nonce(k)
    if b not in seen:
        seen[b] = rpc("eth_getBlockByNumber", hex(b), True)
    blk = seen[b]
    t = next(t for t in blk["transactions"] if t["from"].lower() == X and int(t["nonce"], 16) == k)
    r = rpc("eth_getTransactionReceipt", t["hash"])
    when = time.strftime("%m-%d %H:%M:%S", time.gmtime(int(blk["timestamp"], 16)))
    auths = t.get("authorizationList") or []
    extra = f" auths={len(auths)}->{auths[0]['address'][:10]}" if auths else ""
    to = t["to"] or f"CREATE {r.get('contractAddress')}"
    prio = int(t.get("maxPriorityFeePerGas", t.get("gasPrice", "0x0")), 16) / 1e9
    print(f"nonce {k:2} block {b} {when} idx {int(t['transactionIndex'],16):3}/{len(blk['transactions'])} type {int(t['type'],16)} "
          f"to {to} sel {t['input'][:10]} value {int(t['value'],16)/1e18:g} prio {prio:g}gwei status {r['status']}{extra}")
    print(f"           builder {blk['miner']} extra {bytes.fromhex(blk['extraData'][2:]).decode('utf8','replace')[:30]!r}")
