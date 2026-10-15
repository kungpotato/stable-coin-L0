#!/usr/bin/env bash
# Effective DVN config of every bridge leg (and Ping), read from the endpoints with cast: which DVNs each
# send/receive path requires. Fails if a path trusts a single DVN or a DVN marked compromised.
# usage: ./check-security.sh [compromised DVN keys, default LabDVN]
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
T=config/topology.json
COMPROMISED=" ${1:-LabDVN} "
ZERO=0x0000000000000000000000000000000000000000
fail=0
lc() { tr '[:upper:]' '[:lower:]'; }

for c in $(jq -r '.chains | keys[]' "$T"); do
  rpc=$(jq -r ".chains.$c.rpc" "$T"); D="deployments/$(jq -r ".chains.$c.chainId" "$T").json"
  EP=$(jq -r .EndpointV2 "$D"); SL=$(jq -r .SendUln302 "$D"); RL=$(jq -r .ReceiveUln302 "$D")
  name_of() { jq -r --arg a "$(echo "$1" | lc)" 'to_entries[] | select((.value|tostring|ascii_downcase) == $a) | .key' "$D" | grep -E '^LabDVN' | head -1; }
  for key in $(jq -r '.assets | keys[]' "$T") Ping; do
    oapp=$(jq -r --arg k "$key" '.[$k] // empty' "$D"); [ -n "$oapp" ] || continue
    for r in $(jq -r '.chains | keys[]' "$T"); do
      [ "$r" = "$c" ] && continue
      reid=$(jq -r ".chains.$r.eid" "$T")
      for side in send receive; do
        lib=$SL; [ $side = receive ] && lib=$RL
        cur=$(cast call "$EP" "$([ $side = send ] && echo 'getSendLibrary(address,uint32)(address)' || echo 'getReceiveLibrary(address,uint32)(address,bool)')" "$oapp" "$reid" --rpc-url "$rpc" | head -1 | lc)
        if [ "$cur" != "$(echo "$lib" | lc)" ]; then echo "⛔ $c $key $side $r: library $cur (blocked/contained)"; continue; fi
        cfg=$(cast call "$EP" "getConfig(address,address,uint32,uint32)(bytes)" "$oapp" "$lib" "$reid" 2 --rpc-url "$rpc")
        dvns=$(cast abi-decode "x()((uint64,uint8,uint8,uint8,address[],address[]))" "$cfg" | grep -oE '0x[0-9a-fA-F]{40}' | sed -n '1,$p')
        names=$(for a in $dvns; do n=$(name_of "$a"); echo "${n:-$a}"; done | paste -sd+ -)
        count=$(echo "$dvns" | grep -c . || true)
        bad=""
        [ "$count" -lt 2 ] && bad="single DVN"
        for n in ${names//+/ }; do [[ "$COMPROMISED" == *" $n "* ]] && bad="${bad:+$bad, }trusts compromised $n"; done
        if [ -n "$bad" ]; then echo "❌ $c $key $side $r: $names ($bad)"; [ "$key" = Ping ] || fail=1
        else echo "✅ $c $key $side $r: $names"; fi
      done
    done
  done
done
[ $fail -eq 0 ] && echo "== security OK (bridge assets)" || echo "== security has bridge assets at risk"
exit $fail
