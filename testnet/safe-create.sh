#!/usr/bin/env bash
# Topic 8: create a 2-of-3 Safe (v1.4.1) on each testnet: TESTNET_ADDRESS + SAFE_OWNER_B + SAFE_OWNER_C.
# Writes SEPOLIA_SAFE_ADDRESS / ARBITRUM_SEPOLIA_SAFE_ADDRESS into .env. Re-runnable (skips an existing Safe).
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
FACTORY=0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67
HANDLER=0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99
ZERO=0x0000000000000000000000000000000000000000
OWNERS="[$TESTNET_ADDRESS,$SAFE_OWNER_B_ADDRESS,$SAFE_OWNER_C_ADDRESS]"

create() { # name, rpc, singleton (Safe on L1, SafeL2 on L2s), .env variable
  local name=$1 rpc=$2 singleton=$3 var=$4 existing="${!4:-}"
  if [ -n "$existing" ] && [ "$(cast code "$existing" --rpc-url "$rpc")" != 0x ]; then
    echo "$name: Safe $existing already exists"; return
  fi
  local init tx proxy
  init=$(cast calldata 'setup(address[],uint256,address,bytes,address,address,uint256,address)' "$OWNERS" 2 $ZERO 0x $HANDLER $ZERO 0 $ZERO)
  tx=$(cast send $FACTORY 'createProxyWithNonce(address,bytes,uint256)' "$singleton" "$init" "$(date +%s)" \
       --rpc-url "$rpc" --private-key "$TESTNET_PRIVATE_KEY" --json)
  # ProxyCreation(address indexed proxy, address singleton): the proxy is topic 1
  proxy=$(echo "$tx" | jq -r --arg t "$(cast keccak 'ProxyCreation(address,address)')" '.logs[] | select(.topics[0]==$t) | .topics[1]' | head -1)
  proxy=$(cast parse-bytes32-address "$proxy")
  sed -i '' "s|^$var=.*|$var=$proxy|" .env
  echo "$name: created Safe $proxy"
}
create Sepolia "$SEPOLIA_RPC_URL" 0x41675C099F32341bf84BFc5382aF534df5C7461a SEPOLIA_SAFE_ADDRESS
create "Arbitrum Sepolia" "$ARBITRUM_SEPOLIA_RPC_URL" 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762 ARBITRUM_SEPOLIA_SAFE_ADDRESS

set -a; . ./.env; set +a
for pair in "Sepolia:$SEPOLIA_RPC_URL:$SEPOLIA_SAFE_ADDRESS" "Arbitrum Sepolia:$ARBITRUM_SEPOLIA_RPC_URL:$ARBITRUM_SEPOLIA_SAFE_ADDRESS"; do
  IFS=: read -r n r1 r2 safe <<<"$pair"; rpc="$r1:$r2"
  echo "== $n Safe $safe: threshold $(cast call "$safe" 'getThreshold()(uint256)' --rpc-url "$rpc"), owners $(cast call "$safe" 'getOwners()(address[])' --rpc-url "$rpc")"
done
