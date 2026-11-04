# After-hack response & monitoring runbook (workshop topic 19)

Built from the two drains traced in this repo: Binance 14 (`../binance-2026-10-29/`, EIP-7702) and
Mercado Bitcoin (`../mercado-bitcoin-2026-11-02/`, one stolen signing authority). Both emptied hot
wallets in **~25 minutes** while the human response took **hours**. Every control below exists to
close that gap.

> One hard fact frames everything: **stablecoins (USDT/USDC) can be frozen after the fact; ETH and
> native coins cannot.** So the attacker's whole game is convert-to-ETH-and-park fast, and our whole
> game is detect-and-contain faster than they can convert.

## Monitoring — signals to alert on (real time)
| Signal | What it catches | Seen in |
|---|---|---|
| Hot EOA gains code `0xef0100‖addr` | EIP-7702 delegation to a sweeper | Binance 14 |
| Outflow > N× baseline per minute | any mass drain | both |
| Many deposit addresses sign in one window | one compromised seed/signer | Mercado |
| Tiny "test" tx (e.g. 0.0001) then a burst | attacker dry-run before the sweep | Mercado |
| Transfer into a fresh **nonce-0** wallet | ETH being parked for cash-out | both |

Detection logic is modelled in `../../lz-potato/test/HotWalletMonitor.t.sol`
(`_delegatedTo()` flags the 7702 designator; outflow-vs-baseline signal).

## Containment — don't wait for a human
- **Auto circuit breaker**: cap outflow per rolling window; the over-cap withdrawal latches the
  breaker and sends nothing, so a stolen operator key gets **one window at most**, not the vault.
- **Guardian pause**: a T+0 kill switch on a **separate key** — a compromised operator can neither
  withdraw nor lift the pause.

Both are modelled in `../../lz-potato/src/lab/HotWalletVault.sol`.

## Timeline runbook
| When | Action | Why |
|---|---|---|
| **T+0** | breaker already tripped / guardian `pause()`; rotate operator key; revoke 7702 auth if any | stop the bleeding without waiting |
| **T+5** | contact Tether + Circle + Chainalysis to blacklist the collector address(es) | freezes the USDT/USDC that already left |
| **T+15** | stand up watchers on each hop; notify destination CEXs to flag incoming | catch the ETH before it cashes out |
| **T+60** | public status; preserve logs/evidence; snapshot balances | trust + forensics |
| **T+days** | reimburse users; post-mortem; close the entry point | Binance & Mercado both pledged user cover |

## The gap, in numbers
Binance revoked the 7702 delegation **226 minutes** after the first sweep. The breaker + per-window
cap would have bounded the loss to one window regardless of how late the human arrived — that is the
entire point of moving the first response on-chain.

## Files
- `../../lz-potato/src/lab/HotWalletVault.sol` — circuit-breaker + guardian-pause vault.
- `../../lz-potato/test/HotWalletMonitor.t.sol` — detection signals + containment tests (7/7).
