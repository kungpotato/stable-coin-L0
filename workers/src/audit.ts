// Path audit CLI (topic 3/8): compare every nonce's payload hash on the source (PacketSent) with what the
// destination accepted (PacketVerified). Nonce counts alone miss a forgery once real traffic catches up with the
// forged nonce; payload hashes don't. Statuses: see pathaudit.ts.
// Run: npm run audit -- <deployments key, e.g. DEMOWEAK>      exit 0 clean / 1 in flight / 2 FORGED or POISONED
import { loadChains, errMsg } from "./lib.ts";
import { auditPath } from "./pathaudit.ts";

const asset = process.argv[2];
if (!asset) {
  console.error("usage: npm run audit -- <asset deployments key>");
  process.exit(3);
}
const chains = loadChains().filter((c) => c.deployments[asset]);
if (chains.length < 2) {
  console.error(`${asset} is not deployed on two chains`);
  process.exit(3);
}
let worst = 0;
try {
  for (const src of chains) {
    for (const dst of chains) {
      if (src === dst) continue;
      const rows = await auditPath(asset, src, dst);
      const bad = rows.filter((r) => r.status !== "OK");
      console.log(`${asset} ${src.name}->${dst.name}: ${rows.length} nonce(s), ${rows.length - bad.length} OK` +
        (bad.length ? ` | ${bad.map((r) => `nonce ${r.nonce} ${r.status}`).join(", ")}` : ""));
      for (const r of bad) worst = Math.max(worst, r.status === "IN_FLIGHT" ? 1 : 2);
    }
  }
} catch (e) {
  console.error(`audit failed: ${errMsg(e)}`);
  process.exit(3);
}
process.exit(worst);
