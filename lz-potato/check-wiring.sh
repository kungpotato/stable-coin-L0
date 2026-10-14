#!/usr/bin/env bash
# Topic 11: read the pathway config back from every chain with cast (independent of the deploy scripts' logs).
# usage: ./check-wiring.sh
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
T=config/topology.json
fail=0
ok()  { echo "✅ $*"; }
bad() { echo "❌ $*"; fail=1; }
lc()  { tr '[:upper:]' '[:lower:]'; }
ULN='getUlnConfig(address,uint32)((uint64,uint8,uint8,uint8,address[],address[]))'

for c in $(jq -r '.chains | keys[]' "$T"); do
  rpc=$(jq -r ".chains.$c.rpc" "$T"); id=$(jq -r ".chains.$c.chainId" "$T"); eid=$(jq -r ".chains.$c.eid" "$T")
  D="deployments/$id.json"
  [ -f "$D" ] || { bad "$c: no $D (run DeployProtocol)"; continue; }
  EP=$(jq -r .EndpointV2 "$D"); SL=$(jq -r .SendUln302 "$D"); RL=$(jq -r .ReceiveUln302 "$D")
  DVN=$(jq -r .LabDVN "$D" | lc); EX=$(jq -r .LabExecutor "$D" | lc)
  echo "== $c (eid $eid) endpoint $EP"
  # cast prints big numbers as "40338 [4.033e4]": keep the first field
  got=$(cast call "$EP" "eid()(uint32)" --rpc-url "$rpc" 2>/dev/null | awk '{print $1}')
  [ -n "$got" ] || { bad "$c: endpoint not reachable / no code"; continue; }
  [ "$got" = "$eid" ] && ok "endpoint eid $got" || bad "endpoint eid $got, topology says $eid"

  for r in $(jq -r '.chains | keys[]' "$T"); do
    [ "$r" = "$c" ] && continue
    reid=$(jq -r ".chains.$r.eid" "$T"); lconf=$(jq -r ".chains.$c.confirmations" "$T"); rconf=$(jq -r ".chains.$r.confirmations" "$T")
    echo "  -- path $c <-> $r (eid $reid)"
    [ "$(cast call "$EP" "defaultSendLibrary(uint32)(address)" "$reid" --rpc-url "$rpc" | lc)" = "$(echo "$SL" | lc)" ] \
      && ok "  default send library = SendUln302" || bad "  default send library is not SendUln302"
    [ "$(cast call "$EP" "defaultReceiveLibrary(uint32)(address)" "$reid" --rpc-url "$rpc" | lc)" = "$(echo "$RL" | lc)" ] \
      && ok "  default receive library = ReceiveUln302" || bad "  default receive library is not ReceiveUln302"

    for side in send receive; do
      lib=$SL; want=$lconf; [ $side = receive ] && { lib=$RL; want=$rconf; }
      cfg=$(cast call "$lib" "$ULN" 0x0000000000000000000000000000000000000000 "$reid" --rpc-url "$rpc" 2>/dev/null | lc) \
        || { bad "  $side ULN config missing"; continue; }
      conf=$(echo "$cfg" | sed -E 's/^\(([0-9]+),.*/\1/'); dvns=$(echo "$cfg" | grep -oE '0x[0-9a-f]{40}' | paste -sd, -)
      [ "$conf" = "$want" ] && [ "$dvns" = "$DVN" ] \
        && ok "  $side ULN: confirmations $conf, required DVN = local LabDVN" \
        || bad "  $side ULN: confirmations $conf (want $want), DVNs [$dvns] (want [$DVN])"
    done

    ex=$(cast call "$SL" "getExecutorConfig(address,uint32)((uint32,address))" 0x0000000000000000000000000000000000000000 "$reid" --rpc-url "$rpc" | lc)
    echo "$ex" | grep -q "$EX" && ok "  executor = local LabExecutor" || bad "  executor config $ex"
  done
done
[ $fail -eq 0 ] && echo "== wiring OK" || echo "== wiring has errors"
exit $fail
