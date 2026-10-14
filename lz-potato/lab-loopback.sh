#!/usr/bin/env bash
# Topic 9 readiness check: deploy self-hosted LayerZero V2 on one chain and push one message
# A -> B through the full path (send -> DVN verify -> commit -> lzReceive).
# usage: ./lab-loopback.sh <rpc-url> <private-key> [eid]
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
RPC="$1"; export PRIVATE_KEY="$2"; export LOCAL_EID="${3:-40707}"
cd "$(dirname "$0")"

CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
START=$(cast block-number --rpc-url "$RPC")
echo "== chain $CHAIN_ID, eid $LOCAL_EID, start block $START"

forge script script/DeployLab.s.sol --rpc-url "$RPC" --broadcast --slow -q
DEP="deployments/$CHAIN_ID.json"
EP=$(jq -r .EndpointV2 "$DEP"); A=$(jq -r .PingA "$DEP"); B=$(jq -r .PingB "$DEP")
echo "== deployed endpoint $EP"

MSG="hello from eid $LOCAL_EID @ $(date +%s)"
cast send "$A" "ping(uint32,string)" "$LOCAL_EID" "$MSG" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null
echo "== ping sent: $MSG"

# what a DVN does: find PacketSent. Start from the deploy block, never 0 (cosmos/evm getLogs bug, known-issues.md)
DATA=$(cast logs --from-block "$START" --address "$EP" "PacketSent(bytes,bytes,address)" --rpc-url "$RPC" --json | jq -r '.[-1].data')
export PAYLOAD=$(cast abi-decode --input "x(bytes,bytes,address)" "$DATA" | head -1)
echo "== PacketSent payload: ${PAYLOAD:0:42}..."

forge script script/Relay.s.sol --rpc-url "$RPC" --broadcast --slow -q

echo "== B.lastMessage: $(cast call "$B" "lastMessage()(string)" --rpc-url "$RPC")"
echo "== B.received:    $(cast call "$B" "received()(uint256)" --rpc-url "$RPC")"
