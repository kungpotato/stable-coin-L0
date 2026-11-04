#!/usr/bin/env bash
# Retail cross-chain payment demo: instant local payout (fast path) + batched
# cross-chain settlement (bamboo). Requires bamboo deployed (deployments/local.json)
# and the relay mesh running.
#
#   Flow: users on A pay -> PSP instantly pays merchants on B from FastPayPool
#         -> bamboo sendBatch settles the netted total back into the pool.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.foundry/bin:$PATH"

J=deployments/local.json
A_NAME=$(jq -r '.chains|keys[0]' $J); B_NAME=$(jq -r '.chains|keys[1]' $J)
A_RPC=$(jq -r ".chains.$A_NAME.rpc" $J);   B_RPC=$(jq -r ".chains.$B_NAME.rpc" $J)
A_TOKEN=$(jq -r ".chains.$A_NAME.token" $J); B_TOKEN=$(jq -r ".chains.$B_NAME.token" $J)
A_OFT=$(jq -r ".chains.$A_NAME.oft" $J);     B_ID=$(jq -r ".chains.$B_NAME.logicalChainId" $J)

OWNER=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # anvil#0 (token/OFT owner, A user)
OPKEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a   # anvil#2 (PSP/operator)
OPADDR=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
USER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266                           # A user (seeded)
M1=0xAAaa000000000000000000000000000000000001
M2=0xAaaA000000000000000000000000000000000002
M3=0xaAAa000000000000000000000000000000000003
AMT=10000000000000000000   # 10 per fruit payment
TOTAL=30000000000000000000 # net settlement for the epoch

bal(){ cast call $1 "balanceOf(address)(uint256)" $2 --rpc-url $3|awk '{print $1}'; }

echo ">> deploy FastPayPool on $B_NAME (token=$B_TOKEN)"
POOL=$(forge create src/FastPayPool.sol:FastPayPool --rpc-url $B_RPC --private-key $OWNER \
  --broadcast --json --constructor-args $B_TOKEN | jq -r .deployedTo)
cast send $POOL "setOperator(address)" $OPADDR --rpc-url $B_RPC --private-key $OWNER >/dev/null
cast send $POOL "setCaps(uint256,uint256)" $AMT 1000000000000000000000 --rpc-url $B_RPC --private-key $OWNER >/dev/null
echo "   pool=$POOL operator=$OPADDR"

echo ">> prefund pool with 100 on $B_NAME + whitelist pool (settlement recipient)"
cast send $B_TOKEN "ownerMint(address,uint256)" $POOL 100000000000000000000 --rpc-url $B_RPC --private-key $OWNER >/dev/null
cast send $(jq -r ".chains.$B_NAME.oft" $J) "setWhitelist(address,bool)" $POOL true --rpc-url $B_RPC --private-key $OWNER >/dev/null

echo ""
echo "=== STEP 1 — instant payouts (fast path, local on $B_NAME, no cross-chain wait) ==="
echo "pool before: $(bal $B_TOKEN $POOL $B_RPC)"
i=0
for M in $M1 $M2 $M3; do
  i=$((i+1)); REF=$(cast keccak "payment-$i-$(date +%s)")
  cast send $POOL "payMerchant(address,uint256,bytes32)" $M $AMT $REF --rpc-url $B_RPC --private-key $OPKEY >/dev/null
  echo "  merchant $M paid 10 instantly (ref ${REF:0:10})  balance=$(bal $B_TOKEN $M $B_RPC)"
done
echo "pool after payouts: $(bal $B_TOKEN $POOL $B_RPC)  (fronted 30)"

echo ""
echo "=== STEP 2 — batched settlement via bamboo (replenish pool) ==="
echo "A supply before: $(cast call $A_TOKEN 'totalSupply()(uint256)' --rpc-url $A_RPC|awk '{print $1}')"
cast send $A_TOKEN "approve(address,uint256)" $A_OFT $TOTAL --rpc-url $A_RPC --private-key $OWNER >/dev/null
cast send $A_OFT "sendBatch(uint64,address[],uint256[])" $B_ID "[$POOL]" "[$TOTAL]" --rpc-url $A_RPC --private-key $OWNER >/dev/null
echo "sendBatch(net 30 -> pool) submitted on $A_NAME; waiting for mesh to settle on $B_NAME..."
for n in $(seq 1 15); do sleep 2; pb=$(bal $B_TOKEN $POOL $B_RPC); [ "$pb" != "70000000000000000000" ] && break; done
echo ""
echo "=== result ==="
echo "pool replenished: $(bal $B_TOKEN $POOL $B_RPC)  (back to ~100, net change 0)"
echo "merchants: $(bal $B_TOKEN $M1 $B_RPC) / $(bal $B_TOKEN $M2 $B_RPC) / $(bal $B_TOKEN $M3 $B_RPC)  (got paid instantly)"
echo "A supply after: $(cast call $A_TOKEN 'totalSupply()(uint256)' --rpc-url $A_RPC|awk '{print $1}')  (users' 30 moved cross-chain in 1 batch)"
