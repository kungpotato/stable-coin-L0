#!/usr/bin/env bash
# Topic 7: CrossChainReader on Arbitrum Sepolia reads Ping.received() on Sepolia through lzRead, and the answer
# is compared with a direct RPC call. usage: testnet/read.sh
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
READER=$(jq -r .Reader lz-potato/deployments/421614.json); TARGET=$(jq -r .Ping lz-potato/deployments/11155111.json)
EID=$(jq -r '.chains.sepolia.eid' testnet/config.json); CD=$(cast calldata 'received()')
DIRECT=$(cast call "$TARGET" 'received()(uint256)' --rpc-url "$SEPOLIA_RPC_URL")
FEE=$(cast call "$READER" 'quote(uint32,address,bytes)((uint256,uint256))' "$EID" "$TARGET" "$CD" --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL" | tr -d '()' | cut -d, -f1 | awk '{print $1}')
BEFORE=$(cast call "$READER" 'reads()(uint256)' --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL")
echo "== Sepolia Ping.received() read directly over RPC: $DIRECT"
echo "== lzRead fee: $(cast from-wei "$FEE") ETH"
TX=$(cast send "$READER" 'read(uint32,address,bytes)' "$EID" "$TARGET" "$CD" --value "$FEE" --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL" --private-key "$TESTNET_PRIVATE_KEY" --json | jq -r .transactionHash)
echo "== read requested on arbitrum-sepolia: $TX"
echo "   https://testnet.layerzeroscan.com/tx/$TX"
T0=$(date +%s); last=""
while :; do
  s=$(curl -s -m 20 "https://scan-testnet.layerzero-api.com/v1/messages/tx/$TX" | jq -r '.data[0].status.name // "NOT_INDEXED_YET"' 2>/dev/null || echo "?")
  [ "$s" != "$last" ] && { echo "   t+$(( $(date +%s) - T0 ))s scan status: $s"; last=$s; }
  if [ "$(cast call "$READER" 'reads()(uint256)' --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL")" != "$BEFORE" ]; then
    V=$(cast call "$READER" 'lastValue()(uint256)' --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL")
    [ "$V" = "$DIRECT" ] && echo "✅ answered after $(( $(date +%s) - T0 ))s: lastValue $V == direct RPC $DIRECT" \
                         || echo "⚠️ answered $V but direct RPC says $DIRECT (Ping changed in between?)"
    break
  fi
  case "$s" in FAILED|BLOCKED) echo "❌ scan status $s"; exit 1 ;; esac
  [ $(( $(date +%s) - T0 )) -ge 1800 ] && { echo "❌ no answer after 30 min"; exit 1; }
  sleep 15
done
