#!/usr/bin/env bash
# Topics 13-14: bridge an asset between chains through its OFT legs (workers must be running).
# usage: ./bridge.sh <POTATO|USDC|DEMOWEAK|DEMOSAFE> <from> <to> <amount, e.g. 1.5> [recipient]
#   recipient defaults to the address of KEY_<to> (our account on the destination chain)
# Amounts are rounded down to the 6 shared decimals; the dust never leaves the wallet.
#   POTATO from its home: sent as msg.value = fee + amount exactly (NativeOFTAdapter, ADR 0002)
#   USDC / demo assets from their home: approve the home token (IssuerUSDC / <ASSET>Token) to the adapter
#   anywhere else:        the OFT burns from the sender, msg.value = fee
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
set -a; . config/dev-keys.env; set +a
T=config/topology.json
ASSET="$1"; FROM="$2"; TO="$3"; AMOUNT="$4"
get() { jq -r ".chains.$1.$2" "$T"; }
dep() { jq -r ".$2" "deployments/$(get "$1" chainId).json"; }
num() { awk '{print $1}'; }
HOME_CHAIN=$(jq -r ".assets.$ASSET.home" "$T"); DEC=$(jq -r ".assets.$ASSET.decimals" "$T")
HOME_TOKEN_KEY=IssuerUSDC; [ "$ASSET" != USDC ] && HOME_TOKEN_KEY="${ASSET}Token"
DUST_STEP=$(echo "10^($DEC - $(jq -r ".assets.$ASSET.sharedDecimals" "$T"))" | bc)
SRC_RPC=$(get "$FROM" rpc); DST_RPC=$(get "$TO" rpc); DST_EID=$(get "$TO" eid)
SRC_LEG=$(dep "$FROM" "$ASSET"); DST_LEG=$(dep "$TO" "$ASSET")
KEY_VAR="KEY_$FROM"; DST_KEY_VAR="KEY_$TO"
SENDER=$(cast wallet address "${!KEY_VAR}")
RECIPIENT="${5:-$(cast wallet address "${!DST_KEY_VAR}")}"

balance() { # $ASSET balance of $2 on chain $1
  if [ "$1" = "$HOME_CHAIN" ] && [ "$ASSET" = POTATO ]; then cast balance "$2" --rpc-url "$(get "$1" rpc)"
  elif [ "$1" = "$HOME_CHAIN" ]; then cast call "$(dep "$1" "$HOME_TOKEN_KEY")" "balanceOf(address)(uint256)" "$2" --rpc-url "$(get "$1" rpc)" | num
  else cast call "$(dep "$1" "$ASSET")" "balanceOf(address)(uint256)" "$2" --rpc-url "$(get "$1" rpc)" | num; fi
}
fmt() { cast format-units "$1" "$DEC"; }

AMOUNT_LD=$(cast parse-units "$AMOUNT" "$DEC")
SENT_LD=$(echo "$AMOUNT_LD - $AMOUNT_LD % $DUST_STEP" | bc)
TO32=$(cast abi-encode "f(address)" "$RECIPIENT")
SEND_PARAM="($DST_EID,$TO32,$AMOUNT_LD,$SENT_LD,0x,0x,0x)"
FEE=$(cast call "$SRC_LEG" "quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)((uint256,uint256))" "$SEND_PARAM" false --rpc-url "$SRC_RPC" | tr -d '()' | cut -d, -f1 | num)
VALUE=$FEE; [ "$FROM" = "$HOME_CHAIN" ] && [ "$ASSET" = POTATO ] && VALUE=$(echo "$FEE + $SENT_LD" | bc)

echo "== $AMOUNT $ASSET $FROM -> $TO, recipient $RECIPIENT"
[ "$SENT_LD" != "$AMOUNT_LD" ] && echo "   dust kept by sender: $(echo "$AMOUNT_LD - $SENT_LD" | bc) wei"
echo "   amount sent $(fmt "$SENT_LD"), fee $FEE wei, msg.value $VALUE wei"
if [ "$FROM" = "$HOME_CHAIN" ] && [ "$ASSET" != POTATO ]; then # the adapter pulls the home token with transferFrom
  TOKEN=$(dep "$FROM" "$HOME_TOKEN_KEY")
  if [ "$(echo "$(cast call "$TOKEN" "allowance(address,address)(uint256)" "$SENDER" "$SRC_LEG" --rpc-url "$SRC_RPC" | num) < $SENT_LD" | bc)" = 1 ]; then
    cast send "$TOKEN" "approve(address,uint256)" "$SRC_LEG" "$SENT_LD" --rpc-url "$SRC_RPC" --private-key "${!KEY_VAR}" >/dev/null
    echo "   approved $(fmt "$SENT_LD") $ASSET for the adapter"
  fi
fi
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
echo "✅ delivered in $(( $(date +%s) - T0 ))s: recipient on $TO $(fmt "$DST_BEFORE") -> $(fmt "$DST_AFTER") (+$(fmt "$(echo "$DST_AFTER - $DST_BEFORE" | bc)"))"
