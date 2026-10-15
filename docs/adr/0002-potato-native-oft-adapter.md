# ADR 0002: lock POTATO ด้วย NativeOFTAdapter

- สถานะ: ตัดสินใจแล้ว (2026-10-15, workshop topic 13)
- ผู้ตัดสินใจ: Kittisak
- ต่อจาก: [ADR 0001](0001-counterpart-chain-and-home-chains.md) (POTATO home = potato)

## บริบท

ต้องเลือกว่าฝั่ง potato (home ของ POTATO) จะ lock เหรียญด้วย `NativeOFTAdapter` หรือ `OFTAdapter` ที่ครอบ WPOTATO

ข้อเท็จจริงที่ตรวจบนเชนแล้ว (topic 13):

- WPOTATO (`0xEeee…EEeE`) **ไม่ใช่ wrapped token** แต่เป็น ERC-20 precompile (cosmos/evm `werc20`) ที่มองเห็น native balance ตรงๆ
  - `balanceOf(x)` = native balance ของ x
  - `deposit()` คืนเหรียญกลับ และ `withdraw()` แค่ emit event
- `totalSupply` ของ WPOTATO = supply ทั้งเชน ซึ่ง**เพิ่มขึ้นทุก block** จาก x/mint (staking rewards)
- ไม่ว่าเลือกทางไหน สิ่งที่ถูก lock คือ native POTATO ตัวเดียวกัน

## การตัดสินใจ

| ฝั่ง | contract |
|---|---|
| potato | `PotatoNativeAdapter` (= `NativeOFTAdapter`, local decimals 18) |
| anvil | `PotatoOFT` (= `OFT` "Potato"/"POTATO", 18 decimals) |

## เหตุผล

- **ใช้ง่ายกว่า:** tx เดียว ผู้ใช้ส่ง POTATO เป็น `msg.value` ไม่ต้อง approve
- **ไม่พึ่ง precompile:** พฤติกรรมของ precompile เปลี่ยนได้เมื่อ upgrade cosmos/evm ส่วน `msg.value` เป็น EVM มาตรฐาน

## ผลที่ตามมา

- **`msg.value` ต้องเท่ากับ `fee + amount (ตัด dust แล้ว)` พอดี:** ถ้าต่างไปแม้ 1 wei จะ revert ด้วย `IncorrectMessageValue` client ต้องตัด dust เอง
- **Dust:** ข้ามเชนได้ละเอียดที่สุด 10^12 wei (shared decimals 6) ส่วนที่เศษกว่านั้นไม่ออกจาก wallet
- **ผู้รับบน potato ต้องรับ native ได้:** ถ้าเป็น contract ที่ไม่มี `receive()` message จะ revert ด้วย `CreditFailed` และค้างที่ executor (ต้อง retry หลังแก้ หรือใช้ `lzReceive` ไปยัง address ใหม่ไม่ได้)
- **Supply invariant (ใช้แทน totalSupply ของเชน เพราะเชน mint เพิ่มเรื่อยๆ):**
  - `native balance ของ PotatoNativeAdapter บน potato` ≥ `PotatoOFT.totalSupply() บน anvil` เสมอ
  - จะเท่ากันพอดีเมื่อไม่มี message ค้างระหว่างทาง ถ้าน้อยกว่า = มีการ mint เกินของที่ lock อยู่ (เหตุร้ายแรง)
- Uniswap pair และ Morpho market บน potato ยังใช้ WPOTATO ได้ตามเดิม เพราะเป็นเหรียญเดียวกัน
