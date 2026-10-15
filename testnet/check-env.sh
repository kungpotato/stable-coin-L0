#!/usr/bin/env bash
# Is .env ready for the testnet topics (4, 7, 8)? Checks without ever printing the private key or RPC URLs.
# usage: testnet/check-env.sh
set -uo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "❌ no .env: run  cp .env.example .env  and fill it in"; exit 1; }
git check-ignore -q .env || { echo "❌ .env is NOT gitignored, stop and fix .gitignore first"; exit 1; }
set -a; . ./.env; set +a
fail=0
ok()  { echo "✅ $*"; }
bad() { echo "❌ $*"; fail=1; }

for v in TESTNET_PRIVATE_KEY TESTNET_ADDRESS SEPOLIA_RPC_URL ARBITRUM_SEPOLIA_RPC_URL; do
  [ -n "${!v:-}" ] && ok "$v is set" || bad "$v is empty"
done
[ -n "${ETHERSCAN_API_KEY:-}" ] && ok "ETHERSCAN_API_KEY is set" || echo "➖ ETHERSCAN_API_KEY empty (optional: no contract verification)"
[ $fail -eq 0 ] || { echo "== fill in .env and run again"; exit 1; }

derived=$(cast wallet address "$TESTNET_PRIVATE_KEY" 2>/dev/null) || { bad "TESTNET_PRIVATE_KEY is not a valid private key"; exit 1; }
[ "$(echo "$derived" | tr A-F a-f)" = "$(echo "$TESTNET_ADDRESS" | tr A-F a-f)" ] \
  && ok "private key matches TESTNET_ADDRESS ($TESTNET_ADDRESS)" || bad "private key belongs to $derived, not TESTNET_ADDRESS"
# well-known public dev keys must never be used on a public network
case "$(echo "$derived" | tr A-F a-f)" in
  0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266|0x70997970c51812dc3a010c7d01b50e0d17dc79c8|0xc6fe5d33615a1c52c08018c47e8bc53646a0e101)
    bad "that is a PUBLIC dev key (anvil/potato): anyone can drain it. Use  cast wallet new" ;;
esac

check_chain() { # name, rpc var, expected chainId
  local id
  id=$(cast chain-id --rpc-url "${!2}" 2>/dev/null) || { bad "$1: RPC not reachable"; return; }
  [ "$id" = "$3" ] && ok "$1: RPC is chainId $id" || { bad "$1: RPC is chainId $id, expected $3 (wrong network?)"; return; }
  local wei eth
  wei=$(cast balance "$TESTNET_ADDRESS" --rpc-url "${!2}"); eth=$(cast from-wei "$wei")
  if [ "$(echo "$wei >= 50000000000000000" | bc)" = 1 ]; then ok "$1: balance $eth ETH"
  else bad "$1: balance $eth ETH, need at least 0.05 (about 0.1 recommended)"; fi
}
check_chain "Sepolia" SEPOLIA_RPC_URL 11155111
check_chain "Arbitrum Sepolia" ARBITRUM_SEPOLIA_RPC_URL 421614

[ $fail -eq 0 ] && echo "== ready for the testnet topics" || echo "== not ready yet"
exit $fail
