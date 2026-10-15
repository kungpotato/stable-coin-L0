#!/usr/bin/env bash
# Topic 4: send one Ping across official LayerZero testnets and follow it on LayerZero Scan.
# usage: testnet/ping.sh <from: sepolia|arbitrum-sepolia> <to> [message]
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
C=testnet/config.json; FROM="$1"; TO="$2"; MSG="${3:-hello $1 -> $2 @ $(date +%s)}"
rpc() { local v; v=$(jq -r --arg c "$1" '.chains[$c].rpcEnv' "$C"); echo "${!v}"; }
cid() { jq -r --arg c "$1" '.chains[$c].chainId' "$C"; }
SRC_RPC=$(rpc "$FROM"); DST_RPC=$(rpc "$TO"); DST_EID=$(jq -r --arg c "$TO" '.chains[$c].eid' "$C")
SRC_PING=$(jq -r .Ping "lz-potato/deployments/$(cid "$FROM").json"); DST_PING=$(jq -r .Ping "lz-potato/deployments/$(cid "$TO").json")

FEE=$(cast call "$SRC_PING" "quote(uint32,string)((uint256,uint256))" "$DST_EID" "$MSG" --rpc-url "$SRC_RPC" | tr -d '()' | cut -d, -f1 | awk '{print $1}')
echo "== quote: native fee $(cast from-wei "$FEE") ETH (real: DVNs + executor + destination gas)"
BEFORE=$(cast call "$DST_PING" "received()(uint256)" --rpc-url "$DST_RPC")
TX=$(cast send "$SRC_PING" "ping(uint32,string)" "$DST_EID" "$MSG" --value "$FEE" --rpc-url "$SRC_RPC" --private-key "$TESTNET_PRIVATE_KEY" --json | jq -r .transactionHash)
echo "== sent on $FROM: $TX"
echo "   https://testnet.layerzeroscan.com/tx/$TX"
T0=$(date +%s); last=""
while :; do
  s=$(curl -s -m 20 "https://scan-testnet.layerzero-api.com/v1/messages/tx/$TX" | jq -r '.data[0].status.name // "NOT_INDEXED_YET"' 2>/dev/null || echo "?")
  [ "$s" != "$last" ] && { echo "   t+$(( $(date +%s) - T0 ))s scan status: $s"; last=$s; }
  now=$(cast call "$DST_PING" "received()(uint256)" --rpc-url "$DST_RPC")
  [ "$now" != "$BEFORE" ] && { echo "✅ delivered after $(( $(date +%s) - T0 ))s: $TO Ping.received $BEFORE -> $now, lastMessage: $(cast call "$DST_PING" "lastMessage()(string)" --rpc-url "$DST_RPC")"; break; }
  case "$s" in FAILED|BLOCKED|PAYLOAD_STORED) echo "❌ scan status $s"; break ;; esac
  [ $(( $(date +%s) - T0 )) -ge 1800 ] && { echo "❌ not delivered after 30 min"; exit 1; }
  sleep 15
done
