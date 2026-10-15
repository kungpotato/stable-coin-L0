#!/usr/bin/env bash
# Topic 8: hand an OApp to the chain's Safe: endpoint delegate first (needs the current owner), then ownership.
# usage: testnet/handover.sh [deployments key, default Ping]      Re-runnable.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
KEY="${1:-Ping}"; EP=0x6EDCE65403992e310A62460808c4b910D972f10f
lc() { tr '[:upper:]' '[:lower:]'; }
for pair in "Sepolia:11155111:SEPOLIA_RPC_URL:SEPOLIA_SAFE_ADDRESS" "Arbitrum Sepolia:421614:ARBITRUM_SEPOLIA_RPC_URL:ARBITRUM_SEPOLIA_SAFE_ADDRESS"; do
  IFS=: read -r name id rpcv safev <<<"$pair"; rpc="${!rpcv}"; safe="${!safev}"
  oapp=$(jq -r --arg k "$KEY" '.[$k]' "lz-potato/deployments/$id.json")
  if [ "$(cast call "$EP" 'delegates(address)(address)' "$oapp" --rpc-url "$rpc" | lc)" != "$(echo "$safe" | lc)" ]; then
    cast send "$oapp" 'setDelegate(address)' "$safe" --rpc-url "$rpc" --private-key "$TESTNET_PRIVATE_KEY" >/dev/null
    echo "$name: endpoint delegate -> Safe"
  fi
  if [ "$(cast call "$oapp" 'owner()(address)' --rpc-url "$rpc" | lc)" != "$(echo "$safe" | lc)" ]; then
    cast send "$oapp" 'transferOwnership(address)' "$safe" --rpc-url "$rpc" --private-key "$TESTNET_PRIVATE_KEY" >/dev/null
    echo "$name: owner -> Safe"
  fi
  echo "== $name $KEY $oapp: owner $(cast call "$oapp" 'owner()(address)' --rpc-url "$rpc"), delegate $(cast call "$EP" 'delegates(address)(address)' "$oapp" --rpc-url "$rpc") (Safe $safe)"
done
