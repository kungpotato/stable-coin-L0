#!/usr/bin/env bash
# Counterpart chain for the workshop (topic 10): anvil that keeps its state across restarts,
# because it is the HOME chain of USDC. Losing its state = losing the canonical USDC supply.
#   start: potato-localnet/anvil-home.sh
#   stop:  pkill -f "anvil --port 28545"   (SIGTERM -> anvil dumps state before exit)
set -euo pipefail
cd "$(dirname "$0")"
ANVIL="${ANVIL:-$HOME/.foundry/bin/anvil}"

if pgrep -f "anvil --port 28545" >/dev/null; then
  echo "anvil :28545 already running" >&2; exit 1
fi

# --state loads anvil-home-state.json if present and dumps on exit; --state-interval also
# dumps every 10s so a crash (kill -9) loses at most 10s of blocks.
nohup "$ANVIL" --port 28545 --chain-id 31338 --hardfork prague --block-time 1 \
  --state anvil-home-state.json --state-interval 10 > anvil-home.log 2>&1 &
echo "anvil-home pid $! (log: potato-localnet/anvil-home.log)"
