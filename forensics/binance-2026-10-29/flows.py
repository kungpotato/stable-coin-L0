# Replay txs with `cast run` and summarise what moved: native value transfers and ERC-20 Transfer events.
#   python3 flows.py <txhash> [<txhash> ...]
import os, re, subprocess, sys
from rpc import rpc, R

cast = os.path.expanduser("~/.foundry/bin/cast")
_meta = {}


def meta(token):
    if token not in _meta:
        try:
            sym = subprocess.run([cast, "call", token, "symbol()(string)", "--rpc-url", R], capture_output=True, text=True).stdout.strip().strip('"')
            dec = int(subprocess.run([cast, "call", token, "decimals()(uint8)", "--rpc-url", R], capture_output=True, text=True).stdout.split()[0])
        except Exception:
            sym, dec = token[:10], 18
        _meta[token] = (sym or token[:10], dec)
    return _meta[token]


def short(a):
    return a[:6] + "…" + a[-4:]


for h in sys.argv[1:]:
    trace = subprocess.run([cast, "run", h, "--rpc-url", R, "--quick"], capture_output=True, text=True).stdout
    tx = rpc("eth_getTransactionByHash", h)
    head = trace.splitlines()[1].strip()[:150] if len(trace.splitlines()) > 1 else "?"
    print(f"\n== {h[:12]}… block {int(tx['blockNumber'],16)}  {head}")
    current = None
    for line in trace.splitlines():
        m = re.search(r"\] (0x[0-9a-fA-F]{40})::", line)
        if m and "[delegatecall]" not in line:  # events of a proxy are emitted by the proxy, not its implementation
            current = m.group(1)
        v = re.search(r"(0x[0-9a-fA-F]{40})::\w*\{value: (\d+)\}", line)
        if v and int(v.group(2)) > 0:
            print(f"   ETH  {int(v.group(2))/1e18:>22,.4f} -> {short(v.group(1))}")
        t = re.search(r"emit Transfer\(from: (0x[0-9a-fA-F]{40}), to: (0x[0-9a-fA-F]{40}), (?:value|amount|wad|tokens): (\d+)", line)
        if t and current:
            sym, dec = meta(current)
            print(f"   {sym:<6} {int(t.group(3))/10**dec:>22,.4f}  {short(t.group(1))} -> {short(t.group(2))}")
