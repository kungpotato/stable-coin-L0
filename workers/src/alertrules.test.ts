import { test } from "node:test";
import assert from "node:assert/strict";
import { AlertBook, supplyBroken, forgedVerification, isStuck, formatAlert } from "./alertrules.ts";

test("AlertBook raises once per condition and resolves once", () => {
  const b = new AlertBook();
  assert.ok(b.raise("SUPPLY:X", "critical", "broken"));
  assert.equal(b.raise("SUPPLY:X", "critical", "still broken"), undefined); // no repeat while it holds
  assert.ok(b.resolve("SUPPLY:X", "ok again"));
  assert.equal(b.resolve("SUPPLY:X", "ok again"), undefined); // nothing to resolve
  assert.ok(b.raise("SUPPLY:X", "critical", "broken again")); // a new occurrence alerts again
});

test("events always pass", () => {
  const b = new AlertBook();
  assert.equal(b.event("PAUSED:a", "info", "x").state, "event");
  assert.equal(b.event("PAUSED:a", "info", "x").state, "event");
});

test("supply: minted above what backs it is broken, in flight is not", () => {
  assert.equal(supplyBroken(100n, 0n, 100n), false);
  assert.equal(supplyBroken(105n, 0n, 100n), false); // locked first, minted later: in flight
  assert.equal(supplyBroken(100n, 0n, 101n), true);
  assert.equal(supplyBroken(100n, 10n, 95n), true); // quarantined at home does not back anything
});

test("forged verification: unknown or different payload", () => {
  assert.equal(forgedVerification("0xAB", "0xab"), false);
  assert.equal(forgedVerification(undefined, "0xab"), true);
  assert.equal(forgedVerification("0xab", "0xcd"), true);
});

test("stuck after the threshold", () => {
  assert.equal(isStuck(0, 119_999, 120), false);
  assert.equal(isStuck(0, 120_000, 120), true);
});

test("format", () => {
  const b = new AlertBook();
  assert.match(formatAlert(b.raise("X", "critical", "m")!), /^🚨 CRITICAL X: m$/);
  assert.match(formatAlert(b.resolve("X", "ok")!), /^✅ RESOLVED X: ok$/);
});
