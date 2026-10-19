# ADR 0007: pause และ rate limit ขาออกของ POTATO

- สถานะ: ตัดสินใจแล้ว (2026-10-19) · deploy ใน lab แล้วเป็น POTATO v3 (runbook 13.13–13.14)
- ต่อจาก: [ADR 0002](0002-potato-native-oft-adapter.md), [ADR 0006](0006-inbound-mint-cap.md) · action item ข้อ 4 ของ [postmortem DEMOWEAK](../incidents/2026-10-15-demoweak-forged-mint.md)

## บริบท

- **POTATO ไม่มี pause:** ใน drill ต้องใช้ BlockedMessageLib หยุดแทน และตอนย้าย DVN ต้องรีบเปลี่ยนสองเชนต่อกันโดยหยุด traffic ไม่ได้ (topic 8.13)
- **POTATO ไม่มี rate limit ขาออก:** ถ้า key ของผู้ใช้หรือ owner หลุด ผู้โจมตีส่งออกได้ไม่จำกัดต่อช่วงเวลา
- **control เดิมของ USDC อยู่ใน `StablecoinControls`:** ซึ่งรวม blacklist มาด้วย แต่ POTATO เป็น native coin ของเชนเรา ยังไม่มีเหตุผลให้ blacklist

## การตัดสินใจ

1. **แยก `BridgeControls`** (pause + outbound rate limit + inbound mint cap) ออกจาก `StablecoinControls`
   - `StablecoinControls` = `BridgeControls` + blacklist เท่านั้น ส่วนพฤติกรรมของ USDC ไม่เปลี่ยน (test เดิมผ่านครบ)
   - blacklist เสียบเข้ามาผ่าน hook `_checkSender`, `_mustHold` และ `_checkPayee`
2. **`PotatoNativeAdapter` และ `PotatoOFT` ใช้ `BridgeControls`** ไม่มี blacklist
3. **rate limit ขาออก 1,000 POTATO ต่อชั่วโมงต่อเชนปลายทาง เท่ากับ inbound cap ของอีกฝั่ง:** traffic ที่ไม่เกิน limit จะไม่ถูกกักที่ปลายทาง
4. **pause มีความหมายเดียวกับ USDC:**
   - ขาส่ง revert ทั้ง tx ทำให้ `msg.value` ไม่ถูก lock
   - ขารับให้ message รออยู่ที่ executor และส่งต่อเองหลัง unpause

## ผลที่ตามมา

- **`RateLimiter` ถือว่า path ที่ไม่ได้ตั้ง limit มีเพดานเป็น 0:**
  - leg ที่ deploy ใหม่จะส่งไม่ได้เลยจนกว่าจะตั้ง limit
  - `DeployPotatoBridge` ต้องรันด้วย `CONTROLS=true` ทุกครั้ง
  - ถ้าเพิ่มเชนใหม่ต้องตั้ง limit ให้ path นั้นด้วย
- **ใช้หลักเดียวกันกับ USDC แล้ว:** เดิม USDC ใช้ outbound 10,000/60 วินาที แต่ inbound cap 10,000/ชั่วโมง ทำให้ traffic ที่ถูกต้องแต่สูงไปถูกกักที่ปลายทาง (เหมือน step 6.13) ตอนนี้ outbound เปลี่ยนเป็น 10,000/ชั่วโมงแล้วโดยไม่ต้อง deploy ใหม่ (runbook 14.10) ส่งเกินจะถูกปฏิเสธตั้งแต่ต้นทาง
- **deploy แล้วเป็น POTATO v3:** พิสูจน์บนเชนแล้วว่า rate limit revert ตอนส่งโดยไม่ lock เงิน และ pause หยุดทั้งขาส่งและขารับโดย message ไม่หาย ปิด action item ข้อ 4 ของ postmortem ได้
