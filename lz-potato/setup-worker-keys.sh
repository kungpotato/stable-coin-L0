#!/usr/bin/env bash
# Topic 12: hand LabDVN ownership to the DVN key and fund both worker keys on every chain.
# Re-runnable: only acts where the owner/balance is not already right.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
set -a; . config/dev-keys.env; set +a
T=config/topology.json
DVN_ADDR=$(cast wallet address "$DVN_KEY"); EX_ADDR=$(cast wallet address "$EXECUTOR_KEY")
MIN_WEI=$(cast to-wei 5); TOPUP=10ether
lc() { tr '[:upper:]' '[:lower:]'; }

for c in $(jq -r '.chains | keys[]' "$T"); do
  rpc=$(jq -r ".chains.$c.rpc" "$T"); D="deployments/$(jq -r ".chains.$c.chainId" "$T").json"
  key_var="KEY_$c"; DVN=$(jq -r .LabDVN "$D")
  owner=$(cast call "$DVN" "owner()(address)" --rpc-url "$rpc")
  if [ "$(echo "$owner" | lc)" = "$(echo "$DVN_ADDR" | lc)" ]; then
    echo "$c: LabDVN owner already DVN key"
  else
    cast send "$DVN" "transferOwnership(address)" "$DVN_ADDR" --rpc-url "$rpc" --private-key "${!key_var}" >/dev/null
    echo "$c: LabDVN owner $owner -> $DVN_ADDR"
  fi
  for who in "dvn:$DVN_ADDR" "executor:$EX_ADDR"; do
    name=${who%%:*}; addr=${who#*:}
    bal=$(cast balance "$addr" --rpc-url "$rpc")
    if [ "$(echo "$bal >= $MIN_WEI" | bc)" = 1 ]; then
      echo "$c: $name $addr has $(cast from-wei "$bal")"
    else
      cast send "$addr" --value "$TOPUP" --rpc-url "$rpc" --private-key "${!key_var}" >/dev/null
      echo "$c: $name $addr funded $TOPUP"
    fi
  done
done
