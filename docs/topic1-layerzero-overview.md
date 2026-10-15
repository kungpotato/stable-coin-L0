# Topic 1: LayerZero คือ messaging layer ไม่ใช่ bridge

เอกสารนี้อธิบายด้วยสิ่งที่เราสร้างและวัดเองใน lab ตัวเลขทั้งหมดรันซ้ำได้ (runbook topic 1)

## 1. LayerZero ส่ง "ข้อความ" ไม่ได้ถือ "เงิน"

| ใครถือเงิน (วัดจากเชน 2026-10-15) | ยอด |
|---|---|
| EndpointV2 บน potato (ของ LayerZero) | **0 POTATO** |
| EndpointV2 บน anvil (ของ LayerZero) | **0 USDC** |
| `PotatoNativeAdapter` (OApp ของเรา) | 68.88 POTATO |
| `UsdcAdapter` v2 / v1 (OApp ของเรา) | 852.5 / 20 USDC |

- **"bridge" ของเราคือ OApp ที่เราเขียนเอง:** `OFTAdapter`, `OFT` และ `NativeOFTAdapter` เป็นคน lock, mint และ burn ส่วน LayerZero แค่นำข้อความ "lock แล้ว X, ให้ mint X ให้ Y" ไปส่ง
- **ผลที่ตามมา:** ความปลอดภัยของเงินคือ **ความรับผิดชอบของเรา** ทั้ง code ของ OApp, การเลือก DVN, การตั้ง config และ control

## 2. ใครทำอะไรได้บ้าง (และทำร้ายเราได้แค่ไหน)

| ผู้เล่น | หน้าที่ | ถ้าเป็นฝ่ายร้าย ทำอะไรได้ | ใน lab |
|---|---|---|---|
| **Endpoint** (immutable) | รับ/ส่ง message, เก็บ nonce, เรียก `lzReceive` | ไม่มีใครแก้ code ได้ | topic 9 |
| **เจ้าของ endpoint** (production คือ LayerZero Labs) | ตั้ง **default** library และ config | เปลี่ยน default ได้ จึง**มีผลกับ OApp ที่ใช้ default** แต่ย้ายเงินของ OApp ไม่ได้ | topic 11 |
| **DVN** (ครบ quorum ตามที่ OApp เลือก) | ยืนยันว่า packet มีจริง | **ปลอม message ได้: mint ไม่จำกัดและดูด lockbox** | drill topic 3 |
| **Executor** | ส่งของ (commit + `lzReceive`) | ปลอมไม่ได้ ทำได้แค่ส่งช้าหรือไม่ส่ง (เรื่อง liveness) | topic 12 |
| **เจ้าของ OApp** (เรา) | peers, DVN config, pause, rate limit, blacklist | ทุกอย่างของแอป จึงต้องเป็น multisig | topic 13–14, 6 |

**ข้อค้นพบระหว่างทำ topic นี้:** OApp ของเราตั้ง DVN เองแล้ว แต่ **send/receive library ยังใช้ default ของ endpoint** ถ้าเจ้าของ endpoint เปลี่ยน default library ข้อความของเราจะไปวิ่งผ่าน library ใหม่ ใน production ควรระบุ library ตายตัวด้วย `setSendLibrary`/`setReceiveLibrary` (ไปทำต่อใน topic 8 ร่วมกับ DevTools)

## 3. bridge hack ในโลกจริง เทียบกับสิ่งที่เราสร้าง

