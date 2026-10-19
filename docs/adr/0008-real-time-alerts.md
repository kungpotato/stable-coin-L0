# ADR 0008: alert แบบ real-time และใช้ nilify กับ message ปลอมที่ยังไม่ execute

- สถานะ: ตัดสินใจแล้ว (2026-10-19) · ใช้ใน lab แล้ว (runbook 8.22–8.24)
- ต่อจาก: action item ข้อ 6 ของ [postmortem DEMOWEAK](../incidents/2026-10-15-demoweak-forged-mint.md), [ADR 0006](0006-inbound-mint-cap.md)

## บริบท

- **การตรวจจับเดิมต้องมีคนรันเอง:** ทั้ง `check-supply` และ `npm run audit` ใน drill DEMOWEAK คนรันเองหลังเกิดเหตุ
- **เหตุการณ์ Cysic (2026-10-17):** เริ่มเทขาย 5 นาทีหลัง mint แต่ blacklist ตามมาที่นาทีที่ 76
- **playbook เดิมให้ใช้ `endpoint.burn` กับ message ปลอมที่ commit แล้วแต่ยังไม่ execute ซึ่งผิด:** จาก source ของ EndpointV2 `burn` ใช้ได้เฉพาะ nonce ≤ `lazyInboundNonce` แต่ message ที่เพิ่ง commit อยู่ที่ nonce ถัดไป จึงได้ `LZ_InvalidNonce`

## การตัดสินใจ

1. **`workers/src/alert.ts` (`npm run alert`)**
   - ตรวจทั้งสองเชนทุก 3 วินาที
   - อ่านอย่างเดียว ไม่ถือ key
   - กฎที่ไม่ต้องคุยกับ RPC อยู่ใน `alertrules.ts` และมี unit test

   | alert | ระดับ | เงื่อนไข |
   |---|---|---|
   | `FORGED_VERIFIED` | 🚨 | endpoint ปลายทาง commit (`PacketVerified`) payload ที่ต้นทางไม่เคยส่ง แจ้ง**ก่อน** `lzReceive` พร้อมคำสั่ง nilify |
   | `SUPPLY` | 🚨 | minted บนเชนอื่น > locked บน home ลบยอดที่ home leg กักไว้ |
   | `POISONED` | 🚨 | packet จริงส่งไม่ถึงตลอดไป เพราะ nonce ถูกใช้กับ payload อื่น (ต้องยืนยัน 2 tick ติดกัน) |
   | `STUCK` | ⚠️ | packet จริงยังไม่ถึงหลัง `STUCK_SECONDS` |
   | `HELD` | ⚠️ | ถูกกักเพราะเกิน inbound cap หรือเพราะ blacklist |
   | `RPC` | ⚠️ | เชนไม่ตอบ 3 tick ติดกัน |
   | `PAUSED` / `UNPAUSED` / `NILIFIED` / `BURNT` / `SKIPPED` | ℹ️ | ใครเข้ามาแก้ระบบ ทำให้ช่องทาง alert เป็น timeline ของ incident ด้วย |

   - **ช่องทางแจ้ง:** console, `workers/state/alerts.jsonl`, `ALERT_WEBHOOK_URL` (JSON ที่มี `text` และ `content` ใช้ได้ทั้ง Slack และ Discord) และ `ALERT_DESKTOP=1` (notification ของ macOS)
   - **แจ้งไม่ซ้ำ:** แต่ละเงื่อนไขแจ้งครั้งเดียว และแจ้งอีกครั้งตอน resolved
2. **message ปลอมที่ commit แล้วแต่ยังไม่ execute → `endpoint.nilify(oapp, srcEid, sender, nonce, payloadHash)`** โดย owner หรือ delegate ของ OApp
   - slot ของ nonce นั้นกลายเป็น NIL จึง execute ไม่ได้อีก
   - packet จริงที่ nonce เดียวกันยัง verify ทับได้ จึงไม่กลายเป็น POISONED เหมือนใน drill DEMOWEAK เดิม
   - `burn` ใช้กับ nonce ที่อยู่หลัง `lazyInboundNonce` แล้วเท่านั้น
3. **`inboundState` ถือว่า NIL = pending:** รอ packet จริงมา verify ไม่ได้แปลว่า poisoned

## ผลจากการซ้อมบนเชน

- **ปลอม DEMOWEAK v2 ด้วย key ของ DVN B และ C (`ForgeMint` + `DVN_IDS`/`DVN_KEYS` + `STOP_AFTER_COMMIT`):**
  - `FORGED_VERIFIED` ขึ้นภายใน tick เดียวหลัง commit
  - delegate เรียก nilify แล้ว alert แจ้ง `NILIFIED` และ resolved ให้เอง
  - การโอนจริงครั้งถัดไปใช้ nonce เดียวกันและส่งถึง (audit 2/2 OK)
- **ซ้อมกรณีอื่น:**
  - pause USDC: ได้ `PAUSED` → `STUCK` หลัง 30 วินาที → `UNPAUSED` → `STUCK` resolved
  - ลด cap ของ POTATO เหลือ 1: ได้ `HELD` แล้ว owner release
- **เจอของจริงตั้งแต่เปิด worker:** `SUPPLY:DEMOWEAK_V1` (unbacked 999,999 จาก drill ใน topic 3 ซึ่ง leg ปิดไปแล้ว)
- **bug ที่เจอระหว่างซ้อม:**
  - index ของ `PacketVerified` สแกน block ปลายสุดครั้งเดียว ถ้า log ของ block นั้นยังไม่ถูก index (cosmos/evm) จะเห็นแต่ payload ปลอม ทำให้แจ้ง POISONED ผิด
  - แก้แล้ว: ให้สแกนซ้อน 5 block ทุกครั้ง และให้ POISONED ต้องยืนยัน 2 tick ติดกัน
  - ส่งจริงอีก 5 ครั้งไม่มี alert ผิด

## ผลที่ตามมา

- **worker ตัวเดียวคือ single point of failure:** ใน production ต้องรันหลายที่ คนละเครื่องและคนละ RPC และต้องมี heartbeat แยก (ถ้าไม่มี alert ไม่ได้แปลว่าทุกอย่างปกติ)
- **ยังไม่มีการตอบสนองอัตโนมัติ:** เช่น auto-pause เมื่อเจอ `FORGED_VERIFIED`
  - ต้องให้บอตถือ key ที่ pause ได้ จึงควรแยก role "pauser" ที่ทำได้แค่ pause ไม่ให้ใช้ key ของ owner
  - เป็นงานถัดไป
- **ถ้าผู้โจมตี commit และ execute ใน tx เดียว:** alert จะมาหลัง execute แล้ว ตอนนั้นสิ่งที่จำกัดความเสียหายคือ inbound cap (ADR 0006) และ pause
