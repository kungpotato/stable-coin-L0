# ทางไป production (workshop topic 16)

ตาม [ADR 0004](adr/0004-production-routing.md): POTATO ใช้ IBC (ไป Cosmos) และ LayerZero ทางการ (ไป EVM) ส่วน USDC ใช้ของ issuer ผ่าน IBC

**เครื่องหมาย:** ✅ = ทำ/พิสูจน์แล้วใน workshop · ⬜ = ยังไม่ทำ · ❓ = ต้องยืนยันกับเจ้าของระบบ (หาเอกสารทางการไม่เจอ)

## 0. เชน potato เอง

- ⬜ เปิด public testnet แล้วตามด้วย mainnet พร้อม RPC สาธารณะที่เสถียร explorer และ faucet ของ testnet
- ✅ patch bug RPC 2 ตัวของ cosmos/evm แล้ว (potato `main`) ก่อน mainnet ให้ตรวจว่า upstream แก้แล้วหรือยัง แล้วค่อยถอด patch
- ⬜ upgrade policy ผ่าน `x/gov` (ซ้อมแล้วใน week 6) และมีแผนว่าจะ upgrade cosmos/evm อย่างไรโดยไม่ทำให้ IBC กับ LayerZero พัง

## 1. IBC (POTATO ↔ Cosmos, USDC เข้า)

- ✅ ICS-20 + `PotatoBridge` ทำงานได้กับ gaia-local (week 4–5)
- ⬜ **relayer ใน production:** มีอย่างน้อย 2 operator แยกกัน และ alert เมื่อ client ใกล้หมดอายุ (เช่นเหลือน้อยกว่า 1/3 ของ trusting period)
- ⬜ **runbook กู้ client ที่หมดอายุ:** ใช้ gov proposal `MsgRecoverClient` บนทั้งสองเชน ตอนนี้ client ของ lab หมดอายุจริงอยู่ ใช้ซ้อมได้
- ⬜ **USDC:** เปิด channel ไป Injective แล้วรับ native USDC (CCTP V2) ตั้ง allowlist ของ denom ที่ยอมรับ และกำหนดว่า DeFi บน potato จะใช้ `ibc/<hash>` ตัวไหนเป็น USDC
- ⬜ IBC rate-limit middleware สำหรับ ICS-20 (ถ้าต้องการเพดานความเสียหายแบบที่ทำใน OFT)

## 2. LayerZero (POTATO ↔ EVM)

- ❓ **ติดต่อ LayerZero Labs เรื่อง chain integration:** ให้ deploy EndpointV2 และ message lib บน potato ได้ EID ทางการ และให้ executor รองรับ (หาขั้นตอนทางการแบบละเอียดในเอกสารสาธารณะไม่เจอ)
- ❓ **DVN อย่างน้อย 2 รายที่เป็นอิสระต่อกัน** ต้องรองรับ potato ทุก DVN ต้อง deploy contract ของตัวเองบน potato
- ✅ **potato เหมาะกับ LayerZero:** EVM ระดับ Prague, gas ตรงกับ Ethereum และ finality ทันที (`confirmations = 1`) ตามที่พิสูจน์ใน topic 9
- ⬜ **เลิกใช้ contract ของ lab:** EndpointV2/ULN302 ที่ deploy เอง, `LabDVN`, `LabExecutor` และ workers ห้ามใช้ใน production (license LZBL-1.2)
- ⬜ **deploy `PotatoNativeAdapter` และ `PotatoOFT`** โดยชี้ไปที่ endpoint ทางการ แล้วตั้ง peer, enforced options, DVN config (send/receive ต้องตรงกันทั้งสองฝั่ง) และ rate limit ให้กับ POTATO ด้วย
- ⬜ **owner และ delegate ของ OApp เป็น multisig** (เช่น Safe) ไม่ใช่ EOA
- ⬜ **audit** `PotatoNativeAdapter`, `StablecoinControls` และ config ของ path ทั้งหมด
- ✅ supply invariant checker (`check-supply.sh`) นำไปใช้กับ monitoring จริงได้ ต้องเปลี่ยนให้อ่านจาก endpoint ทางการ

## 3. Operations

- ✅ monitoring แบบที่ใช้ใน lab: indexer (Ponder) ติดตามสถานะ message ทั้งสองเชน และ UI แสดงสถานะให้ผู้ใช้เห็น
- ⬜ **alert:** message ค้างนานเกิน X นาที, invariant ผิด (minted > locked), client ใกล้หมดอายุ, relayer หรือ DVN หยุด
- ⬜ **incident runbook:** pause → สอบสวน → unpause ซ้อมแล้วใน topic 14 ต้องเขียนเป็นขั้นตอนพร้อมระบุคนรับผิดชอบ
- ⬜ **ทดสอบนาฬิกาของเชน:** indexer ต้องไม่พึ่งลำดับเวลาข้ามเชน (บทเรียนจาก topic 15)

## แหล่งอ้างอิง

ดู [ibc-vs-layerzero.md](ibc-vs-layerzero.md#แหล่งอ้างอิง)
