#!/usr/bin/env bash
# Topic 12: show the cosmos/evm eth_getLogs bug on potato (potato-chain/docs/known-issues.md):
# right after a tx, fromBlock 0 returns the newest log twice; fromBlock 1 is always right.
# Sends one ping (potato -> anvil) to create a fresh log; the workers will deliver it as usual.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
set -a; . config/dev-keys.env; set +a
R=$(jq -r .chains.potato.rpc config/topology.json); D=deployments/$(jq -r .chains.potato.chainId config/topology.json).json
EP=$(jq -r .EndpointV2 "$D")
q() { cast rpc eth_getLogs "{\"fromBlock\":\"$1\",\"toBlock\":\"latest\",\"address\":\"$EP\"}" --rpc-url "$R" | jq length; }
cast send "$(jq -r .Ping "$D")" "ping(uint32,string)" "$(jq -r .chains.anvil.eid config/topology.json)" "getLogs probe" --rpc-url "$R" --private-key "$KEY_potato" >/dev/null
for i in 1 2 3 4; do
  a=$(q 0x0); b=$(q 0x1)
  [ "$a" = "$b" ] && s="same" || s="DIFFERENT <- bug: tip log duplicated"
  echo "t+$i: fromBlock 0 -> $a logs, fromBlock 1 -> $b logs ($s)"
  sleep 0.5
done
