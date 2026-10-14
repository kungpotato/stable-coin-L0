# lz-potato — LayerZero V2 self-hosted lab

Workshop topic 9: does LayerZero V2 run on potato-chain?

## What's here

| Path | What |
|---|---|
| `src/lab/LabDVN.sol` | Zero-fee DVN. Its owner (off-chain signer) attests packets via `verify()` |
| `src/lab/LabExecutor.sol` | Zero-fee executor. Satisfies the send-side fee interface; delivery is off-chain |
| `src/lab/PingOApp.sol` | Smallest OApp: `ping(dstEid, msg)` / stores `lastMessage` |
| `script/DeployLab.s.sol` | EndpointV2 + SendUln302 + ReceiveUln302 + DVN + Executor, default config, 2 PingOApps (loopback) |
| `script/Relay.s.sol` | Manual DVN + executor: verify → commitVerification → lzReceive |
| `lab-loopback.sh` | Runs everything end to end against one RPC |
| `deployments/<chainId>.json` | Addresses written by the deploy |

## Run

```bash
npm install --legacy-peer-deps
./lab-loopback.sh <rpc-url> <private-key> [eid]
```

- potato localnet (ports remapped, see `../potato-localnet/ports-override.yml`): `http://localhost:18545`, dev0 key from `potato-chain/scripts/lib.sh`
- scratch anvil: `anvil --port 28545 --chain-id 31338`, anvil key #0

## Notes

- LayerZero protocol + messagelib are `LZBL-1.2` licensed and built on OpenZeppelin 4.x; OApp/OFT are MIT on OpenZeppelin 5.x. `remappings.txt` scopes OZ v4 to the LayerZero packages.
- EIDs are ours (not LayerZero's registry): potato = `40707`.
- Log scans start from the deploy block, never block 0 (cosmos/evm `eth_getLogs` bug, see `potato-chain/docs/known-issues.md`).

## Topic 9 result (2026-10-15)

LayerZero V2 runs on potato-chain unmodified. Loopback ping A → B delivered on the first try.

| Check | potato-chain (707070) | anvil (31338) |
|---|---|---|
| Compile (solc 0.8.22, evm `prague`) | ✅ | ✅ |
| Deploy EndpointV2 / SendUln302 / ReceiveUln302 | ✅ | ✅ |
| `PacketSent` → `PacketVerified` → `PacketDelivered` | ✅ 1 / 1 / 1 | ✅ |
| Relay gas: verify / commit / lzReceive | 55,615 / 79,357 / 173,989 | 55,627 / 79,369 / 174,001 |
| Block time | ~1.25 s, instant finality (CometBFT) | — |

Carry-overs for later topics:
- **Confirmations = 1 is safe** on potato (no reorgs). The counterpart chain sets its own value.
- **Workers (topic 12)**: scan logs from the deploy block (getLogs `fromBlock: 0` bug); if written with viem + local account, pass explicit `gas` (`eth_fillTransaction` bug).
- **License**: protocol/messagelib are LZBL-1.2. Fine for the lab; check before any production use.
