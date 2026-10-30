# Where did it go? Read every block from the sweep to now, keep every tx sent by the exploiter addresses
# (and any new address they fund with ETH), then aggregate their receipts' ERC-20 Transfer logs.
# Output: flows.jsonl (one line per tx) for summarise.py.   python3 follow.py [from_block] [to_block]
import json, sys, time
from concurrent.futures import ThreadPoolExecutor
from rpc import rpc

SEEDS = {"0x5227f603c1ee34ce3c06efe6477003bdfccb2f8c": "Exploiter 2",
         "0xa97bf7836f8a08f9ed91d41453d371493fae8d10": "exploiter (late sweeps)"}
TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
start = int(sys.argv[1]) if len(sys.argv) > 1 else 26300770
end = int(sys.argv[2]) if len(sys.argv) > 2 else int(rpc("eth_blockNumber"), 16)
watched = dict(SEEDS)


def get_block(n):
    for attempt in range(5):
        try:
            return rpc("eth_getBlockByNumber", hex(n), True)
        except Exception:
            time.sleep(1 + attempt)
    raise RuntimeError(f"block {n}")


def receipt(h):
    for attempt in range(5):
        try:
            return rpc("eth_getTransactionReceipt", h)
        except Exception:
            time.sleep(1 + attempt)


out = open("flows.jsonl", "w")
with ThreadPoolExecutor(6) as pool:
    for base in range(start, end + 1, 60):
        blocks = list(pool.map(get_block, range(base, min(base + 60, end + 1))))
        for blk in blocks:
            for t in blk["transactions"]:
                frm, to = t["from"].lower(), (t.get("to") or "").lower()
                if frm not in watched:
                    continue
                r = receipt(t["hash"])
                logs = [{"token": l["address"].lower(), "from": "0x" + l["topics"][1][26:], "to": "0x" + l["topics"][2][26:],
                         "amount": int(l["data"], 16) if l["data"] != "0x" else 0}
                        for l in r["logs"] if l["topics"] and l["topics"][0] == TRANSFER and len(l["topics"]) == 3]
                value = int(t["value"], 16)
                # follow ETH: a plain value transfer from a watched address to a fresh EOA joins the watch list
                if value >= 10**18 and to and t["input"] == "0x" and to not in watched and rpc("eth_getCode", to, "latest") == "0x":
                    watched[to] = f"hop from {watched[frm]}"
                out.write(json.dumps({"block": int(blk["number"], 16), "ts": int(blk["timestamp"], 16), "hash": t["hash"], "from": frm,
                                      "who": watched[frm], "to": to, "sel": t["input"][:10], "value": value,
                                      "status": r["status"], "transfers": logs}) + "\n")
        out.flush()
        print(f"scanned to {min(base + 59, end)} / {end}, watching {len(watched)}", flush=True)
json.dump(watched, open("watched.json", "w"), indent=1)
print("done", flush=True)
