#!/usr/bin/env bash
# Topic 10: check config/topology.json against itself and the live chains.
# usage: ./check-topology.sh [config/topology.json]
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
T="${1:-config/topology.json}"
fail=0
ok()  { echo "✅ $*"; }
bad() { echo "❌ $*"; fail=1; }

echo "== chains"
for c in $(jq -r '.chains | keys[]' "$T"); do
  want=$(jq -r ".chains.$c.chainId" "$T"); rpc=$(jq -r ".chains.$c.rpc" "$T"); conf=$(jq -r ".chains.$c.confirmations" "$T")
  got=$(cast chain-id --rpc-url "$rpc" 2>/dev/null) || { bad "$c: RPC $rpc not reachable"; continue; }
  [ "$got" = "$want" ] && ok "$c: $rpc is chainId $got" || bad "$c: $rpc is chainId $got, expected $want (wrong chain behind this port?)"
  [ "$conf" -ge 1 ] && ok "$c: confirmations $conf" || bad "$c: confirmations must be >= 1"
done
dups=$(jq -r '[.chains[].eid] | group_by(.) | map(select(length > 1)[0]) | .[]' "$T")
[ -z "$dups" ] && ok "EIDs unique: $(jq -c '[.chains | to_entries[] | "\(.key)=\(.value.eid)"]' "$T")" || bad "duplicate EID: $dups"

echo "== assets"
for a in $(jq -r '.assets | keys[]' "$T"); do
  home=$(jq -r ".assets.$a.home" "$T")
  jq -e ".chains.$home" "$T" >/dev/null && ok "$a: home '$home' is a known chain" || bad "$a: home '$home' is not in chains"
  missing=$(jq -r "(.chains | keys) - (.assets.$a.legs | keys) | .[]" "$T")
  [ -z "$missing" ] && ok "$a: has a leg on every chain" || bad "$a: no leg on $missing"
  # exactly one lockbox per asset, and it must sit on the home chain; two lockboxes = two sources of supply
  adapters=$(jq -r ".assets.$a.legs | to_entries | map(select(.value.kind == \"adapter\")) | map(.key) | join(\",\")" "$T")
  [ "$adapters" = "$home" ] && ok "$a: single adapter (lockbox) on home '$home', OFT elsewhere" || bad "$a: adapters on [$adapters], expected exactly [$home]"
  d=$(jq -r ".assets.$a.decimals" "$T"); s=$(jq -r ".assets.$a.sharedDecimals" "$T")
  if [ "$s" -le "$d" ]; then
    [ "$s" -eq "$d" ] && ok "$a: decimals $d = shared $s, no dust" || ok "$a: decimals $d > shared $s, amounts below 10^$((d - s)) wei are dust"
  else bad "$a: sharedDecimals $s > decimals $d"; fi
done

echo "== paths"
for p in $(jq -r '.paths[] | join(">")' "$T"); do
  a=${p%>*}; b=${p#*>}
  jq -e ".chains.$a and .chains.$b" "$T" >/dev/null && ok "path $a -> $b" || bad "path $a -> $b uses an unknown chain"
done
n=$(jq '.chains | length' "$T"); np=$(jq '.paths | length' "$T")
[ "$np" -eq $((n * (n - 1))) ] && ok "all $np directed paths between $n chains" || bad "$np paths, expected $((n * (n - 1)))"

[ $fail -eq 0 ] && echo "== topology OK" || echo "== topology has errors"
exit $fail
