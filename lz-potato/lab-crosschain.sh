#!/usr/bin/env bash
# Topic 11: send one ping across chains and relay it by hand (DVN + executor work; topic 12 automates it).
# usage: ./lab-crosschain.sh <from> <to> [message]      e.g. ./lab-crosschain.sh potato anvil
# Chains/RPCs/EIDs come from config/topology.json, keys from config/dev-keys.env.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
set -a; . config/dev-keys.env; set +a
T=config/topology.json
FROM="$1"; TO="$2"; MSG="${3:-hello $1 -> $2 @ $(date +%s)}"
get() { jq -r ".chains.$1.$2" "$T"; }
SRC_RPC=$(get "$FROM" rpc); DST_RPC=$(get "$TO" rpc); DST_EID=$(get "$TO" eid); CONF=$(get "$FROM" confirmations)
SRC_D="deployments/$(get "$FROM" chainId).json"; DST_D="deployments/$(get "$TO" chainId).json"
SRC_KEY_VAR="KEY_$FROM"; DST_KEY_VAR="KEY_$TO"

# 1. Ping deployed and peered on every chain (second pass fills peers that were pending in the first)
for pass in 1 2; do
  for c in $(jq -r '.chains | keys[]' "$T"); do
    forge script script/DeployPing.s.sol --rpc-url "$(get "$c" rpc)" --broadcast --slow -q
  done
done
SRC_PING=$(jq -r .Ping "$SRC_D"); DST_PING=$(jq -r .Ping "$DST_D"); SRC_EP=$(jq -r .EndpointV2 "$SRC_D")
echo "== $FROM Ping $SRC_PING -> $TO Ping $DST_PING (eid $DST_EID)"

# 2. send on the source chain
BEFORE=$(cast call "$DST_PING" "received()(uint256)" --rpc-url "$DST_RPC")
START=$(cast block-number --rpc-url "$SRC_RPC")
TX_BLOCK=$(cast send "$SRC_PING" "ping(uint32,string)" "$DST_EID" "$MSG" --rpc-url "$SRC_RPC" --private-key "${!SRC_KEY_VAR}" --json | jq -r .blockNumber | cast to-dec)
echo "== sent on $FROM in block $TX_BLOCK: $MSG"

# 3. DVN: wait for the source chain's confirmations, then read PacketSent (from START, never block 0)
until [ "$(cast block-number --rpc-url "$SRC_RPC")" -ge $((TX_BLOCK + CONF)) ]; do sleep 1; done
DATA=$(cast logs --from-block "$START" --address "$SRC_EP" "PacketSent(bytes,bytes,address)" --rpc-url "$SRC_RPC" --json | jq -r '.[-1].data')
export PAYLOAD=$(cast abi-decode --input "x(bytes,bytes,address)" "$DATA" | sed -n 1p)
echo "== PacketSent on $FROM after $CONF confirmation(s): ${PAYLOAD:0:42}..."

# 4. DVN verify + commit + executor lzReceive, all on the destination chain with its own key
PRIVATE_KEY="${!DST_KEY_VAR}" CONFIRMATIONS="$CONF" forge script script/Relay.s.sol --rpc-url "$DST_RPC" --broadcast --slow -q

echo "== $TO Ping.received:    $BEFORE -> $(cast call "$DST_PING" "received()(uint256)" --rpc-url "$DST_RPC")"
echo "== $TO Ping.lastSrcEid:  $(cast call "$DST_PING" "lastSrcEid()(uint32)" --rpc-url "$DST_RPC" | awk '{print $1}')"
echo "== $TO Ping.lastMessage: $(cast call "$DST_PING" "lastMessage()(string)" --rpc-url "$DST_RPC")"
