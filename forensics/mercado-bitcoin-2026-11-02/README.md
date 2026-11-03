# Forensics: Mercado Bitcoin hot-wallet drain, 2026-11-02 (runbook topic 18)

Read-only reconstruction from public reporting + live mainnet checks. No keys, nothing sent.
Companion to `../binance-2026-10-29/` — the two incidents are deliberately contrasted in the workshop.

> Attribution and the exact entry point are **unconfirmed**. Addresses below are attributed by
> on-chain behaviour (Arkham/Bitquery) and verified live with `check.sh`. Loss figures are
> preliminary and differ by source (~$46M–$49M across 10–17 chains).

## What happened
- **2026-11-02 ~01:22 UTC** a 0.0001 ETH test tx leaves the exchange's Base hot wallet.
- **~06:24–06:50 UTC** hot wallets on ~10 chains are emptied within ~25 minutes. On Ethereum tokens
  are sent **one at a time** (2,852 ETH, then USDT/USDC, then 185+ ERC-20s). 104.43 BTC swept at 06:41.
- **from ~12:27 UTC** customer **deposit addresses** start signing transfers of their full balances
  to the attacker — **36,042 on Ethereum alone**, continuing hours after the exchange said it was contained.
- Security firms: carried out with **ordinary signed transfers, not a smart-contract exploit**.
- Mercado Bitcoin pledged to cover user losses (~$40M). Tether + Circle + Chainalysis froze ~$9–11M.

## How (most likely mechanism — inferred, not confirmed)
The attacker could sign for **both** the hot wallets **and every customer deposit address** across
many chains. That blast radius points at a **single compromised signing authority** — a shared
master seed (HD wallet) or a signing service/HSM — not 36,042 individually stolen keys. One secret,
signing power over all derived addresses. The exchange has not disclosed the entry point.

## Key addresses (verified live — see `check.sh`, block ~26,337,586)
| role | address | live state |
|---|---|---|
| Victim — MB ETH hot wallet | `0x5cc7787778b4d20a947dcc53b41f593cfd27d548` | EOA, nonce 16192, drained to ~0.009 ETH |
| Hacker main (EVM, all chains) | `0xe485e7a70b1131216cb47ca4555c4bbb2c742478` | EOA, nonce 50, **3,059,424 USDT frozen (isBlackListed=true)** |
| Intermediate | `0x8419e7824e785c4ac8d9d94a0093c437ab1ff320` | EOA, nonce 3, passed ~2,800 ETH through |
| ETH parking | `0x59a919e8d0582ce62c8de9431b3ebc6fa121731e` | EOA, **nonce 0, 2,979 ETH sitting** (never sent) |
| ETH parking | `0x071f8366375fdd21423bb23ae19e4b91f03f9270` | EOA, nonce 0, ~670 ETH |
| ETH from Tron/Bridgers | `0x4d5f3758938df94a76bfd19652f118ccd7a72c9d` | EOA, nonce 0, ~761 ETH |

Other chains (attributed): BTC `19qGpsHvzh1t6pVi526XNNkh6hW6prDZp` (106.07 BTC still sitting),
Solana `3YX6WHncP1Ra4AotE9YLawFt4nPmxyux288FWXkEW97J`, Tron `TEX3HuDRHRa3tnYpy96M4UfSx62VhDyA5L`,
Avalanche collector `0x71ddbdd9b865d74b3c21068d71b3a11e110db728`.

## Fund flow (ETH leg)
```
MB hot 0x5cc7… ──(06:24–06:48, one tx per token)──► hacker main 0xe485…
0xe485… ──~2,800 ETH──► 0x8419… ──$6.7M ETH (12:07)──► park 0x59a9…  (2,979 ETH, parked, nonce 0)
new wallets + 0xe485… ──3,649 ETH overnight──► 0x59a9… and 0x071f…
Tron 1.71M TRX ─via Bridgers─► 181 ETH ─► 0x4d5f…    | Solana via Mayan/Chainflip ─► ~$1.15M ETH
```
Stablecoins that stayed as USDT were partly **frozen** (0xe485… USDT isBlackListed). ETH was
consolidated into fresh **nonce-0** wallets and left unfrozen — nobody can freeze ETH.

## Contrast with Binance 14 (2026-10-29)
| | Binance 14 | Mercado Bitcoin |
|---|---|---|
| Mechanism | **EIP-7702** delegation → attacker **sweeper contract** runs as the wallet | **plain signed transfers**, no contract |
| Victim on-chain | wallet gets code `0xef0100‖sweeper` | victim stays a bare **EOA** (code length 0) |
| Scope | the hot wallets whose owners signed 7702 auths | hot wallets **+ 36,042 deposit addresses**, **10+ chains** |
| Root cause | authorizations signed (signing layer let a type-4 auth through) | **one signing authority compromised** (shared seed / signer) |
| "Stop the bleeding" | revoke 7702 (226 min late) + issuer freeze | issuer freeze only; no delegation to revoke |
| Same lesson | stablecoins freezable, ETH not → attacker converts/parks ETH fast | identical: USDT frozen at 0xe485…, ETH parked unfrozen |

## Files
- `check.sh` — live re-verification of the table above (`RPC=… ./check.sh`).
- Lab model: `../../lz-potato/test/MercadoDepositSweep.t.sol` — one seed drains N deposit EOAs with
  plain transfers (no 7702), then issuer freezes the USDT collector but not the parked ETH.

## Sources
- Arkham — <https://info.arkm.com/research/mercado-bitcoin-hack-trace-the-46m-stolen-on-chain>
- Bitquery — <https://bitquery.io/investigations/mercado-bitcoin-hack>
- CoinDesk — <https://www.coindesk.com/business/2026/11/03/mercado-bitcoin-pledges-to-cover-all-user-losses-after-near-usd40-million-hack>
