#!/usr/bin/env bash
# Topic 13: supply invariant of a bridged asset (ADR 0002).
#   locked on the home chain (adapter) >= sum of OFT supply on the other chains
#   equal when nothing is in flight; locked < minted means tokens were minted without backing.
# usage: ./check-supply.sh [asset]        (POTATO | USDC | DEMOWEAK | DEMOSAFE, default POTATO)
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
T=config/topology.json
ASSET="${1:-POTATO}"
get() { jq -r ".chains.$1.$2" "$T"; }
dep() { jq -r ".$2 // empty" "deployments/$(get "$1" chainId).json"; }
num() { awk '{print $1}'; }  # cast prints "123 [1.23e2]"
fmt() { if [ "${1#-}" != "$1" ]; then echo "-$(cast format-units "${1#-}" "$DEC")"; else cast format-units "$1" "$DEC"; fi; }  # cast rejects negatives
# executed <endpoint> <rpc> <receiver> <srcEid> <sender32> <sent>: how many of nonces 1..sent were executed.
# Not inboundNonce: that counts committed (verified) packets, which a paused receiver has not executed yet.
# Executed = payload hash cleared and nonce <= lazyInboundNonce (same rule as the executor worker).
executed() {
  local lazy n count=0
  lazy=$(cast call "$1" "lazyInboundNonce(address,uint32,bytes32)(uint64)" "$3" "$4" "$5" --rpc-url "$2" | num)
  for ((n = 1; n <= $6; n++)); do
    [ "$n" -le "$lazy" ] && [ "$(cast call "$1" "inboundPayloadHash(address,uint32,bytes32,uint64)(bytes32)" "$3" "$4" "$5" "$n" --rpc-url "$2")" = 0x0000000000000000000000000000000000000000000000000000000000000000 ] && count=$((count + 1))
  done
  echo $count
}
HOME_CHAIN=$(jq -r ".assets.$ASSET.home" "$T"); DEC=$(jq -r ".assets.$ASSET.decimals" "$T")
HOME_LEG=$(dep "$HOME_CHAIN" "$ASSET"); HOME_RPC=$(get "$HOME_CHAIN" rpc); HOME_EP=$(dep "$HOME_CHAIN" EndpointV2)
[ -n "$HOME_LEG" ] || { echo "❌ no $ASSET leg recorded on $HOME_CHAIN"; exit 1; }

case "$ASSET" in
  POTATO) locked=$(cast balance "$HOME_LEG" --rpc-url "$HOME_RPC") ;;  # native coin held by the adapter
  USDC) locked=$(cast call "$(dep "$HOME_CHAIN" IssuerUSDC)" "balanceOf(address)(uint256)" "$HOME_LEG" --rpc-url "$HOME_RPC" | num) ;;
  *) TOKEN=$(dep "$HOME_CHAIN" "${ASSET}Token")  # demo assets: DemoToken held by the adapter
     [ -n "$TOKEN" ] || { echo "❌ don't know how to read locked $ASSET"; exit 1; }
     locked=$(cast call "$TOKEN" "balanceOf(address)(uint256)" "$HOME_LEG" --rpc-url "$HOME_RPC" | num) ;;
esac
echo "== $ASSET: home $HOME_CHAIN, adapter $HOME_LEG"
echo "locked on $HOME_CHAIN: $(fmt "$locked")"

minted=0; inflight=0; forged=0
for c in $(jq -r '.chains | keys[]' "$T"); do
  [ "$c" = "$HOME_CHAIN" ] && continue
  leg=$(dep "$c" "$ASSET"); rpc=$(get "$c" rpc); ep=$(dep "$c" EndpointV2); eid=$(get "$c" eid); heid=$(get "$HOME_CHAIN" eid)
  [ -n "$leg" ] || { echo "❌ no $ASSET leg recorded on $c"; exit 1; }
  s=$(cast call "$leg" "totalSupply()(uint256)" --rpc-url "$rpc" | num)
  minted=$(echo "$minted + $s" | bc)
  echo "minted on $c:   $(fmt "$s")"
  H=$(cast abi-encode "f(address)" "$HOME_LEG"); L=$(cast abi-encode "f(address)" "$leg")
  out=$(cast call "$HOME_EP" "outboundNonce(address,uint32,bytes32)(uint64)" "$HOME_LEG" "$eid" "$L" --rpc-url "$HOME_RPC" | num)
  in=$(executed "$ep" "$rpc" "$leg" "$heid" "$H" "$out")
  back_out=$(cast call "$ep" "outboundNonce(address,uint32,bytes32)(uint64)" "$leg" "$heid" "$H" --rpc-url "$rpc" | num)
  back_in=$(executed "$HOME_EP" "$HOME_RPC" "$HOME_LEG" "$eid" "$L" "$back_out")
  echo "messages $HOME_CHAIN->$c: sent $out, delivered $in | $c->$HOME_CHAIN: sent $back_out, delivered $back_in"
  inflight=$((inflight + out - in + back_out - back_in))
  # a destination that accepted more nonces than the source ever sent was fed forged messages
  lazy=$(cast call "$ep" "lazyInboundNonce(address,uint32,bytes32)(uint64)" "$leg" "$heid" "$H" --rpc-url "$rpc" | num)
  back_lazy=$(cast call "$HOME_EP" "lazyInboundNonce(address,uint32,bytes32)(uint64)" "$HOME_LEG" "$eid" "$L" --rpc-url "$HOME_RPC" | num)
  [ "$lazy" -gt "$out" ] && { echo "❌ $c accepted $((lazy - out)) message(s) from $HOME_CHAIN that were never sent: FORGED"; forged=1; }
  [ "$back_lazy" -gt "$back_out" ] && { echo "❌ $HOME_CHAIN accepted $((back_lazy - back_out)) message(s) from $c that were never sent: FORGED"; forged=1; }
done

diff=$(echo "$locked - $minted" | bc)
if [ "$forged" = 1 ]; then
  echo "❌ forged messages on this asset's paths (locked - minted = $(fmt "$diff")): pause the legs and investigate the DVNs"; exit 1
elif [ "$(echo "$diff < 0" | bc)" = 1 ]; then
  echo "❌ minted exceeds locked by $(fmt "${diff#-}") $ASSET: unbacked supply"; exit 1
elif [ "$diff" = 0 ] && [ "$inflight" = 0 ]; then
  echo "✅ locked == minted, nothing in flight"
elif [ "$inflight" -gt 0 ]; then
  echo "⏳ locked - minted = $(fmt "$diff") with $inflight message(s) in flight (expected until delivered)"
else
  echo "⚠️ locked exceeds minted by $(fmt "$diff") with nothing in flight (extra backing, investigate)"
fi
