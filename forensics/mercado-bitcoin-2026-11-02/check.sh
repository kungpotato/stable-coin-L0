#!/usr/bin/env bash
# Live re-verification of the Mercado Bitcoin drain (2026-11-02) on Ethereum mainnet.
# Read-only: balances, nonce, code, USDT balance + Tether blacklist status. No keys, nothing sent.
#   RPC=https://eth.drpc.org ./check.sh     # archive RPC recommended
export PATH="$HOME/.foundry/bin:$PATH"
RPC="${RPC:-https://eth.drpc.org}"
USDT=0xdac17f958d2ee523a2206206994597c13d831ec7

echo "chain head: $(cast block-number --rpc-url "$RPC")"
printf "%-18s %-14s %-7s %-8s %-14s %s\n" LABEL ETH NONCE KIND USDT BLACKLISTED

# label:address  (victim hot wallet, hacker collector, intermediate, ETH parking wallets)
for pair in \
  "VICTIM_MB_hot:0x5cc7787778b4d20a947dcc53b41f593cfd27d548" \
  "HACKER_main:0xe485e7a70b1131216cb47ca4555c4bbb2c742478" \
  "interm_0x8419:0x8419e7824e785c4ac8d9d94a0093c437ab1ff320" \
  "park_0x59a9:0x59a919e8d0582ce62c8de9431b3ebc6fa121731e" \
  "park_0x071f:0x071f8366375fdd21423bb23ae19e4b91f03f9270" \
  "tronETH_0x4d5f:0x4d5f3758938df94a76bfd19652f118ccd7a72c9d" ; do
  lbl=${pair%%:*}; a=${pair##*:}
  eth=$(cast balance "$a" --rpc-url "$RPC" --ether 2>/dev/null)
  nonce=$(cast nonce "$a" --rpc-url "$RPC" 2>/dev/null)
  code=$(cast code "$a" --rpc-url "$RPC" 2>/dev/null); clen=${#code}
  kind=$([ "$clen" -le 2 ] && echo EOA || echo "code")
  usdt=$(cast call "$USDT" "balanceOf(address)(uint256)" "$a" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  bl=$(cast call "$USDT" "isBlackListed(address)(bool)" "$a" --rpc-url "$RPC" 2>/dev/null)
  printf "%-18s %-14.4f %-7s %-8s %-14.2f %s\n" "$lbl" "${eth:-0}" "$nonce" "$kind" "$(echo "scale=2;${usdt:-0}/1000000"|bc)" "$bl"
done
