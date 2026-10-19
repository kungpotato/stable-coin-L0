# Playbook: bridge incident (forged mint / DVN compromise)

ใช้เมื่อพบอย่างใดอย่างหนึ่งต่อไปนี้ (`npm run alert` แจ้งทุกข้อให้เองแบบ real-time):
- `check-supply.sh` ขึ้น ❌
- `npm run audit` ได้ exit 2 (FORGED หรือ POISONED)
- worker ขึ้น `ALERT POISONED`
- minted บนเชนปลายทางมากกว่าที่ lock ไว้

ซ้อมจริงแล้วกับ DEMOWEAK (ดู [postmortem](../incidents/2026-10-15-demoweak-forged-mint.md))
คำสั่งทั้งหมดรันจาก `lz-potato/` (ส่วน `npm run …` รันจาก `workers/`) และต้องโหลด key ก่อน: `set -a; . config/dev-keys.env; set +a`

## 1. หยุดความเสียหาย (เป้าหมาย: ภายในไม่กี่นาที)

ทำทันทีที่สงสัย ไม่ต้องรอให้ยืนยันก่อน เพราะยกเลิกทีหลังได้

| leg มีอะไร | ทำอะไร |
|---|---|
| มี pause (USDC.lz, `StablecoinControls`) | `cast send <leg> 'pause()'` บนทุกเชน |
| ไม่มี pause (DEMO*, PotatoNativeAdapter) | `ASSET=<key> forge script script/ContainOApp.s.sol --rpc-url <rpc> --broadcast` บนทุกเชน |

ตรวจผลว่า containment ใช้ได้จริง:
- ผู้ใช้ส่งเข้าแล้วต้อง revert
- `FORCE=true … ForgeMint.s.sol` แบบจำลองต้อง revert

**ถ้าเจอ message ปลอมที่ commit แล้วแต่ยังไม่ execute** (alert `FORGED_VERIFIED` หรือ audit ขึ้น FORGED และ `inboundPayloadHash` ยังไม่ว่าง): owner หรือ delegate เรียก `endpoint.nilify(oapp, srcEid, sender, nonce, payloadHash)` ทันที (alert จะพิมพ์คำสั่งที่ใส่ค่าครบแล้วให้) slot นั้นจะกลายเป็น NIL ซึ่ง execute ไม่ได้ แต่ packet จริงที่ nonce เดียวกันยัง verify ทับได้ จึงไม่ค้างถาวร ส่วน `burn` ใช้ไม่ได้ในกรณีนี้ เพราะใช้ได้เฉพาะ nonce ≤ lazyInboundNonce ([ADR 0008](../adr/0008-real-time-alerts.md))

## 2. ประเมินความเสียหาย

```bash
npm run audit -- <key>                                    # nonce ไหน FORGED / POISONED
./check-supply.sh <asset>                                 # locked vs minted
npm run snapshot -- <key> <home chain> <oft chain>        # ใครมีสิทธิ์ได้คืนเท่าไหร่ (ไม่นับเหรียญปลอม)
```

บันทึกตัวเลขต่อไปนี้ลง incident doc:
- ยอดที่ไม่มีหลักประกัน
- ยอดที่ถูกดูดออกจาก lockbox
- message ของผู้ใช้ที่ค้างตลอดไป (POISONED)
- ยอดที่ค้างใน adapter เก่า

## 3. อุดรู

- **ถ้า key ของ DVN หลุด:** ถอด DVN นั้นออกจาก config ของทุก OApp แล้วตั้ง ≥ 2 DVN ที่อิสระต่อกัน (`SetOAppSecurity MODE=bc`)
- **ห้ามเปิด path เดิมใหม่ก่อนอุดรู:** ตรวจด้วย `FORCE=true ForgeMint` ที่ใช้ key ที่หลุด ว่าต้อง revert
- **ถ้าสาเหตุไม่ใช่ DVN** (เช่น executor, config หรือ bug ใน OApp): หยุดที่ข้อ 1 ไว้ก่อนจนกว่าจะรู้สาเหตุ

## 4. กู้คืน

- **deploy leg ใหม่ (v2):** ได้ nonce ชุดใหม่และ supply สะอาด ใช้ home token ตัวเดิม และตั้ง security ให้ถูกตั้งแต่ก่อนมี traffic แรก
- **เปลี่ยนชื่อ key เก่าใน `deployments/*.json`:** เป็น `<KEY>_V1` เพื่อเก็บไว้ตรวจย้อนหลัง
- **ชดเชยผู้ใช้จาก treasury:**
  - คนที่ message ค้าง (POISONED): คืนเงินบน home chain
  - ผู้ถือที่มีสิทธิ์ตาม snapshot: treasury lock เหรียญจริงแล้ว bridge ผ่าน v2 ไปให้ supply ใหม่จึงมีหลักประกันครบ
- **ยืนยันผล:** `check-supply` ต้องขึ้น ✅ และ `audit` ของ v2 ต้อง clean ส่วน leg เก่าปิดไว้ถาวร

## 5. หลังเหตุการณ์

- เขียน postmortem แบบ blameless ใน `docs/incidents/`: สรุป, ผลกระทบ, timeline, สาเหตุ, action items
- ทบทวนว่ามี OApp ไหนอีกที่ยังใช้ config แบบเดียวกับที่ถูกเจาะ
