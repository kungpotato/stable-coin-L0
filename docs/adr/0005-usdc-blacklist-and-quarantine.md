# ADR 0005: blacklist ของ USDC.lz และ quarantine แทนการ revert

- สถานะ: ตัดสินใจแล้ว (2026-10-15, workshop topic 6 / P2)
- ต่อจาก: [ADR 0003](0003-usdc-bridge-and-controls.md) (ตอนนั้นตั้งใจไม่ใส่ blacklist ใน OFT)

## บริบท

- **ผลจาก drill ใน topic 3/8:** leg ของ stablecoin ต้องมี control ครบตั้งแต่วันแรก
- **ข้อกำหนดของผู้ออก stablecoin:** ส่วนใหญ่ต้องหยุด address ที่ถูก sanction ได้
- **ช่องว่างเดิม:** blacklist บน home token ของ issuer หยุดได้แค่บน home chain ส่วน USDC.lz บน potato ยังโอนได้อิสระ
- **ข้อจำกัด:** contract ของ leg upgrade ไม่ได้ จึงต้อง deploy v2 แล้วย้ายเงิน

## การตัดสินใจ

1. **ใส่ blacklist ใน `StablecoinControls` (ทั้งสอง leg):**
   - address ที่ถูก blacklist bridge ออกไม่ได้
   - บน `UsdcOFT` โอนเข้าหรือออกจาก address นั้นไม่ได้ (บล็อกที่ `_update`)
2. **role `blacklister` แยกจาก owner:** owner เป็นคนกำหนดว่าใครเป็น blacklister แต่ตัว owner เอง blacklist ไม่ได้ (แยกหน้าที่แบบเดียวกับ Circle)
3. **เงินที่ส่งมาให้ address ที่ถูก blacklist → quarantine ไม่ revert:**
   - ถ้า `lzReceive` revert, message จะค้างตลอดไป (บทเรียนจาก POISONED และ CreditFailed) และ nonce ถัดไปจะติดอยู่หลังมันด้วย
   - **ฝั่ง potato:** mint เข้าตัว contract เองและบันทึกใน `quarantined[to]` เหรียญยังมีหลักประกันแต่ใช้ไม่ได้
   - **ฝั่ง anvil:** เหรียญยังอยู่ใน adapter และถูกบันทึกว่าเป็นของที่กักไว้
4. **`releaseQuarantined(to, payee)` เป็นการตัดสินใจของ owner เท่านั้น:**
   - จ่ายคืนเจ้าของเมื่อถูกปลด blacklist หรือจ่ายให้ issuer ตามคำสั่งศาล
   - ห้ามจ่ายให้ address ที่ยังถูก blacklist
5. **ย้ายไป v2 แบบผู้ใช้ย้ายเอง:**
   - ปิดขาเข้าของ v1 (anvil→potato) แต่เปิดขาออกไว้ให้คนที่ยังถือ v1 ถอนกลับ anvil ได้
   - ผู้ใช้ส่ง v1 กลับ anvil แล้วส่งเข้า v2

## ผลที่ตามมา

- **`check-supply` บน home:** ยอดที่ lock ไว้ต้องหักยอดที่ adapter กักไว้ (`totalQuarantined`) เพราะไม่ได้เป็นหลักประกันให้ supply บนเชนอื่น
- **USDC.lz v1 ยังไม่มี blacklist:** จนกว่าผู้ถือจะย้ายไป v2 ช่วงย้ายจึงยังมีความเสี่ยงเดิม
- **blacklist บนแต่ละ leg แยกกัน:** blacklister ต้อง blacklist ทุกเชน ระบบไม่ sync ให้อัตโนมัติ