| เหตุการณ์ | เกิดอะไรขึ้น | ประเภทของปัญหา | ใน LayerZero/lab ของเรา |
|---|---|---|---|
| **Ronin** (มี.ค. 2022, ~$625M) | bridge ต้องใช้ลายเซ็น 5 ใน 9 ผู้โจมตี phishing ได้ key 4 ดอกของบริษัทเดียวกัน และได้ดอกที่ 5 จากสิทธิ์ของ Axie DAO ที่ลืมถอน โดนดูด 173,600 ETH + 25.5M USDC และกว่าจะรู้ตัวก็ผ่านไป 6 วัน | **key ของผู้ยืนยันหลุด + ผู้ยืนยันไม่อิสระจริง** | ตรงกับ drill topic 3 (key ของ DVN-A หลุด) จะป้องกันได้ต้องมี DVN **หลายรายที่อิสระจริง** (ไม่ใช่แค่หลาย key ในองค์กรเดียว), **rate limit** (หลังเหตุการณ์ Ronin เพิ่ม daily limit), **alert** ที่เร็ว (`check-supply`/`audit`) |
| **Wormhole** (ก.พ. 2022, ~$320M) | โปรแกรมบน Solana ใช้ฟังก์ชันที่ไม่ตรวจว่า account ที่ใช้ยืนยันลายเซ็นเป็นของจริง ผู้โจมตีจึงปลอม message ให้ mint 120,000 wETH ทั้งที่ไม่มี ETH ถูก lock | **bug ในโค้ดของผู้ยืนยัน** ทำให้ message ปลอมผ่าน | ผลเหมือน forged mint ใน topic 3 การใช้ DVN หลายรายที่ใช้ **โค้ดคนละชุด** ช่วยลดผลจาก bug ตัวเดียว ส่วน invariant (minted > locked) จับได้ทันที และ rate limit จำกัดยอดเสียหาย |
| **Nomad** (ส.ค. 2022, ~$190M) | upgrade ตามปกติตั้ง trusted root เป็น `0x00` ซึ่งเป็นค่าเดียวกับ message ที่ยังไม่ถูกพิสูจน์ ผลคือ**ทุก message ผ่าน** คนก๊อป tx ของผู้โจมตีไปทำตามกันเป็นร้อย address | **config/upgrade ผิดพลาด** | endpoint ของ LayerZero immutable แต่ **config ของ OApp ผิดได้** ซึ่งเราเห็นแล้วทั้ง DEMOWEAK ที่ใช้ default แล้วโดนเจาะ, config ฝั่งส่งกับฝั่งรับไม่ตรงกันจน message ค้าง (3.9) และ DEMOSAFE ที่ยังเชื่อ DVN ที่ key หลุด (`check-security` จับได้) |

**ข้อสรุปร่วม:** ทั้ง 3 เหตุการณ์จบที่การ mint หรือถอน**โดยไม่มีของจริงรองรับ** สิ่งที่ช่วยได้ทุกกรณีคือ:
1. ผู้ยืนยันหลายรายที่**อิสระ**ต่อกัน
2. เพดานความเสียหายต่อช่วงเวลา (rate limit)
3. ตรวจ invariant แบบ real-time
4. สวิตช์หยุดฉุกเฉิน (pause หรือ BlockedMessageLib)

## 4. คำถามทบทวน (ตอบจาก lab ได้)

1. ถ้า LayerZero Labs (เจ้าของ endpoint) ถูกเจาะ เงินใน `UsdcAdapter` จะถูกย้ายออกได้ไหม แล้ว OApp แบบไหนบ้างที่ได้รับผลกระทบ (คำใบ้: ตอบได้จากข้อ 2 และข้อค้นพบเรื่อง default library)
2. Executor ที่ถูกเจาะทำอะไรได้ และทำอะไรไม่ได้ (เทียบกับ topic 12.6 ที่ worker ปิดอยู่)
3. ทำไม DEMOSAFE ถึงปลอดภัยใน drill 3.8 แต่ยังถูก `check-security` จับว่าเสี่ยงหลังจาก A หลุด
4. Ronin ใช้ 5 ใน 9 ทำไมถึงไม่พอ แล้ว B+C ของเราต่างจากนั้นตรงไหน และใน production ต้องทำอะไรเพิ่ม
5. ถ้ามีคนปลอม message แต่ supply รวมยังเท่าเดิม (ปลอมแล้วเผาทิ้ง) `check-supply` จะจับได้ไหม เครื่องมือไหนจับได้

## แหล่งอ้างอิง

- Ronin: [Halborn](https://halborn.com/explained-the-ronin-hack-march-2022/), [ForkLog (postmortem ของทีม)](https://forklog.com/en/ronin-sidechain-developers-reveal-further-details-of-625-million-hack/)
- Wormhole: [CertiK](https://www.certik.com/blog/wormhole-bridge-exploit-incident-analysis), [Ackee](https://ackee.xyz/blog/2022-solana-hacks-explained-wormhole/)
- Nomad: [Immunefi](https://immunefi.com/blog/bug-fix-reviews/hack-analysis-nomad-bridge-august-2022/), [Coinbase](https://www.coinbase.com/blog/nomad-bridge-incident-analysis)
- เปรียบเทียบทั้ง 3: [Spark research](https://www.spark.money/research/stablecoin-bridge-hack-postmortem-lessons)
