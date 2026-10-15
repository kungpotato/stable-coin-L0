#!/usr/bin/env bash
# Topic 7 (lzCompose): one user action = bridge USDC from anvil AND deposit it into the potato vault.
# The OFT credits USDC.lz to UsdcDepositComposer (lzReceive), then the executor's separate lzCompose call
# deposits it for the beneficiary. Workers (DVNs + executor) must be running.
# usage: ./bridge-and-deposit.sh <amount USDC> [beneficiary on potato]   (default: KEY_potato's address)
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")"
set -a; . config/dev-keys.env; set +a
AMOUNT="$1"; BENEFICIARY="${2:-$(cast wallet address "$KEY_potato")}"
A=$(jq -r .chains.anvil.rpc config/topology.json); P=$(jq -r .chains.potato.rpc config/topology.json)
AD=$(jq -r .USDC deployments/31338.json); TOKEN=$(jq -r .IssuerUSDC deployments/31338.json)
COMPOSER=$(jq -r .UsdcComposer deployments/707070.json); VAULT=$(jq -r .UsdcVault deployments/707070.json)
SENDER=$(cast wallet address "$KEY_anvil")
AMOUNT_LD=$(cast parse-units "$AMOUNT" 6)
shares() { cast call "$VAULT" "balanceOf(address)(uint256)" "$BENEFICIARY" --rpc-url "$P" | awk '{print $1}'; }

# send to the composer, with the beneficiary as the compose payload
PARAM="($(jq -r .chains.potato.eid config/topology.json),$(cast abi-encode 'f(address)' "$COMPOSER"),$AMOUNT_LD,$AMOUNT_LD,0x,$(cast abi-encode 'f(address)' "$BENEFICIARY"),0x)"
SIG="(uint32,bytes32,uint256,uint256,bytes,bytes,bytes)"
FEE=$(cast call "$AD" "quoteSend($SIG,bool)((uint256,uint256))" "$PARAM" false --rpc-url "$A" | tr -d '()' | cut -d, -f1 | awk '{print $1}')
cast send "$TOKEN" "approve(address,uint256)" "$AD" "$AMOUNT_LD" --rpc-url "$A" --private-key "$KEY_anvil" >/dev/null
BEFORE=$(shares)
cast send "$AD" "send($SIG,(uint256,uint256),address)" "$PARAM" "($FEE,0)" "$SENDER" --value "$FEE" --rpc-url "$A" --private-key "$KEY_anvil" >/dev/null
T0=$(date +%s)
echo "== sent $AMOUNT USDC anvil -> potato composer, deposit for $BENEFICIARY"
until [ "$(shares)" != "$BEFORE" ]; do
  [ $(( $(date +%s) - T0 )) -ge 90 ] && { echo "❌ no vault shares after 90s (check executor log for the compose step)"; exit 1; }
  sleep 1
done
echo "✅ deposited in $(( $(date +%s) - T0 ))s: vault shares $(cast format-units "$BEFORE" 6) -> $(cast format-units "$(shares)" 6) pvUSDC"
