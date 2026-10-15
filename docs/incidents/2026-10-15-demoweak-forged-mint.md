# Postmortem: DEMOWEAK forged mint (drill)

- วันที่: 2026-10-15 · ประเภท: **drill บน lab** (ตั้งใจโจมตีเอง) · สถานะ: ปิดแล้ว
- playbook ที่ใช้: [bridge-incident.md](../runbooks/bridge-incident.md)

## สรุป

ผู้โจมตีได้ key ของ DVN-A ซึ่งเป็น DVN ตัวเดียวที่ path anvil → potato ของ DEMOWEAK ต้องผ่าน จากนั้นลำดับเหตุการณ์คือ:
1. ปลอม message ว่า anvil lock ไว้ 1,000,000 DEMOWEAK และได้ DEMOWEAK.lz บน potato โดยไม่มีของจริงรองรับ
2. bridge 100 ในนั้นกลับ ทำให้ดึงเหรียญจริงออกจาก lockbox บน anvil จนหมด
3. message ปลอมไปใช้ nonce 2 ของ path ทำให้การโอนจริงของผู้ใช้ที่ได้ nonce 2 ส่งไม่ถึงตลอดไป

## ผลกระทบ

| รายการ | จำนวน |
|---|---|
| mint ปลอม (ไม่มีหลักประกัน) | 1,000,000 DEMOWEAK.lz (ผู้โจมตีถือ 999,900, เผาไป 100) |
| ถูกดูดออกจาก lockbox บน anvil | 100 DEMOWEAK |
| การโอนจริงที่ค้างตลอดไป (POISONED nonce 2) | 1 DEMOWEAK |
| ค้างใน adapter v1 ถอนคืนไม่ได้ | 3 DEMOWEAK (1 จาก nonce 2 และ 2 จาก nonce 3) |
| ผู้ถือที่ถูกต้องที่เสียหลักประกัน | dev0: 102 DEMOWEAK.lz |
| **treasury จ่ายชดเชย** | **103** (คืนเงิน 1 + migrate 102) |

POTATO, USDC.lz และ DEMOSAFE ไม่ได้รับผลกระทบ เพราะ OApp แต่ละตัวมี config และ nonce space ของตัวเอง

## Timeline (ลำดับใน drill)

1. baseline: โอนจริง 100 ไป dev0 ผ่าน nonce 1
2. **โจมตี:** `ForgeMint` ใช้ key DVN-A → verify → commit → lzReceive แล้ว mint 1,000,000 ให้ผู้โจมตี (nonce 2)
3. **ดูด lockbox:** ผู้โจมตีส่ง 100 กลับ anvil ทำให้ lockbox ลดจาก 100 เป็น 0
4. **ตรวจจับ (ครั้งแรก):** `check-supply` ขึ้น ❌ ทั้ง minted > locked และ inbound nonce > outbound
5. ผู้ใช้โอนจริง 1 (nonce 2) ค้าง แล้วโอนจริง 2 (nonce 3) ส่งถึง **หลังจากนั้นการนับ nonce ไม่จับ forgery อีก** (sent 3 = delivered 3)
6. **แก้การตรวจจับ:**
   - `npm run audit` เทียบ payload hash ราย nonce แล้วพบ nonce 2 เป็น FORGED+POISONED
   - worker ขึ้น ALERT POISONED เพียง 1 ครั้งจากการ rescan 48 message
7. **หยุดความเสียหาย:** `ContainOApp` ตั้ง BlockedMessageLib ให้ทั้งสองเชน ใช้เวลา 14 วินาที แล้วตรวจว่าผู้ใช้ส่งไม่ได้และ forge ซ้ำไม่ได้
8. **อุดรู:** ถอด DVN-A แล้วตั้ง v2 ให้ต้องผ่าน DVN-B + DVN-C ตรวจด้วย `FORCE` ForgeMint ที่ใช้ key A ได้ `LZ_ULN_Verifying`
9. **กู้คืน:**
   - deploy v2 (adapter + OFT ใหม่ ใช้ DemoToken เดิม)
   - `snapshot`: dev0 มีสิทธิ์ 102 ส่วนผู้โจมตีได้ 0
   - คืนเงิน 1 ให้ผู้ส่ง nonce 2 และ treasury bridge 102 ผ่าน v2 ไปให้ dev0
10. **ยืนยัน:** v2 มี locked 102 = minted 102 ✅, audit clean, โอนกลับได้ และมีแค่ B กับ C ที่ verify

## สาเหตุ

1. **ตรงๆ:** path ที่มี DVN ตัวเดียว key หลุด 1 ตัวก็เท่ากับยอมรับ message อะไรก็ได้
2. **สาเหตุที่ลึกกว่า:**
   - DEMOWEAK ไม่ได้ตั้ง security ของตัวเอง จึงใช้ default ของ endpoint ซึ่งมี DVN ตัวเดียว
   - DEMOWEAK ไม่มี pause และไม่มี rate limit ที่จะจำกัดความเสียหาย
3. **การตรวจจับเดิม:** ใช้การนับ nonce ซึ่งพลาดเมื่อ nonce จริงตามทัน ส่วน worker เดิมตีความ "nonce ≤ lazy และ slot ว่าง" ว่าส่งถึงแล้ว ทำให้ซ่อน message ที่ค้างไว้

## อะไรได้ผล

- `check-supply` จับ minted > locked ได้ทันที
- BlockedMessageLib ใช้ได้ทันทีกับ OApp ที่ไม่มี pause และไม่ต้อง upgrade contract
- แยก nonce space ด้วย v2 พร้อมใช้ home token เดิม ทำให้กู้คืนได้สะอาด และ invariant ยืนยันได้ด้วยเครื่องมือเดิม

## อะไรไม่ได้ผล

- การตรวจจับที่นับ nonce ถูกหลอกได้ (แก้แล้ว: payload hash audit)
- worker แสดงผลผิดว่า "already delivered" และ "waiting for DVN" (แก้แล้ว: ALERT POISONED)
- 3 DEMOWEAK ค้างใน adapter v1 ถาวร เพราะ adapter ไม่มีทางกู้เหรียญ

## Action items

| # | งาน | สถานะ |
|---|---|---|
| 1 | audit ตาม payload hash ใน `check-supply` | ✅ `49a61c2` |
| 2 | worker แจ้ง POISONED แทน "already delivered" | ✅ `57fe13e` |
| 3 | ทุก OApp ใน production ต้องตั้ง security เอง และต้องผ่าน ≥ 2 DVN ที่อิสระต่อกัน | ✅ POTATO, USDC.lz, DEMOSAFE ย้ายไปใช้ B + C แล้ว (USDC ผ่าน pause → config → unpause ใช้เวลา 16 วินาที) ตรวจด้วย `check-security.sh` ส่วน Ping เป็นแอปทดสอบ ยังใช้ A |
| 4 | ทุก leg ต้องมี pause + rate limit (PotatoNativeAdapter ยังไม่มี) | ⬜ |
| 5 | adapter รุ่นต่อไปควรมีทางกู้เหรียญที่ค้าง (เช่น owner-gated sweep สำหรับ leg ที่ปิดแล้ว) | ⬜ ต้องออกแบบไม่ให้กลายเป็นช่องโหว่ใหม่ |
| 6 | alert แบบ real-time ทันทีที่ audit/worker ขึ้น FORGED/POISONED (ตอนนี้ต้องรันเอง) | ⬜ topic 8 |
