# Forensics: Binance hot wallet sweep, 2026-10-29 (runbook topic 17)

Read-only scripts that reconstruct the incident from Ethereum mainnet. No keys, nothing sent.
Needs an RPC with historical state: default `https://eth.drpc.org`, override with `RPC_URL=...`.
Write-up: [binance-incident-2026-10-29.html](../../binance-incident-2026-10-29.html) (and workshop-lessons.html chapter 17).

| script | answers |
|---|---|
| `timeline.py` | the EIP-7702 delegation, its 50 authorizations, Binance 14's state block by block |
| `authorities.py` | who signed the 50 authorizations (`cast recover-authority`): all Binance 14 |
| `prep.py` | attacker funding (Tornado relayer withdrawal) and the sweeper contract deployment |
| `attacker_txs.py` | every tx of the attacker EOA: rehearsals, delegation, sweep, 9 re-sweeps |
| `b16.py` | Binance 16 signing a plain 28,005.6 ETH transfer to the exploiter |
| `flows.py <tx>...` | replay txs with `cast run` and list ETH / ERC-20 movements |
| `replay.sh` | full trace of the main sweep |
| `revoke.py` | when Binance removed the delegation |
| `follow.py` + `summarise.py` | every tx the exploiter addresses sent after the sweep (~10 min scan) |
| `inflows.py <addr>` | where an address's ETH came from, one hop back |
| `usdt_trail.py` | the 700M USDT that left before Tether froze it |

Facts from the chain are reproducible here; how the signatures were obtained, attribution and the total loss
were unconfirmed when this was written (2026-10-30).
