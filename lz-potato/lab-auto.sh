#!/usr/bin/env bash
# Topic 12: send a ping and let the workers deliver it (no manual relay). Needs `npm run dvn` and
# `npm run executor` running in workers/. Prints how long delivery took.
# usage: ./lab-auto.sh <from> <to> [message] [timeout_s]
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
set -a; . config/dev-keys.env; set +a
T=config/topology.json
FROM="$1"; TO="$2"; MSG="${3:-auto $1 -> $2 @ $(date +%s)}"; TIMEOUT="${4:-60}"
get() { jq -r ".chains.$1.$2" "$T"; }
SRC_RPC=$(get "$FROM" rpc); DST_RPC=$(get "$TO" rpc); DST_EID=$(get "$TO" eid)
SRC_PING=$(jq -r .Ping "deployments/$(get "$FROM" chainId).json"); DST_PING=$(jq -r .Ping "deployments/$(get "$TO" chainId).json")
KEY_VAR="KEY_$FROM"

BEFORE=$(cast call "$DST_PING" "received()(uint256)" --rpc-url "$DST_RPC")
T0=$(date +%s)
cast send "$SRC_PING" "ping(uint32,string)" "$DST_EID" "$MSG" --rpc-url "$SRC_RPC" --private-key "${!KEY_VAR}" >/dev/null
echo "== sent on $FROM: $MSG"
until [ "$(cast call "$DST_PING" "received()(uint256)" --rpc-url "$DST_RPC")" -gt "$BEFORE" ]; do
  [ $(( $(date +%s) - T0 )) -ge "$TIMEOUT" ] && { echo "❌ not delivered after ${TIMEOUT}s (are both workers running?)"; exit 1; }
  sleep 1
done
echo "✅ delivered to $TO in $(( $(date +%s) - T0 ))s: $(cast call "$DST_PING" "lastMessage()(string)" --rpc-url "$DST_RPC")"
