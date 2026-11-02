# bamboo — cross-chain messaging / interoperability lab

A **non-custodial, attestation-based** cross-chain **messaging** protocol between EVM chains
(here: `anvil` ↔ `potato`, where potato is a cosmos/evm chain that also speaks EVM JSON-RPC).

The gateway carries **arbitrary `bytes` payloads** — it is a generic messaging layer, not a
token bridge. Token transfer (`BambooOFT`) is just the **first app** built on top; the gateway
never touches tokens. Any contract implementing `IBambooReceiver` can receive cross-chain messages.

It implements the trust model from the design discussion:

| ชั้น | กลไก | ที่ในโค้ด |
|---|---|---|
| **(1) Signature** | attester เซ็น EIP-191 digest ของ `msgId` (ECDSA / `ecrecover`) | `BambooGateway.receiveMessage` |
| **(2) N-of-M threshold** | ต้องมี ≥ `threshold` attester ที่ต่างกัน (sig เรียง address asc กัน dup) | `BambooGateway` |
| **(3) Encryption** | *ยังไม่ทำใน MVP นี้* — payload ยังเป็น cleartext (ดู spec §5, §10) | — |
| replay guard | `processed[msgId]` | `BambooGateway` |
| burn-and-mint | ไม่มี wrapped token, supply รวมคงที่ | token `mint`/`burnFrom` |

"D" (relay) = **untrusted transport**. มันเดินสาร/เรียงลำดับได้ แต่ **mint เองไม่ได้** เพราะ
mint authority อยู่หลัง threshold check — ตรงกับ positioning "neutral operator ที่พิสูจน์ได้ว่าโกงไม่ได้"

## ⭐ จุดสำคัญ: issuer ไม่เสีย proxy/upgradability ของ token ตัวเอง

bamboo **ไม่ได้เป็นเจ้าของ token** และไม่บังคับให้ issuer ใช้ token ของเรา
Gateway เรียก token ของ issuer ผ่าน interface เล็กๆ เท่านั้น:

```solidity
interface IBridgeToken {
    function mint(address to, uint256 amount) external;      // ให้ gateway mint ตอนรับข้าม chain
    function burnFrom(address from, uint256 amount) external; // allowance-based burn ตอน send
}
```

issuer แค่:
1. `setMinter(gateway, true)` บน token ของตัวเอง (grant role — revoke ได้)
2. ชี้ gateway ไปที่ **proxy address** ของ token

→ token เดิมยังเป็น **proxy upgradable, มี blacklist / pause / cap / controls ครบ**
อัปเกรด logic ได้โดย bamboo ไม่ต้องรู้ ตราบใดที่ interface + role ยังอยู่
(`BambooToken.sol` เป็นแค่ **mock** สำหรับ lab ที่จำลอง role-based token — ไม่ใช่ส่วนของ protocol)

## สถาปัตยกรรม

```
  chain A (anvil)                 relay "D" (off-chain)              chain B (potato)
  BambooOFT  burnFrom token                                         BambooOFT  mint token
     │ gateway.send(payload)       ┌──────────────────┐                ▲ bambooReceive(payload)
     ▼                   MessageSent│ poll events      │ receiveMessage │
  BambooGateway ──── emit payload ─▶│ attesters sign   │── verify ─────▶ BambooGateway
  (generic messaging)              │ collect N-of-M   │  (1)(2) on dst  (generic messaging)
                                   │ submit to dst    │  then calls the receiver app
                                   └──────────────────┘
  gateway carries opaque bytes; only the OFT app knows it's a token transfer
```

## รัน (anvil ↔ anvil — ทดสอบเร็ว, พิสูจน์ protocol)

```bash
# 1) สอง anvil
anvil --port 28545 --chain-id 31338 --hardfork prague --silent &
anvil --port 38545 --chain-id 31340 --hardfork prague --silent &

# 2) deploy + wire (token, gateway, attester set, threshold, seed)
A_NAME=anvilA A_RPC=http://localhost:28545 A_ID=1 \
B_NAME=anvilB B_RPC=http://localhost:38545 B_ID=2 ./deploy.sh

# 3) relay (attester keys = anvil #1,#2,#3 ; relayer = #0)
cd relay && npm install
cp ../.env.example .env            # แก้ได้
set -a; source .env; set +a
node --experimental-strip-types relay.ts &

# 4) demo: ส่ง 100 bUSD A->B แล้ว verify
cd .. && ./demo.sh
```

ผลที่ควรเห็น: A supply ลด 100, B supply เพิ่ม 100, **รวมคงที่** = burn-and-mint

## รัน (anvil ↔ potato — เป้าหมายจริง)

potato เป็น cosmos/evm → มี EVM JSON-RPC ที่ :18545 เหมือน EVM ทั่วไป ต่าง 2 จุด:
1. ต้องสตาร์ท potato ก่อน: `cd ../../potato-chain && make localnet-up` (รอ EVM :18545 ขึ้น)
2. relayer key ฝั่ง potato ต้องมี gas — ตั้ง `BAMBOO_RELAYER_KEY_POTATO=<key ที่ faucet เติมแล้ว>`
   (ดู `potato-chain/scripts/faucet.sh`)

