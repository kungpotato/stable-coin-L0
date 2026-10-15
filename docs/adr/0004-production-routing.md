# ADR 0004: เส้นทางข้ามเชนใน production

- สถานะ: ตัดสินใจแล้ว (2026-10-15, workshop topic 16)
- ผู้ตัดสินใจ: Kittisak
- ข้อมูลประกอบ: [ibc-vs-layerzero.md](../ibc-vs-layerzero.md)
- ปรับขอบเขตของ: [ADR 0003](0003-usdc-bridge-and-controls.md) (USDC.lz เหลือใช้แค่ใน lab)

## การตัดสินใจ

| asset | ไปเชน Cosmos | ไปเชน EVM |
|---|---|---|
| POTATO | **IBC** (ICS-20 แบบที่มีอยู่) | **LayerZero แบบ integration ทางการ** (endpoint ของ LayerZero Labs) + `PotatoNativeAdapter` |
| USDC | **native USDC ของ issuer ผ่าน IBC** (ตอนนี้คือ USDC บน Injective ผ่าน CCTP V2 เพราะ Noble กำลังปิด) | ไม่ทำเอง ใช้เส้นทางที่ issuer รองรับ |

## เหตุผล

- **POTATO:** IBC ไปฝั่ง Cosmos ปลอดภัยที่สุด (ใช้ light client) และเรามีอยู่แล้ว ส่วนฝั่ง EVM นั้น LayerZero ครอบคลุมเชนมากกว่า IBC Eureka ในตอนนี้ และเราทำ adapter กับ control ไว้แล้ว
- **USDC:** stablecoin มีค่าเพราะ issuer รับรอง ถ้าเรา bridge เอง (USDC.lz) ผู้ถือจะต้องรับความเสี่ยงของ bridge เรา และ liquidity จะแยกจาก USDC ตัวจริง

## ผลที่ตามมา

- **ไม่ไป production:** `UsdcAdapter`, `UsdcOFT` (USDC.lz) และ `MockUSDC` ใช้แค่ใน lab และ devnet
- **LayerZero ที่ self-host (topic 9–12) ไม่ไป production:** ติด license LZBL-1.2 และเชนอื่นจะไม่รู้จัก endpoint ของเรา
  - ใช้ใน production ได้เฉพาะ OApp/OFT ของเรา (MIT) ที่ชี้ไป endpoint ทางการ
  - ข้อยกเว้นคือซื้อ commercial license จาก LayerZero Labs
- **IBC ต้องมี relayer ทำงานตลอด และมี alert ก่อน client หมดอายุ:** เหตุการณ์จริงใน lab คือ `07-tendermint-0` หมดอายุหลังไม่มี relayer อัปเดต 14 วัน
- **ICS-20 ไม่มี rate limit หรือ pause ในตัว:** ถ้าต้องการต้องเพิ่ม IBC middleware (เช่น rate-limiting) แยกต่างหาก
- **USDC ผูกกับนโยบายของ Circle:** ต้องติดตามประกาศของ Circle (ครั้งนี้ Noble ถูกปิดภายในไม่กี่เดือน)

## สิ่งที่ต้องทำต่อ

ดูรายการใน [production-path.md](../production-path.md)
