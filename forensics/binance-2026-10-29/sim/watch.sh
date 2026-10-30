. "$(dirname "$0")/env.sh"; last=0x
while true; do
  code=$($C code $B14 --rpc-url $R 2>/dev/null); b=$($C block-number --rpc-url $R 2>/dev/null)
  if [ "$code" != "$last" ]; then echo "$(date +%T) block $b  ALERT B14 code changed: ${last} -> ${code}"; last=$code; fi
  sleep 1
done