```bash
A_NAME=anvil A_RPC=http://localhost:28545 A_ID=1 A_KEY=<anvil dev key> \
B_NAME=potato B_RPC=http://localhost:18545 B_ID=2 B_KEY=<potato funded key> \
./deploy.sh
# relay: export BAMBOO_RELAYER_KEY_POTATO=<potato funded key> ก่อนรัน
```

หมายเหตุ: potato/cosmos-evm เคยมี getLogs/filter quirk → relay จึง **poll ด้วย block range ชัดเจน** (ไม่ใช้ eth_newFilter) อยู่แล้ว

## ไฟล์

```
src/BambooGateway.sol   GENERIC messaging: send(bytes payload) ; receiveMessage() verify N-of-M -> deliver
src/IBambooReceiver.sol interface ของ app ที่รับ message (bambooReceive)
src/BambooOFT.sol       app แรก: burn-and-mint token transfer บน messaging layer
src/IBridgeToken.sol    interface ที่ OFT ต้องการจาก token ของ issuer (mint / burnFrom)
src/BambooToken.sol     LAB MOCK ของ issuer token (role-based) — ไม่ใช่ protocol
deploy.sh               deploy gateway+token+OFT + wire attesters/peers -> deployments/local.json
relay/relay.ts          all-in-one relay (lab convenience; holds all attester keys)
relay/common.ts         shared: chain setup, domain digest, sig store, checkpoints
relay/attester.ts       ONE attester (one key) — signs + publishes sigs to the store
relay/submitter.ts      permissionless relayer — collects >=threshold sigs, submits (run many)
relay/self-relay.ts     user rescues ONE stuck message with published sigs (no attester keys)
run-mesh.sh             launch 3 attesters + 2 redundant submitters
demo.sh                 ส่ง A->B ผ่าน OFT + verify supply
```

## Permissionless & redundant relaying

relay แยกเป็น 2 บทบาท → ไม่เป็น chokepoint:
- **attester** (มี key, = trust): เซ็น digest แล้ว publish ลายเซ็นลง shared store — 1 ไฟล์ต่อ signer (ไม่ clobber กัน)
- **submitter** (ไม่มี key, = transport): เก็บ ≥threshold sigs แล้ว submit — รันกี่ตัวก็ได้ แข่งกัน ตัวแพ้เห็น `replay` แล้วหลบ
- **self-relay**: user กู้ message ที่ค้างเองได้ ด้วย sigs ที่ publish ไว้ โดย**ไม่ต้องมี attester key**

พิสูจน์แล้วใน lab: 2 submitters → ตัวนึง deliver อีกตัว "already delivered"; ปิด submitter หมด → `self-relay.ts <msgId>` ส่งเองได้
→ relay ดับ/เซ็นเซอร์ ก็ไม่ทำเงินติด (liveness ไม่ขึ้นกับ operator คนเดียว)

```bash
./run-mesh.sh                                  # 3 attesters + 2 submitters
node --experimental-strip-types relay/self-relay.ts <msgId>   # rescue by anyone
```

## Security hardening (จาก self-audit — แก้แล้ว)

| id | finding | fix |
|---|---|---|
| H-1 | ไม่มี domain separation → cross-instance replay | signed digest ผูก `block.chainid` + `address(this)` (`BambooGateway.digest()`); relay เซ็น digest ของ dst gateway |
| H-2 | relay ไม่รอ finality → reorg double-mint | relay act เฉพาะ block ≤ `head - CONFIRMATIONS` |
| H-3 | burned-but-undeliverable → เงินหาย | `receiveMessage` try/catch เก็บ `failed[msgId]` + `retry()` |
| H-4 | ถอด attester ต่ำกว่า threshold → DoS | `setAttester(remove)` บังคับ `attesterCount >= threshold` |
| H-5 | relay พลาด event ตอน downtime | persist `.checkpoint.json` + resume |
| M-1 | ไม่มี pause | `setPaused()` + `whenNotPaused` |
| M-2 | mint ไม่เช็ค whitelist | `whitelisted[to]` ใน `send`/`bambooReceive` |
| M-3 | ไม่มี mint cap | rolling `dailyMintCap` ใน OFT |
| M-4 | admin EOA เดียว | 2-step ownership (owner ควรเป็น multisig+timelock) |
| L-2 | reentrancy | `nonReentrant` + checks-effects-interactions |

> ยังเป็น self-audit บน lab — **ยังต้อง independent audit + formal verification** ก่อนแตะเงินจริง
> L-1 (keys ใน env) ยังคงอยู่โดยตั้งใจ: lab เท่านั้น, production = HSM/MPC + issuer รัน attester เอง

## ยังไม่ได้ทำ (roadmap ตาม spec)
- (3) payload encryption (HPKE) + zk amount privacy
- BOT เป็น co-signer role แยก (ตอนนี้รวมใน attester set)
- control messages: freeze / burn-seize / whitelist-sync ข้ามเชน
- supply reconciliation ↔ reserve
- BLS aggregate signatures (ลด gas ฝั่ง verify)
