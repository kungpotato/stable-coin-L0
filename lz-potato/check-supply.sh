#!/usr/bin/env bash
# Topic 13: supply invariant of a bridged asset (ADR 0002).
#   locked on the home chain (adapter) >= sum of OFT supply on the other chains
#   equal when nothing is in flight; locked < minted means tokens were minted without backing.
# usage: ./check-supply.sh [asset]        (default POTATO)
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
T=config/topology.json
ASSET="${1:-POTATO}"
get() { jq -r ".chains.$1.$2" "$T"; }
dep() { jq -r ".$2 // empty" "deployments/$(get "$1" chainId).json"; }
num() { awk '{print $1}'; }  # cast prints "123 [1.23e2]"
fmt() { cast from-wei "$1"; }
HOME_CHAIN=$(jq -r ".assets.$ASSET.home" "$T")
HOME_LEG=$(dep "$HOME_CHAIN" "$ASSET"); HOME_RPC=$(get "$HOME_CHAIN" rpc); HOME_EP=$(dep "$HOME_CHAIN" EndpointV2)
[ -n "$HOME_LEG" ] || { echo "❌ no $ASSET leg recorded on $HOME_CHAIN"; exit 1; }

case "$ASSET" in
  POTATO) locked=$(cast balance "$HOME_LEG" --rpc-url "$HOME_RPC") ;;  # native coin held by the adapter
  *) echo "❌ don't know how to read locked $ASSET yet"; exit 1 ;;
esac
echo "== $ASSET: home $HOME_CHAIN, adapter $HOME_LEG"
echo "locked on $HOME_CHAIN: $(fmt "$locked")"

minted=0; inflight=0
for c in $(jq -r '.chains | keys[]' "$T"); do
  [ "$c" = "$HOME_CHAIN" ] && continue
  leg=$(dep "$c" "$ASSET"); rpc=$(get "$c" rpc); ep=$(dep "$c" EndpointV2); eid=$(get "$c" eid); heid=$(get "$HOME_CHAIN" eid)
  [ -n "$leg" ] || { echo "❌ no $ASSET leg recorded on $c"; exit 1; }
  s=$(cast call "$leg" "totalSupply()(uint256)" --rpc-url "$rpc" | num)
  minted=$(echo "$minted + $s" | bc)
  echo "minted on $c:   $(fmt "$s")"
  H=$(cast abi-encode "f(address)" "$HOME_LEG"); L=$(cast abi-encode "f(address)" "$leg")
  out=$(cast call "$HOME_EP" "outboundNonce(address,uint32,bytes32)(uint64)" "$HOME_LEG" "$eid" "$L" --rpc-url "$HOME_RPC" | num)
  in=$(cast call "$ep" "inboundNonce(address,uint32,bytes32)(uint64)" "$leg" "$heid" "$H" --rpc-url "$rpc" | num)
  back_out=$(cast call "$ep" "outboundNonce(address,uint32,bytes32)(uint64)" "$leg" "$heid" "$H" --rpc-url "$rpc" | num)
  back_in=$(cast call "$HOME_EP" "inboundNonce(address,uint32,bytes32)(uint64)" "$HOME_LEG" "$eid" "$L" --rpc-url "$HOME_RPC" | num)
  echo "messages $HOME_CHAIN->$c: sent $out, delivered $in | $c->$HOME_CHAIN: sent $back_out, delivered $back_in"
  inflight=$((inflight + out - in + back_out - back_in))
done

diff=$(echo "$locked - $minted" | bc)
if [ "$(echo "$diff < 0" | bc)" = 1 ]; then
  echo "❌ minted exceeds locked by $(fmt "${diff#-}") $ASSET: unbacked supply"; exit 1
elif [ "$diff" = 0 ] && [ "$inflight" = 0 ]; then
  echo "✅ locked == minted, nothing in flight"
elif [ "$inflight" -gt 0 ]; then
  echo "⏳ locked - minted = $(fmt "$diff") with $inflight message(s) in flight (expected until delivered)"
else
  echo "⚠️ locked exceeds minted by $(fmt "$diff") with nothing in flight (extra backing, investigate)"
fi
