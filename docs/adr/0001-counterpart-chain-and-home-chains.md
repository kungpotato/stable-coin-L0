# ADR 0001: เชนคู่ และ home chain ของแต่ละ asset

- สถานะ: ตัดสินใจแล้ว (2026-10-15, workshop topic 10)
- ผู้ตัดสินใจ: Kittisak

## บริบท

potato-chain (EVM บน cosmos/evm) ต้อง bridge native coin (POTATO) และ stablecoin (USDC) ผ่าน LayerZero V2 แบบ self-host
topic 9 ยืนยันแล้วว่า LayerZero V2 ทำงานบน potato ได้ ตอนนี้ต้องเลือกเชนคู่ และกำหนดว่า token ตัวจริงของแต่ละ asset อยู่เชนไหน

## การตัดสินใจ

| เรื่อง | ค่า |
|---|---|
| เชนคู่ | anvil local, chainId `31338`, รันด้วย `potato-localnet/anvil-home.sh` (เก็บ state ข้าม restart) |
| EID | potato = `40707`, anvil = `40338` (เราตั้งเอง ไม่อยู่ใน registry ของ LayerZero) |
| POTATO home | potato (native coin) ส่วนจะใช้ NativeOFTAdapter หรือครอบ WPOTATO ตัดสินใน topic 13 |
| USDC home | **anvil** เป็น ERC-20 ธรรมดาที่ issuer คุม + `OFTAdapter` (lock/unlock) |
| USDC บน potato | `OFT` ตัวใหม่ (mint/burn) |
| confirmations | 1 ทั้งสองทาง |

## เหตุผล

- **anvil:** เร็วและฟรี script จาก topic 9 ใช้ได้เลย ส่วนความเสี่ยงที่ state หายแก้ด้วย `--state`
- **USDC home อยู่เชนคู่:** จำลองโลกจริงที่ USDC ออกโดย issuer บนเชนอื่น (เช่น Circle บน Ethereum) แล้ว potato เป็นแค่ spoke
- **ใช้ OFTAdapter บน home แทนการทำ USDC เป็น OFT ตรงๆ:** ในโลกจริงเราแก้ contract ของ issuer ไม่ได้ จึงต้องครอบจากข้างนอก
- **confirmations = 1:** potato มี finality ทันที (CometBFT) ส่วน anvil เป็น local ไม่มี reorg
  - ถ้าเปลี่ยนเชนคู่เป็น Ethereum จริง ต้องใช้ค่าที่สูงกว่านี้มาก หรือรอ finalized block

## ผลที่ตามมา

- **potato จะมี USDC สองตัว:** `MockUSDC` เดิมที่อยู่ใน Uniswap pair, Morpho market และ faucet กับ USDC (OFT) ที่ bridge มา
  - ต้องตัดสินใน topic 14 ว่าจะย้าย pool/market ไปใช้ OFT หรือเลิกใช้ MockUSDC
- **Supply invariant ของ USDC:** ยอดที่ lock อยู่ใน OFTAdapter บน anvil ต้องเท่ากับ `totalSupply` ของ USDC OFT บน potato เสมอ (topic 14 ต้องมีวิธีตรวจ)
- **Decimals:** USDC มี 6 decimals เท่ากับ shared decimals จึงไม่มี dust ส่วน POTATO มี 18 decimals จะถูกตัดเหลือ 6 ตอนข้ามเชน (topic 13)
- **anvil คือ single point of failure ของ USDC:** ลบไฟล์ `anvil-home-state.json` เท่ากับ USDC หายทั้งระบบ ห้ามลบระหว่าง workshop
- ทั้งสองฝั่งเป็น EVM แปลง address เป็น `bytes32` ได้ตรงๆ

## ที่มาของค่า

ค่าทั้งหมดอยู่ใน `lz-potato/config/topology.json` และตรวจกับเชนจริงด้วย `lz-potato/check-topology.sh`
