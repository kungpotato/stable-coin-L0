# ADR 0003: bridge USDC (home anvil) และ control ของ stablecoin

- สถานะ: ตัดสินใจแล้ว (2026-10-15, workshop topic 14)
- ผู้ตัดสินใจ: Kittisak
- ต่อจาก: [ADR 0001](0001-counterpart-chain-and-home-chains.md) (USDC home = anvil, potato = OFT)

## บริบท

- **USDC ตัวจริงอยู่บน anvil:** ใช้ ERC-20 ของ issuer และ lock ด้วย `OFTAdapter` ส่วนบน potato ใช้ `OFT`
- **potato มี `MockUSDC` อยู่แล้ว:** ใช้กับ faucet, Uniswap pair และ Morpho market
- **ทำ MockUSDC ให้เป็นตัว bridge ไม่ได้:** มีแค่ `mint` ของ owner แต่ไม่มี `burn` จึงใช้ `MintBurnOFTAdapter` ไม่ได้ และถ้าใช้จะทำให้ faucet mint เหรียญที่ไม่มีหลักประกันมาปน

## การตัดสินใจ

| เรื่อง | ค่า |
|---|---|
| MockUSDC บน potato | **เก็บไว้ตามเดิม** ถือเป็นของทดสอบเท่านั้น ใช้กับ faucet/DEX/lending เดิม |
| USDC ตัวจริง (anvil) | `IssuerUSDC` "USD Coin"/"USDC", 6 decimals, owner (issuer) mint/burn |
| lock บน anvil | `UsdcAdapter` = `OFTAdapter` + rate limit + pause |
| USDC บน potato | `UsdcOFT` "USD Coin (LayerZero)"/**"USDC.lz"**, 6 decimals + rate limit + pause |
| rate limit (lab) | 10,000 USDC ต่อ ~~60 วินาที~~ **ชั่วโมง** ต่อเชนปลายทาง ทั้งสองฝั่ง (เปลี่ยนเมื่อ 2026-10-19 ให้ตรงกับ inbound cap ของ [ADR 0006](0006-inbound-mint-cap.md), ดู [ADR 0007](0007-potato-pause-and-rate-limit.md)) |
| pause | owner หยุดได้ทั้งขาส่งและขารับ |

## เหตุผล

- **เก็บทั้งคู่:** ไม่แตะ DeFi, web และ indexer เดิมใน topic นี้ จะย้ายทีหลังก็ได้
- **ใช้ symbol `USDC.lz`:** ให้คนแยกออกจาก MockUSDC ใน wallet และ explorer ได้ทันที
- **Rate limit:** จำกัดความเสียหายต่อช่วงเวลา ถ้า DVN, executor หรือ key ถูกเจาะ จะเสียได้ไม่เกิน limit ต่อ window
- **Pause:** เป็นสวิตช์หยุดฉุกเฉินระหว่างสอบสวนเหตุการณ์
- **ไม่ใส่ blacklist ใน OFT:** ในโลกจริง issuer (เช่น Circle) blacklist ที่ token บน home chain เอง ส่วน OFT บนเชนอื่นตาม policy นี้ภายหลังได้ (ยังไม่ทำใน lab)

## ผลที่ตามมา

- **potato มี USDC 2 ตัว:** `MockUSDC` (symbol USDC, ไม่มีหลักประกัน) กับ `UsdcOFT` (USDC.lz, มีหลักประกันบน anvil) ราคาและ pool แยกกัน
- **Supply invariant:** `IssuerUSDC.balanceOf(UsdcAdapter)` บน anvil ≥ `UsdcOFT.totalSupply()` บน potato
- **Pause ขารับ:** message ที่ส่งมาแล้วจะค้างที่ executor จน unpause และ check-supply จะขึ้น ⏳ ในช่วงนั้น โดยไม่เสียเงิน
- **Rate limit คิดเฉพาะขาออก:** ขาเข้า (`_inflow`) จะคืนโควตาให้เส้นทางเดียวกัน ถ้าโอนเกิน limit จะ revert `RateLimitExceeded` ตอนส่ง ไม่ใช่ตอนรับ
