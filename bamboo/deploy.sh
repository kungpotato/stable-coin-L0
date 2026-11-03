#!/usr/bin/env bash
# Deploy bamboo messaging layer (gateway) + the OFT token app to two EVM chains,
# wire attester set + peers. Writes deployments/local.json for the relay.
#
# Config via env (defaults = anvil<->anvil local test). Override for anvil<->potato.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.foundry/bin:$PATH"

# --- chain A --------------------------------------------------------------
A_NAME="${A_NAME:-anvil}"
A_RPC="${A_RPC:-http://localhost:28545}"
A_ID="${A_ID:-1}"
A_KEY="${A_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}" # anvil #0
# --- chain B --------------------------------------------------------------
B_NAME="${B_NAME:-potato}"
B_RPC="${B_RPC:-http://localhost:18545}"
B_ID="${B_ID:-2}"
B_KEY="${B_KEY:-$A_KEY}"
# --- attester set + threshold (anvil #1,#2,#3 by default) -----------------
ATTESTERS="${ATTESTERS:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8,0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,0x90F79bf6EB2c4f870365E785982E1f101E93b906}"
THRESHOLD="${THRESHOLD:-2}"
# demo seed on chain A
SEED_TO="${SEED_TO:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}" # anvil #0
SEED_AMT="${SEED_AMT:-1000000000000000000000}"                   # 1000e18
# damage-bounding defaults (bound a compromised attester set — Ronin/AFX lost all at once)
GUARDIAN="${GUARDIAN:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8}"      # anvil #1 as BOT guardian (emergency pause)
MAX_PER_TRANSFER="${MAX_PER_TRANSFER:-200000000000000000000}"          # 200e18 per transfer
DAILY_CAP="${DAILY_CAP:-1000000000000000000000}"                       # 1000e18 per day

deploy_chain() { # $1=rpc $2=logicalId $3=key  -> echoes "token gateway oft"
  local rpc="$1" id="$2" key="$3" token gateway oft
  token=$(forge create src/BambooToken.sol:BambooToken --rpc-url "$rpc" --private-key "$key" \
    --broadcast --json --constructor-args "Bamboo USD" "bUSD" | jq -r .deployedTo)
  gateway=$(forge create src/BambooGateway.sol:BambooGateway --rpc-url "$rpc" --private-key "$key" \
    --broadcast --json --constructor-args "$id" | jq -r .deployedTo)
  oft=$(forge create src/BambooOFT.sol:BambooOFT --rpc-url "$rpc" --private-key "$key" \
    --broadcast --json --constructor-args "$gateway" "$token" | jq -r .deployedTo)
  # issuer grants the OFT app a minter/burner role (NOT the gateway). Issuer keeps the token.
  cast send "$token" "setMinter(address,bool)" "$oft" true --rpc-url "$rpc" --private-key "$key" >/dev/null
  # M-2: whitelist the demo wallet (KYC'd) so it can send/receive
  cast send "$oft" "setWhitelist(address,bool)" "$SEED_TO" true --rpc-url "$rpc" --private-key "$key" >/dev/null
  # attester set + threshold on the gateway
  local IFS=,
  for a in $ATTESTERS; do
    cast send "$gateway" "setAttester(address,bool)" "$a" true --rpc-url "$rpc" --private-key "$key" >/dev/null
  done
  cast send "$gateway" "setThreshold(uint256)" "$THRESHOLD" --rpc-url "$rpc" --private-key "$key" >/dev/null
  # guardian (emergency pause) + damage caps
  cast send "$gateway" "setGuardian(address)" "$GUARDIAN" --rpc-url "$rpc" --private-key "$key" >/dev/null
  cast send "$oft" "setMaxPerTransfer(uint256)" "$MAX_PER_TRANSFER" --rpc-url "$rpc" --private-key "$key" >/dev/null
  cast send "$oft" "setDailyMintCap(uint256)" "$DAILY_CAP" --rpc-url "$rpc" --private-key "$key" >/dev/null
  echo "$token $gateway $oft"
}

echo ">> deploying to $A_NAME ($A_RPC, id=$A_ID)"
read -r A_TOKEN A_GATEWAY A_OFT < <(deploy_chain "$A_RPC" "$A_ID" "$A_KEY")
echo "   token=$A_TOKEN gateway=$A_GATEWAY oft=$A_OFT"

echo ">> deploying to $B_NAME ($B_RPC, id=$B_ID)"
read -r B_TOKEN B_GATEWAY B_OFT < <(deploy_chain "$B_RPC" "$B_ID" "$B_KEY")
echo "   token=$B_TOKEN gateway=$B_GATEWAY oft=$B_OFT"

# wire peers (each OFT trusts its sibling on the other chain)
echo ">> wiring peers"
cast send "$A_OFT" "setPeer(uint64,address)" "$B_ID" "$B_OFT" --rpc-url "$A_RPC" --private-key "$A_KEY" >/dev/null
cast send "$B_OFT" "setPeer(uint64,address)" "$A_ID" "$A_OFT" --rpc-url "$B_RPC" --private-key "$B_KEY" >/dev/null

# seed demo supply on chain A
echo ">> seeding $SEED_AMT bUSD to $SEED_TO on $A_NAME"
cast send "$A_TOKEN" "ownerMint(address,uint256)" "$SEED_TO" "$SEED_AMT" \
  --rpc-url "$A_RPC" --private-key "$A_KEY" >/dev/null

mkdir -p deployments
cat > deployments/local.json <<JSON
{
  "threshold": $THRESHOLD,
  "chains": {
    "$A_NAME": { "rpc": "$A_RPC", "logicalChainId": $A_ID, "token": "$A_TOKEN", "gateway": "$A_GATEWAY", "oft": "$A_OFT" },
    "$B_NAME": { "rpc": "$B_RPC", "logicalChainId": $B_ID, "token": "$B_TOKEN", "gateway": "$B_GATEWAY", "oft": "$B_OFT" }
  }
}
JSON
echo ">> wrote deployments/local.json"
cat deployments/local.json
