#!/usr/bin/env bash
# Launch the bamboo relay MESH: 3 independent attesters + 2 redundant submitters.
# Attesters each hold ONE key and publish sigs; submitters hold no attester keys
# and race to deliver (permissionless). Logs in /tmp/bamboo-{att,sub}-*.log
set -euo pipefail
cd "$(dirname "$0")/relay"
export BAMBOO_THRESHOLD="${BAMBOO_THRESHOLD:-2}"
export BAMBOO_CONFIRMATIONS="${BAMBOO_CONFIRMATIONS:-2}"
export BAMBOO_POLL_MS="${BAMBOO_POLL_MS:-1500}"

# attesters = anvil #1,#2,#3
ATT_KEYS=(
  0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
  0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
  0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
)
i=0
for k in "${ATT_KEYS[@]}"; do
  BAMBOO_ATTESTER_KEY="$k" nohup node --experimental-strip-types attester.ts > "/tmp/bamboo-att-$i.log" 2>&1 &
  echo "attester $i pid $!"; i=$((i+1))
done

# submitters = distinct funded relayer keys (anvil #0, #4) so no nonce clash
BAMBOO_SUBMITTER_ID=0 BAMBOO_RELAYER_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  nohup node --experimental-strip-types submitter.ts > /tmp/bamboo-sub-0.log 2>&1 &
echo "submitter 0 pid $!"
BAMBOO_SUBMITTER_ID=1 BAMBOO_RELAYER_KEY=0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a \
  nohup node --experimental-strip-types submitter.ts > /tmp/bamboo-sub-1.log 2>&1 &
echo "submitter 1 pid $!"
