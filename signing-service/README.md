# Signing service / API — the third custody model (workshop topic 20)

A tiny HTTP service that signs on behalf of **anvil account #0**
(`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`) over `curl`. It completes the custody trilogy the
workshop traced from real 2026 hacks:

| model | who can sign everything | broke in |
|---|---|---|
| one shared **seed** (BIP-32 HD) | whoever steals the seed file | Mercado Bitcoin (topic 18) |
| **EOA** holding funds | whoever steals/tricks the key into a 7702 auth | Binance 14 (topic 17) |
| **signing service / API** (this) | **whoever can reach the endpoint** | this lab |

The lesson: moving the key behind an API is the "operational" choice exchanges make (one place to
rotate keys, log, apply policy) — but it concentrates signing power at the endpoint. Compromise the
API (or its auth) and you get a signature for anything the key controls, the same blast radius as a
stolen seed, just at a different layer. This is why Fireblocks-style **MPC + policy (TAP)** exists:
the key is never whole on any one box, and a policy engine, not the raw endpoint, decides what signs.

> The private key here is the **public** Foundry test key for account #0 — safe for a lab, never a
> real key. There is no auth on the endpoint **on purpose**, to make the single-point-of-failure
> obvious. Bind only to localhost.

## Run it (3 terminals)
```bash
# 1) local node on the Prague hardfork (ships EIP-7702), needed so sign-auth can read nonce + chain
./start-anvil.sh

# 2) the signing service (shells out to `cast wallet`, no python deps)
python3 server.py            # listens on 127.0.0.1:8555

# 3) ask it for signatures
./demo.sh                    # or the curls below
```

## Make a SIG of account #0 over curl
```bash
# whose key does it hold?
curl -s http://127.0.0.1:8555/health

# personal_sign a message
curl -s -X POST http://127.0.0.1:8555/sign -H 'content-type: application/json' \
  -d '{"message":"transfer 1000 USDT to treasury"}'

# sign a raw 32-byte hash (no eth prefix)
curl -s -X POST http://127.0.0.1:8555/sign -H 'content-type: application/json' \
  -d '{"message":"0x00..01","no_hash":true}'

# EIP-7702 authorization: delegate account #0's EOA to a sweeper (the Binance attack shape)
curl -s -X POST http://127.0.0.1:8555/sign-auth -H 'content-type: application/json' \
  -d '{"delegate":"0x00000000000000000000000000000000DeaDBeef"}'
```

The `sign-auth` response is the RLP authorization tuple
(`chain_id, address, nonce, y_parity, r, s`) — submit it with `cast send --auth <authorization>`
and the authority's EOA gains the delegate's code. That is the exact primitive abused in Binance 14.

## Endpoints
| method | path | body | returns |
|---|---|---|---|
| GET | `/health` | — | `{ok, address}` |
| GET | `/address` | — | `{address}` |
| POST | `/sign` | `{message, no_hash?}` | `{address, message, signature}` |
| POST | `/sign-auth` | `{delegate, rpc?}` | `{authority, delegate, authorization}` |

## Env
- `SIGNER_PK` — key to sign with (default: anvil #0 public key).
- `PORT` — service port (default 8555).
- `RPC` — node for `sign-auth` nonce/chain (default `http://127.0.0.1:8545`).

## Files
- `server.py` — the service (stdlib http.server + `cast wallet`).
- `start-anvil.sh` — `anvil --hardfork prague`.
- `demo.sh` — the curl walkthrough above.
