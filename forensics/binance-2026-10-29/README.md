# Forensics: Binance hot wallet sweep, 2026-10-29 (runbook topic 17)

Read-only scripts that reconstruct the EIP-7702 delegation and sweep of "Binance 14"
(`0x28C6c06298d514Db089934071355E5743bf21d60`) from Ethereum mainnet. No keys, nothing sent.

    cd forensics/binance-2026-10-29
    python3 timeline.py     # delegation tx, the 50 authorizations, wallet state block by block
    ./replay.sh             # cast run: replay the sweep locally with a full trace (writes sweep-trace.txt)
    python3 revoke.py       # when the delegation was removed

Findings and context: workshop-lessons.html, chapter "กรณีศึกษา: Binance".
Facts from the chain are reproducible here; everything else (how the signatures were obtained, attribution,
total loss) was unconfirmed when this was written (2026-10-30).
