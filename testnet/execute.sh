#!/usr/bin/env bash
# Topic 4/8 ops: manually deliver a message the executor could not (e.g. too little lzReceive gas in the
# sender's options). Rebuilds the packet from the source tx's PacketSent, checks it is committed on the
# destination, estimates the gas the receiver really needs, and calls EndpointV2.lzReceive (permissionless).
# usage: testnet/execute.sh <src chain: sepolia|arbitrum-sepolia> <src tx hash>
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
C=testnet/config.json; SRC="$1"; TX="$2"
rpc() { local v; v=$(jq -r --arg c "$1" '.chains[$c].rpcEnv' "$C"); echo "${!v}"; }
SRC_RPC=$(rpc "$SRC"); SRC_EID=$(jq -r --arg c "$SRC" '.chains[$c].eid' "$C")
TOPIC=$(cast keccak 'PacketSent(bytes,bytes,address)')
DATA=$(cast receipt "$TX" --rpc-url "$SRC_RPC" --json | jq -r --arg t "$TOPIC" '.logs[] | select(.topics[0]==$t) | .data')
P=$(cast abi-decode --input "x(bytes,bytes,address)" "$DATA" | sed -n 1p)
# PacketV1 hex offsets: version 2..4, nonce 4..20, srcEid 20..28, sender 28..92, dstEid 92..100, receiver 100..164
NONCE=$((16#${P:4:16})); SENDER=0x${P:28:64}; DST_EID=$((16#${P:92:8})); RECV=0x${P:124:40}; GUID=0x${P:164:64}; MSG=0x${P:228}
DST=$(jq -r --argjson e "$DST_EID" '.chains | to_entries[] | select(.value.eid==$e) | .key' "$C"); DST_RPC=$(rpc "$DST")
EP=$(jq -r --arg c "$DST" '.chains[$c].endpointV2' "$C")
echo "== $SRC -> $DST nonce $NONCE, receiver $RECV"
HASH=$(cast call "$EP" 'inboundPayloadHash(address,uint32,bytes32,uint64)(bytes32)' "$RECV" "$SRC_EID" "$SENDER" "$NONCE" --rpc-url "$DST_RPC")
[ "$HASH" = 0x0000000000000000000000000000000000000000000000000000000000000000 ] && { echo "❌ not committed on $DST (not verified yet, or already delivered)"; exit 1; }
CD=$(cast calldata 'lzReceive((uint32,bytes32,uint64),address,bytes32,bytes,bytes)' "($SRC_EID,$SENDER,$NONCE)" "$RECV" "$GUID" "$MSG" 0x)
R=$(curl -s -m 30 -X POST -H 'content-type: application/json' --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_estimateGas\",\"params\":[{\"from\":\"$TESTNET_ADDRESS\",\"to\":\"$EP\",\"data\":\"$CD\"},\"latest\"]}" "$DST_RPC")
EST=$(echo "$R" | jq -r '.result // empty'); [ -n "$EST" ] || { echo "❌ lzReceive reverts even with unlimited gas: $(echo "$R" | jq -c .error)"; exit 1; }
EST=$(cast to-dec "$EST"); LIMIT=$((EST * 13 / 10))
echo "== lzReceive needs ~$EST gas on $DST, sending with $LIMIT"
cast send "$EP" "$CD" --gas-limit "$LIMIT" --rpc-url "$DST_RPC" --private-key "$TESTNET_PRIVATE_KEY" --json \
  | jq -r '"✅ delivered: tx " + .transactionHash + ", gas used " + (.gasUsed | tostring)'
