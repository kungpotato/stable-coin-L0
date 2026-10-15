#!/usr/bin/env bash
# Topic 8: let LayerZero DevTools compute the diff (lz:oapp:wire --dry-run), then send each planned tx through the
# chain's 2-of-3 Safe (owner = delegate = Safe, so DevTools cannot send them itself).
# usage: testnet/devtools/wire-via-safe.sh <owners e.g. AC> [--dry]
set -euo pipefail
cd "$(dirname "$0")"
WHO="$1"; DRY="${2:-}"
PLAN=$(mktemp)
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts --dry-run 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$PLAN"
if grep -q "The OApp is wired, no action is necessary" "$PLAN"; then echo "nothing to change"; exit 0; fi
# each planned tx is a box with "│ Endpoint <name>", "│ OmniAddress <to>" and a wrapped "│ Data 0x..." field
awk '/│ Endpoint/{ep=$3} /│ OmniAddress/{to=$3} /│ Data/{f=1; d=""} f&&/│/{l=$0; sub(/│ Data */,"",l); gsub(/[│ ]/,"",l); d=d l}
     /│ Value/{f=0; sub(/Value.*/,"",d); print ep, to, d}' "$PLAN" |
while read -r EP TO DATA; do
  case "$EP" in
    SEPOLIA_V2_TESTNET) CHAIN=sepolia ;;
    ARBSEP_V2_TESTNET) CHAIN=arbitrum-sepolia ;;
    *) echo "unknown endpoint $EP"; exit 2 ;;
  esac
  ../safe-exec.sh "$CHAIN" "$TO" "$DATA" "$WHO" $DRY
done
