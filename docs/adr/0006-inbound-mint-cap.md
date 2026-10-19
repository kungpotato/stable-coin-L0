# ADR 0006: เพดาน mint ขาเข้า (inbound mint cap)

- สถานะ: ตัดสินใจแล้ว (2026-10-19) · deploy ใน lab แล้วเป็น USDC v3 (runbook 6.12–6.13)
- ต่อจาก: [ADR 0003](0003-usdc-bridge-and-controls.md) (rate limit ขาออก), [ADR 0005](0005-usdc-blacklist-and-quarantine.md) (quarantine)

## บริบท

- **rate limit เดิมนับเฉพาะขาออก:** `_outflow` ตอนส่ง ส่วน `_inflow` แค่คืนโควตา ทำให้ไม่มีอะไรจำกัดยอดที่ mint หรือ unlock ตอนรับ
- **ผลใน drill DEMOWEAK (topic 3):** key ของ DVN-A หลุด แล้ว message ปลอมใบเดียว mint ได้ 1,000,000
- **เหตุการณ์จริง Cysic (2026-10-17):**
  - ผู้โจมตีเข้าถึงฐานข้อมูลของ service ที่ทำงานรองรับ bridge แล้วสร้างคำสั่ง mint ปลอม 10M CYS
  - เริ่มเทขายภายใน 5 นาที และย้ายราว $727K ออกไป Ethereum ก่อนถูก blacklist ที่นาทีที่ 76
- **ข้อสรุป:** ถ้าผู้ยืนยันถูกเจาะ control ฝั่งส่ง (rate limit, pause ขาส่ง) ไม่ช่วยเลย เพราะ message ปลอมไม่ได้ผ่านฝั่งส่ง

## การตัดสินใจ

1. **ตั้งเพดานต่อเชนต้นทาง** ด้วย `setInboundCaps([{srcEid, limit, window}])` ใน `StablecoinControls` ซึ่ง leg ของ USDC ทั้งสองฝั่งใช้ร่วมกัน
   - ยอดที่ใช้ไปลดลงแบบเส้นตรงตามเวลา (แบบเดียวกับ `RateLimiter`)
   - `window = 0` หมายถึงไม่มีเพดาน (ค่าเริ่มต้น เพื่อไม่ให้ leg เดิมเปลี่ยนพฤติกรรม)
   - `limit = 0` คู่กับ `window > 0` หมายถึงกักทุกอย่าง
2. **message ที่เกินเพดาน → quarantine ทั้งก้อน ไม่ revert และไม่แบ่งจ่าย:**
   - ถ้า revert message จะค้างถาวร (ADR 0005)
   - ถ้าแบ่งจ่าย ผู้โจมตีก็ยังได้ส่วนที่พอดีเพดานจาก message ปลอมทุกใบ
   - ฝั่ง OFT จะ mint เข้าตัว contract เอง ส่วนฝั่ง adapter เหรียญยังอยู่ใน adapter และ `totalQuarantined` ทำให้ `check-supply` นับถูกต้อง
3. **ยอดที่ถูกกักไม่กินเพดานและไม่คืนโควตาขาออก:** ไม่อย่างนั้น message ปลอมจะเติมโควตาให้ผู้โจมตีถอนออก
4. **ปล่อยเงินด้วย `releaseQuarantined` เดิม** เป็นการตัดสินใจของ owner หลังตรวจแล้ว และไม่นับรวมในเพดาน (เช่นการโอนก้อนใหญ่ที่ถูกต้อง)
5. **blacklist มาก่อนเพดาน:** เงินของ address ที่ถูก blacklist ถูกกักโดยไม่กินเพดาน

## ผลที่ตามมา

- **ความเสียหายสูงสุดจากผู้ยืนยันที่ถูกเจาะ ≤ limit ต่อ window ต่อเชนต้นทาง** ไม่ว่าจะปลอมยอดเท่าไหร่ (unit test `test_forgedMintIsLimitedToCap`: ปลอม 10M แล้วยิงซ้ำเป็นก้อนเล็ก ผู้โจมตีได้ไม่เกินเพดาน)
- **การโอนที่ถูกต้องแต่ใหญ่กว่าเพดานต้องรอ owner ปล่อย** จึงต้องตั้งเพดานจากข้อมูล volume จริง และมีขั้นตอนตรวจที่ชัดเจน
- **indexer และ UI ต้องรู้จัก event `InboundCapExceeded` และ `Quarantined`** ไม่งั้นจะแสดงว่า delivered (เป็นงานที่ค้างอยู่แล้วจาก ADR 0005)
- **deploy แล้วเป็น USDC v3:** 10,000 USDC ต่อชั่วโมงต่อเชนต้นทาง (`DeployUsdcBridge` กับ `INBOUND_CAP=true`) ปิดขาเข้าของ v2 แล้วและย้ายเงินของ dev0 แล้ว พิสูจน์บนเชนว่าก้อนที่เกินเพดานถูกกักทั้งก้อน message ไม่ค้าง และ invariant ✅
- **vault และ composer ของ topic 7:** deploy คู่ใหม่ให้ v3 แล้ว (runbook 7.8) และ USDC.lz v2 เหลือ supply 0
- **ยังค้าง:**
  - `PotatoNativeAdapter` ยังไม่มี control นี้ (และยังไม่มี pause หรือ rate limit)
- **ไม่ได้แทนที่การมี ≥ 2 DVN ที่อิสระ หรือ alert แบบ real-time:** เพดานแค่จำกัดความเสียหายระหว่างรอให้คนตอบสนอง
