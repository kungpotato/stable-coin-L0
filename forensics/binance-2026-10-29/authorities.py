# Who signed the 50 EIP-7702 authorizations? cast recover-authority on each (needs Foundry >= 1.x).
import collections, json, os, subprocess
from rpc import rpc

DELEGATION = "0xad99264d5532ae0dd04b2004eebda05f25657e70dacb764f7ac8d4ccd051298b"
B14 = "0x28c6c06298d514db089934071355e5743bf21d60"
cast = os.path.expanduser("~/.foundry/bin/cast")
tx = rpc("eth_getTransactionByHash", DELEGATION)
signers = collections.Counter()
for a in tx["authorizationList"]:
    auth = {"chainId": a["chainId"], "address": a["address"], "nonce": a["nonce"],
            "yParity": a.get("yParity", a.get("v")), "r": a["r"], "s": a["s"]}
    out = subprocess.run([cast, "recover-authority", json.dumps(auth)], capture_output=True, text=True)
    signers[(out.stdout.strip() or out.stderr.strip()[:80]).lower()] += 1
for who, n in signers.items():
    print(f"{n} authorization(s) signed by {who}{'  <- Binance 14' if who == B14 else ''}")
