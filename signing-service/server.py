#!/usr/bin/env python3
"""Lab signing service - the THIRD custody model in the workshop.

Chapters 18-19 modelled two custody shapes and how they broke:
  - one shared SEED (BIP-32 HD wallet)  -> Mercado Bitcoin: steal the seed, sign every address.
  - EOA holding funds directly          -> Binance 14: a stolen/tricked key signs a 7702 auth.

This service models the third shape exchanges actually run for "operational" reasons: a
central SIGNING SERVICE / API. The private key never leaves the box; clients ask the API for a
signature over HTTP. It is convenient (one place to rotate keys, log, apply policy) and it is a
single point of failure: whoever can reach this endpoint can get a signature for ANYTHING the key
controls - exactly the "one signing authority compromised" blast radius we traced on-chain.

Key used: anvil default account #0 (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266). Its private key
is PUBLIC and published by Foundry - safe for a lab, NEVER a real key. Set SIGNER_PK to override.

The service shells out to `cast wallet` (Foundry), so it needs no Python crypto deps.

Endpoints (all JSON):
  GET  /health              -> {ok, address}
  GET  /address             -> {address}
  POST /sign    {message, no_hash?}            -> personal_sign (eth-prefixed unless no_hash)
  POST /sign-auth {delegate, rpc?}             -> EIP-7702 authorization delegating the key's
                                                  account to `delegate` (the Binance attack shape)
"""
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# anvil default account #0 - PUBLIC test key, documented by Foundry. Never use a real key here.
SIGNER_PK = os.environ.get(
    "SIGNER_PK", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
)
PORT = int(os.environ.get("PORT", "8555"))
DEFAULT_RPC = os.environ.get("RPC", "http://127.0.0.1:8545")


def cast(*args: str) -> str:
    """Run a `cast` subcommand and return trimmed stdout, raising on failure."""
    out = subprocess.run(
        ["cast", *args], capture_output=True, text=True, timeout=30
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or out.stdout.strip() or "cast failed")
    return out.stdout.strip()


def address() -> str:
    return cast("wallet", "address", "--private-key", SIGNER_PK)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, obj: dict):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length", "0") or "0")
        return json.loads(self.rfile.read(n) or b"{}")

    def log_message(self, fmt, *args):  # quieter logs
        print(f"[signer] {self.command} {self.path} - {fmt % args}")

    def do_GET(self):
        try:
            if self.path == "/health":
                self._send(200, {"ok": True, "address": address()})
            elif self.path == "/address":
                self._send(200, {"address": address()})
            else:
                self._send(404, {"error": "not found"})
        except Exception as e:  # noqa: BLE001 - lab: surface the cast error
            self._send(500, {"error": str(e)})

    def do_POST(self):
        try:
            data = self._body()
            if self.path == "/sign":
                msg = data.get("message")
                if msg is None:
                    return self._send(400, {"error": "message required"})
                args = ["wallet", "sign", "--private-key", SIGNER_PK]
                if data.get("no_hash"):
                    args.append("--no-hash")
                args.append(str(msg))
                sig = cast(*args)
                self._send(200, {"address": address(), "message": msg, "signature": sig})
            elif self.path == "/sign-auth":
                delegate = data.get("delegate")
                if not delegate:
                    return self._send(400, {"error": "delegate address required"})
                rpc = data.get("rpc", DEFAULT_RPC)
                # sign-auth fetches nonce + chain id from the RPC (why we start anvil).
                sig = cast(
                    "wallet", "sign-auth", str(delegate),
                    "--private-key", SIGNER_PK, "--rpc-url", rpc,
                )
                self._send(200, {
                    "authority": address(),
                    "delegate": delegate,
                    "authorization": sig,
                    "note": "EIP-7702 auth: submitting this delegates the authority's EOA to `delegate` - the Binance 14 attack shape.",
                })
            else:
                self._send(404, {"error": "not found"})
        except Exception as e:  # noqa: BLE001
            self._send(500, {"error": str(e)})


if __name__ == "__main__":
    addr = address()
    print(f"[signer] signing service on :{PORT} for {addr}")
    print(f"[signer] RPC for sign-auth: {DEFAULT_RPC}")
    print("[signer] WARNING: anyone who can reach this port can sign for the key. Lab only.")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
