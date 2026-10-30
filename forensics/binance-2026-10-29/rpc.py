# Minimal JSON-RPC client for the forensics scripts. Needs an RPC that serves historical (archive) state:
# eth.drpc.org and rpc.mevblocker.io did on 2026-10-30; publicnode/1rpc ask for a token, and publicnode's
# eth_getLogs requires an address filter.  Override: RPC_URL=... python3 <script>.py
import json, os, urllib.request

R = os.environ.get("RPC_URL", "https://eth.drpc.org")


def rpc(method, *params):
    req = urllib.request.Request(R, data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": list(params)}).encode(),
                                 headers={"content-type": "application/json", "user-agent": "lab-forensics"})
    r = json.load(urllib.request.urlopen(req, timeout=60))
    if "error" in r:
        raise RuntimeError(r["error"])
    return r["result"]
