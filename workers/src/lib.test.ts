import { test } from "node:test";
import assert from "node:assert/strict";
import { decodeAbiParameters, keccak256, slice } from "viem";
import { decodePacket } from "./lib.ts";

// Real PacketSent from topic 11: potato Ping -> anvil Ping, nonce 1
const ENCODED =
  "0x01000000000000000100009f030000000000000000000000008faeb9fd8cb28ec6ec1c774263e5d41c106a3a0b00009d920000000000000000000000009a676e781a523b5d0c0e43731313a708cb607508b725212cee1ef04b08024be84507ef5ff5600b3b670e155535b6863b5bb78def0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002268656c6c6f20706f7461746f202d3e20616e76696c20402031373932303231303330000000000000000000000000000000000000000000000000000000000000";

test("decodePacket reads PacketV1 fields", () => {
  const p = decodePacket(ENCODED);
  assert.equal(p.nonce, 1n);
  assert.equal(p.srcEid, 40707);
  assert.equal(p.dstEid, 40338);
  assert.equal(p.sender, "0x0000000000000000000000008faeb9fd8cb28ec6ec1c774263e5d41c106a3a0b");
  assert.equal(p.receiver, "0x9A676e781A523b5d0C0e43731313A708CB607508");
  assert.equal(p.header, slice(ENCODED, 0, 81));
  assert.equal(p.headerHash, keccak256(p.header));
  // computed independently with: cast keccak 0x<bytes 81..> (guid ++ message)
  assert.equal(p.payloadHash, "0xf5e4257ace7cdaf4dbd37f76d4402015f3c672e6020f590e66d66a5829d00d42");
  assert.deepEqual(decodeAbiParameters([{ type: "string" }], p.message), ["hello potato -> anvil @ 1792021030"]);
});
