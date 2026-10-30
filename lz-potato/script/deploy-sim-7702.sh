#!/usr/bin/env bash
# Deploy the EIP-7702 lab contracts (MockUSDT + Sweeper7702) to a local anvil.
# Part of runbook topic 17 (Binance 2026-10-29 sim). anvil only — uses anvil's own test keys.
#
#   source script/deploy-sim-7702.sh      # exports USDT และ SWEEP เข้า shell ปัจจุบัน (zsh/bash)
#   ./script/deploy-sim-7702.sh           # แค่ deploy แล้ว print (export กลับ shell ไม่ได้)
#
# ต้องตั้งก่อน: RPC, ATK (address โจร = operator/drop), ATK_PK (key โจร จ่าย gas/deploy)
# default ไป anvil: RPC=127.0.0.1:8545, ATK=acct1; ถ้า export ANVIL_LOG ชี้ไป log ของ anvil
# จะดึง ATK_PK (acct1) มาให้อัตโนมัติ  — ไม่ใช้ set -e เพื่อไม่ให้ค้างใน shell ตอน source
export PATH="$HOME/.foundry/bin:$PATH"

# หา path ตัวเองแบบรองรับทั้ง bash (BASH_SOURCE) และ zsh ($0 ชี้ไฟล์ที่ source)
_src="${BASH_SOURCE:-$0}"
_root="$(cd "$(dirname "$_src")/.." 2>/dev/null && pwd)"
if [ ! -f "$_root/src/lab/MockUSDT.sol" ]; then
  echo "ERROR: หา lz-potato root ไม่เจอ ให้ cd เข้า lz-potato ก่อนแล้ว source script/deploy-sim-7702.sh" >&2
  return 1 2>/dev/null || exit 1
fi

_rpc="${RPC:-http://127.0.0.1:8545}"
_atk="${ATK:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8}"   # anvil acct1
_atk_pk="${ATK_PK:-}"
if [ -z "$_atk_pk" ] && [ -n "${ANVIL_LOG:-}" ] && [ -f "$ANVIL_LOG" ]; then
  _atk_pk="$(grep -oE '^\(1\) (0x[0-9a-fA-F]{64})' "$ANVIL_LOG" | awk '{print $2}')"
fi
if [ -z "$_atk_pk" ]; then
  echo "ERROR: ตั้ง ATK_PK ก่อน (private key ของโจร/ผู้ deploy) หรือ export ANVIL_LOG ชี้ไป log ของ anvil" >&2
  return 1 2>/dev/null || exit 1
fi
if ! "$HOME/.foundry/bin/cast" chain-id --rpc-url "$_rpc" >/dev/null 2>&1; then
  echo "ERROR: ต่อ RPC ไม่ได้: $_rpc (เปิด 'anvil --hardfork prague' หรือยัง)" >&2
  return 1 2>/dev/null || exit 1
fi

echo ">> deploy MockUSDT ..."
USDT="$(forge create "$_root/src/lab/MockUSDT.sol:MockUSDT" \
  --rpc-url "$_rpc" --private-key "$_atk_pk" --broadcast --json | jq -r .deployedTo)"

# ⚠️ --constructor-args เป็น variadic กลืน flag ที่ตามหลัง ต้องวาง "ท้ายสุด" เท่านั้น
echo ">> deploy Sweeper7702 (operator=drop=$_atk) ..."
SWEEP="$(forge create "$_root/src/lab/Sweeper7702.sol:Sweeper7702" \
  --rpc-url "$_rpc" --private-key "$_atk_pk" --broadcast --json \
  --constructor-args "$_atk" "$_atk" | jq -r .deployedTo)"

if [ -z "$USDT" ] || [ "$USDT" = null ] || [ -z "$SWEEP" ] || [ "$SWEEP" = null ]; then
  echo "ERROR: deploy ล้มเหลว (USDT=$USDT SWEEP=$SWEEP)" >&2
  return 1 2>/dev/null || exit 1
fi
export USDT SWEEP
echo "USDT=$USDT"
echo "SWEEP=$SWEEP"
echo "(ถ้ารันด้วย ./ ไม่ใช่ source ให้ copy สองบรรทัดบนไป export เอง)"
