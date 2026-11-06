#!/usr/bin/env bash
# Start a local anvil node on the Prague hardfork (the fork that ships EIP-7702).
# The signing service needs an RPC so `cast wallet sign-auth` can fetch nonce + chain id.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
exec anvil --hardfork prague "$@"
