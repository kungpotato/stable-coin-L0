#!/usr/bin/env bash
# Topic 13: bridge POTATO between chains through the OFT legs (workers must be running).
# usage: ./bridge-potato.sh <from> <to> <amount in POTATO, e.g. 1.5> [recipient]
#   recipient defaults to the address of KEY_<to> (our account on the destination chain)
# From the home chain the amount is sent as msg.value, which must be exactly fee + amount
# rounded down to 6 decimals (NativeOFTAdapter, ADR 0002); the dust never leaves the wallet.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
set -a; . config/dev-keys.env; set +a
T=config/topology.json
FROM="$1"; TO="$2"; AMOUNT="$3"
get() { jq -r ".chains.$1.$2" "$T"; }
dep() { jq -r ".$2" "deployments/$(get "$1" chainId).json"; }
num() { awk '{print $1}'; }
HOME_CHAIN=$(jq -r .assets.POTATO.home "$T")
SRC_RPC=$(get "$FROM" rpc); DST_RPC=$(get "$TO" rpc); DST_EID=$(get "$TO" eid)
SRC_LEG=$(dep "$FROM" POTATO); DST_LEG=$(dep "$TO" POTATO)
KEY_VAR="KEY_$FROM"; DST_KEY_VAR="KEY_$TO"
SENDER=$(cast wallet address "${!KEY_VAR}")
RECIPIENT="${4:-$(cast wallet address "${!DST_KEY_VAR}")}"

balance() { # POTATO balance of $2 on chain $1: native on the home chain, OFT elsewhere
  if [ "$1" = "$HOME_CHAIN" ]; then cast balance "$2" --rpc-url "$(get "$1" rpc)"
  else cast call "$(dep "$1" POTATO)" "balanceOf(address)(uint256)" "$2" --rpc-url "$(get "$1" rpc)" | num; fi
}

AMOUNT_LD=$(cast to-wei "$AMOUNT")
SENT_LD=$(echo "$AMOUNT_LD - $AMOUNT_LD % 10^12" | bc)  # shared decimals 6 -> 10^12 wei steps
TO32=$(cast abi-encode "f(address)" "$RECIPIENT")
SEND_PARAM="($DST_EID,$TO32,$AMOUNT_LD,$SENT_LD,0x,0x,0x)"
FEE=$(cast call "$SRC_LEG" "quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)((uint256,uint256))" "$SEND_PARAM" false --rpc-url "$SRC_RPC" | tr -d '()' | cut -d, -f1 | num)
VALUE=$FEE; [ "$FROM" = "$HOME_CHAIN" ] && VALUE=$(echo "$FEE + $SENT_LD" | bc)

echo "== $AMOUNT POTATO $FROM -> $TO, recipient $RECIPIENT"
[ "$SENT_LD" != "$AMOUNT_LD" ] && echo "   dust kept by sender: $(echo "$AMOUNT_LD - $SENT_LD" | bc) wei"
echo "   amount sent $(cast from-wei "$SENT_LD"), fee $FEE wei, msg.value $VALUE wei"
DST_BEFORE=$(balance "$TO" "$RECIPIENT")
cast send "$SRC_LEG" "send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)" \
  "$SEND_PARAM" "($FEE,0)" "$SENDER" --value "$VALUE" --rpc-url "$SRC_RPC" --private-key "${!KEY_VAR}" >/dev/null
T0=$(date +%s)
echo "== sent on $FROM, waiting for delivery on $TO"
until [ "$(balance "$TO" "$RECIPIENT")" != "$DST_BEFORE" ]; do
  [ $(( $(date +%s) - T0 )) -ge 90 ] && { echo "❌ not delivered after 90s (workers running?)"; exit 1; }
  sleep 1
done
DST_AFTER=$(balance "$TO" "$RECIPIENT")
echo "✅ delivered in $(( $(date +%s) - T0 ))s: recipient on $TO $(cast from-wei "$DST_BEFORE") -> $(cast from-wei "$DST_AFTER") (+$(cast from-wei "$(echo "$DST_AFTER - $DST_BEFORE" | bc)"))"
