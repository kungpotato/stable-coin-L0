# Step 17.1-17.2: the EIP-7702 delegation of "Binance 14" and its state around the sweep, read from mainnet.
import time
from rpc import rpc

B14 = "0x28c6c06298d514db089934071355e5743bf21d60"
DELEGATION = "0xad99264d5532ae0dd04b2004eebda05f25657e70dacb764f7ac8d4ccd051298b"
USDT = "0xdac17f958d2ee523a2206206994597c13d831ec7"


def usdt(who, b):
    return int(rpc("eth_call", {"to": USDT, "data": "0x70a08231" + who[2:].rjust(64, "0")}, hex(b)), 16) / 1e6


tx = rpc("eth_getTransactionByHash", DELEGATION)
auths = tx["authorizationList"]
print(f"delegation tx type {int(tx['type'],16)} from {tx['from']} to {tx['to']}, {len(auths)} authorizations")
print("  delegate to:", sorted({a['address'] for a in auths}), "chainIds:", sorted({int(a['chainId'],16) for a in auths}))
n = sorted(int(a["nonce"], 16) for a in auths)
print(f"  authorization nonces {n[0]}..{n[-1]} (consecutive: {n == list(range(n[0], n[-1] + 1))})")
blk = rpc("eth_getBlockByNumber", tx["blockNumber"], True)
for t in blk["transactions"]:
    if t["from"].lower() == B14:
        print(f"  same block, index {int(t['transactionIndex'],16)}: Binance 14's own tx with nonce {int(t['nonce'],16)} (delegation is index {int(tx['transactionIndex'],16)})")
for b in (26300752, 26300753, 26300769, 26300770, 26300800):
    ts = int(rpc("eth_getBlockByNumber", hex(b), False)["timestamp"], 16)
    code = rpc("eth_getCode", B14, hex(b))
    eth = int(rpc("eth_getBalance", B14, hex(b)), 16) / 1e18
    print(f"block {b} {time.strftime('%H:%M:%S', time.gmtime(ts))} UTC: code={code or '0x'} ETH={eth:,.2f} USDT={usdt(B14, b):,.0f}")
    time.sleep(0.2)
