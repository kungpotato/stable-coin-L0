#!/usr/bin/env bash
# Topic 8: run one call through a chain's 2-of-3 Safe, signed off-line by the given owners (A = TESTNET, B, C).
# usage: testnet/safe-exec.sh <sepolia|arbitrum-sepolia> <to> <calldata> <owners e.g. AB> [--dry]
#   --dry: only simulate execTransaction (eth_call) and print the result, nothing is sent
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
CHAIN="$1"; TO="$2"; DATA="$3"; WHO="$4"; DRY="${5:-}"
case "$CHAIN" in
  sepolia) RPC=$SEPOLIA_RPC_URL; SAFE=$SEPOLIA_SAFE_ADDRESS ;;
  arbitrum-sepolia) RPC=$ARBITRUM_SEPOLIA_RPC_URL; SAFE=$ARBITRUM_SEPOLIA_SAFE_ADDRESS ;;
  *) echo "unknown chain $CHAIN"; exit 2 ;;
esac
ZERO=0x0000000000000000000000000000000000000000
NONCE=$(cast call "$SAFE" 'nonce()(uint256)' --rpc-url "$RPC")
HASH=$(cast call "$SAFE" 'getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)(bytes32)' \
  "$TO" 0 "$DATA" 0 0 0 0 $ZERO $ZERO "$NONCE" --rpc-url "$RPC")
# Safe wants signatures ordered by signer address, ascending
keyof() { if [ "$1" = A ]; then echo "$TESTNET_PRIVATE_KEY"; elif [ "$1" = B ]; then echo "$SAFE_OWNER_B_KEY"; else echo "$SAFE_OWNER_C_KEY"; fi; }
SIGS=""
for c in $(echo "$WHO" | grep -o .); do
  k=$(keyof "$c")
  SIGS="$SIGS$(cast wallet address "$k" | tr A-F a-f) $(cast wallet sign --no-hash "$HASH" --private-key "$k")
"
done
SIGS=$(printf '%s' "$SIGS" | sort | awk 'NF {print substr($2,3)}' | tr -d '\n')
SIG_ARGS=("$SAFE" 'execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)(bool)' \
  "$TO" 0 "$DATA" 0 0 0 0 $ZERO $ZERO "0x$SIGS")
echo "== Safe $SAFE nonce $NONCE, safeTxHash $HASH, signed by: $WHO"
if [ "$DRY" = --dry ]; then
  cast call "${SIG_ARGS[@]}" --from "$TESTNET_ADDRESS" --rpc-url "$RPC" 2>&1 | grep -oE 'GS0[0-9]{2}|true|false|execution reverted[^"]*' | head -1
else
  cast send "$SAFE" 'execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)' "${SIG_ARGS[@]:2}" --rpc-url "$RPC" --private-key "$TESTNET_PRIVATE_KEY" --json | jq -r '"executed: tx " + .transactionHash + " status " + .status'
fi
