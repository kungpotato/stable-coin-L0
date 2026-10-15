# IBC vs LayerZero สำหรับ potato-chain (workshop topic 16)

เอกสารนี้เปรียบเทียบจากสิ่งที่เราสร้างและวัดเองใน workshop (topic 9–15) ประกอบกับข้อมูลภายนอกที่อ้างไว้ท้ายเอกสาร
ข้อมูลภายนอกตรวจเมื่อ 2026-10-15 ควรตรวจซ้ำก่อนตัดสินใจจริง

## สิ่งที่ potato มีอยู่ตอนนี้

| | IBC (week 4–5) | LayerZero lab (topic 9–15) |
|---|---|---|
| เชนคู่ | gaia-local (Cosmos) | anvil (EVM) |
| asset | POTATO ผ่าน ICS-20 (`PotatoBridge` + precompile 0x0802) | POTATO (NativeOFTAdapter) และ USDC.lz (OFT + rate limit + pause) |
| off-chain | Hermes relayer | DVN + Executor ที่เราเขียนเอง (workers/) |
| สถานะวันนี้ | **ใช้ไม่ได้: light client `07-tendermint-0` หมดอายุ (Expired)** เพราะ trusting period 14 วัน แต่ไม่มี relayer อัปเดตมาราว 18 วัน | ใช้ได้ ส่งถึงใน 6–11 วินาที |

## เทียบทีละประเด็น

| ประเด็น | IBC | LayerZero |
|---|---|---|
| **ใครยืนยันว่า message จริง** | light client ของอีกเชนบน chain เอง (ตรวจ consensus ของอีกฝั่ง) ไม่ต้องเชื่อคนกลางนอกจาก validator ของเชนทั้งสอง | DVN ที่ app เลือก ปลอดภัยเท่ากับ DVN ที่ตั้งไว้ (เอกสารแนะนำให้มีหลาย DVN อิสระ) |
| **ถ้า off-chain หยุด** | **อันตรายกว่า:** ถ้า relayer หยุดนานเกิน trusting period client จะหมดอายุ ต้อง gov proposal (`MsgRecoverClient`) ทั้งสองเชน (เกิดกับเราจริง) | message แค่รอ พอ worker กลับมาก็ส่งต่อเอง (ทดสอบแล้วใน 12.6) |
| **ใช้กับเชนแบบไหน** | Cosmos ↔ Cosmos ใช้ได้เต็มที่; ฝั่ง EVM ผ่าน IBC Eureka (Ethereum ใช้งานจริงแล้ว ส่วน L2 อื่นยังไม่ยืนยัน ดูแหล่งอ้างอิง) | EVM และ non-EVM จำนวนมาก แต่ต้องมี endpoint ที่ LayerZero deploy บนเชนนั้น |
| **หน้าตาของ token ปลายทาง** | voucher `ibc/<hash>` ซึ่งแต่ละเส้นทางได้ denom ต่างกัน | address เดียวต่อเชน (OFT) และกำหนด supply ร่วมกันได้ |
| **การควบคุมของผู้ออก stablecoin** | ICS-20 ไม่มี rate limit หรือ pause ในตัว ต้องเพิ่ม middleware เอง | ทำใน OFT ได้เอง (ทำแล้วใน topic 14) |
| **การเข้าร่วม** | permissionless: เปิด channel เองได้ทันทีถ้าอีกเชนมี IBC | potato ยังไม่อยู่ในเครือข่าย LayerZero จริง ต้องให้ LayerZero Labs deploy endpoint และ DVN/executor ต้องรองรับ potato |
| **license** | Apache-2.0 (ibc-go) | protocol/messagelib เป็น **LZBL-1.2: ใช้ใน production ไม่ได้ถ้าไม่ซื้อ license** จนถึง 2027-12-14 (หลังจากนั้นเป็น GPL-2.0+ เฉพาะ permissionless app) ส่วน OApp/OFT เป็น MIT |

## ผลต่อ USDC ในโลกจริง (ข้อมูลล่าสุด)

- **USDC ที่ bridge เองอย่าง `USDC.lz` ไม่ใช่ USDC ของ Circle:** เป็น "bridged USDC" ที่ความเสี่ยงของ bridge ตกอยู่กับผู้ถือ และแยก liquidity จาก USDC ตัวจริง
- **Circle กำลังปิด USDC บน Noble ซึ่งเคยเป็นทางหลักของ USDC ใน Cosmos (ตามแหล่งข่าว):**
  - หยุด mint ใหม่ 2026-10-13
  - pause เต็มรูปแบบ 2027-01-12
  - ทางแทนคือ native USDC บน Injective (CCTP V2) แล้วส่งต่อผ่าน IBC
- **ผลต่อ potato:** ถ้าต้องการ USDC "ของจริง" ฝั่ง Cosmos เส้นทางที่เป็นไปได้คือ IBC ไป Injective ซึ่งต้องมี relayer ที่เดินตลอดเวลา เพราะบทเรียนข้างบน

## ข้อสรุปที่ได้จาก workshop

1. **IBC ไม่ใช่ "ตั้งครั้งเดียวจบ":** relayer ต้องเดินตลอด และต้องมี alert ก่อน client หมดอายุ
2. **LayerZero แบบที่เรา self-host ใช้ใน production ไม่ได้** ทั้งเพราะ license และเพราะเชนอื่นต้องเห็น endpoint เดียวกัน ทางจริงคือ integration แบบทางการ
3. **การเลือกเส้นทางของ stablecoin ขึ้นกับว่าผู้ออกเหรียญ (issuer) รองรับทางไหน** ไม่ใช่เทคโนโลยีอย่างเดียว

## แหล่งอ้างอิง

- LayerZero Business License 1.2: https://github.com/LayerZero-Labs/LayerZero-v2 (`LICENSE-LZBL-1.2`)
- LayerZero integration checklist: https://docs.layerzero.network/v2/tools/integration-checklist
- LayerZero deployed endpoints: https://docs.layerzero.network/v2/deployments/deployed-contracts
- LayerZero DVN/executor config: https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config
- IBC Eureka (Ethereum): https://www.theblock.co/post/350316/interchain-labs-launches-ibc-eureka-to-connect-ethereum-to-the-cosmos-ecosystem
- Cosmos Stack roadmap 2026: https://cosmos.network/blog/the-cosmos-stack-roadmap-2026
- Circle ปิด USDC บน Noble: https://www.circle.com/blog/circle-is-discontinuing-support-for-usdc-and-cctp-v1-on-noble
- Injective native USDC: https://injective.com/blog/usdc-migration
