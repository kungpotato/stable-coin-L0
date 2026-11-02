#!/usr/bin/env bash
# Send bUSD from chain A -> chain B through the bamboo protocol and verify the mint.
# Usage: ./demo.sh [amount_wei] [recipient]
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.foundry/bin:$PATH"

AMT="${1:-100000000000000000000}"                               # 100e18
TO="${2:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"           # anvil #0
SENDER_KEY="${SENDER_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

J=deployments/local.json
A_NAME=$(jq -r '.chains | keys[0]' $J); B_NAME=$(jq -r '.chains | keys[1]' $J)
A_RPC=$(jq -r ".chains.$A_NAME.rpc" $J);     B_RPC=$(jq -r ".chains.$B_NAME.rpc" $J)
A_TOKEN=$(jq -r ".chains.$A_NAME.token" $J); B_TOKEN=$(jq -r ".chains.$B_NAME.token" $J)
A_OFT=$(jq -r ".chains.$A_NAME.oft" $J);     B_ID=$(jq -r ".chains.$B_NAME.logicalChainId" $J)

bal() { cast call "$1" "balanceOf(address)(uint256)" "$TO" --rpc-url "$2" | awk '{print $1}'; }
sup() { cast call "$1" "totalSupply()(uint256)" --rpc-url "$2" | awk '{print $1}'; }

echo "=== before ==="
echo "$A_NAME: bal=$(bal $A_TOKEN $A_RPC) supply=$(sup $A_TOKEN $A_RPC)"
echo "$B_NAME: bal=$(bal $B_TOKEN $B_RPC) supply=$(sup $B_TOKEN $B_RPC)"

echo "=== approve OFT + send $AMT from $A_NAME -> $B_NAME (dstId=$B_ID) to $TO ==="
# user approves the OFT app to burn (allowance-based burnFrom)
cast send "$A_TOKEN" "approve(address,uint256)" "$A_OFT" "$AMT" \
  --rpc-url "$A_RPC" --private-key "$SENDER_KEY" >/dev/null
# call the app, which burns + sends a generic message through the gateway
cast send "$A_OFT" "send(uint64,address,uint256)" "$B_ID" "$TO" "$AMT" \
  --rpc-url "$A_RPC" --private-key "$SENDER_KEY" >/dev/null
echo "burned on $A_NAME; waiting for relay to mint on $B_NAME..."

for i in $(seq 1 15); do
  sleep 2
  b=$(bal $B_TOKEN $B_RPC)
  echo "  [$i] $B_NAME bal=$b"
  [ "$b" != "0" ] && break
done

echo "=== after ==="
echo "$A_NAME: bal=$(bal $A_TOKEN $A_RPC) supply=$(sup $A_TOKEN $A_RPC)"
echo "$B_NAME: bal=$(bal $B_TOKEN $B_RPC) supply=$(sup $B_TOKEN $B_RPC)"
echo "(total supply across chains should be unchanged = burn-and-mint, no wrapping)"
