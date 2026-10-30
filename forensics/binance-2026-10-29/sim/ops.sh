. "$(dirname "$0")/env.sh"; U=0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc
while [ ! -f "$(dirname "$0")/stop-ops" ]; do $C send $U --value 0.01ether --rpc-url $R --private-key $B14_KEY >/dev/null 2>&1; done
