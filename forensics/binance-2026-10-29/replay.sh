#!/usr/bin/env bash
# Step 17.2: replay the sweep locally (cast forks mainnet at the parent block) and summarise the trace.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
RPC="${RPC_URL:-https://eth.drpc.org}"
SWEEP=0x53bd38b816c23e74134786c29a8c18d792777998a3b9326047b583100e88e2f3
cd "$(dirname "$0")"
echo "selector: $(cast 4byte 0x8a179be4)"
echo "attacker contract 0x63e8...6fae selectors:"; cast selectors "$(cast code 0x63e842b054bd624a465454d533c33f573e9c6fae --rpc-url "$RPC")"
cast run "$SWEEP" --rpc-url "$RPC" --quick > sweep-trace.txt
sed -n 2,3p sweep-trace.txt | cut -c1-160
echo "ERC-20 Transfer events out of Binance 14: $(grep -c 'emit Transfer(from: 0x28C6c06298d514Db089934071355E5743bf21d60' sweep-trace.txt)"
grep -E "Transaction successfully executed|Gas used" sweep-trace.txt
