# News: "28,005.6 ETH from Binance 16 sent to the same address at 20:26". How?
import time
from rpc import rpc

B16 = "0xdfd5293d8e347dfe59e90efd55b2956a1343963d"
EXP = "0x5227f603c1ee34ce3c06efe6477003bdfccb2f8c"
for b in range(26300770, 26300790):
    blk = rpc("eth_getBlockByNumber", hex(b), True)
    for t in blk["transactions"]:
        if (t["from"].lower() == B16 or (t.get("to") or "").lower() == B16) and int(t["value"], 16) > 10**21 or \
           (t["from"].lower() == B16 and (t.get("to") or "").lower() == EXP):
            print(f"block {b} {time.strftime('%H:%M:%S', time.gmtime(int(blk['timestamp'],16)))} idx {int(t['transactionIndex'],16)} type {int(t['type'],16)} "
                  f"from {t['from']} to {t['to']} value {int(t['value'],16)/1e18:,.4f} ETH sel {t['input'][:10]} auths {len(t.get('authorizationList') or [])} tx {t['hash']}")
    time.sleep(0.1)
for b in (26300770, 26300790):
    print(f"block {b}: B16 code={rpc('eth_getCode', B16, hex(b))} nonce={int(rpc('eth_getTransactionCount', B16, hex(b)),16)} ETH={int(rpc('eth_getBalance', B16, hex(b)),16)/1e18:,.2f}")
