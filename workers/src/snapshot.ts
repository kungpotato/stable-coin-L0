// Incident recovery (topic 8 drill): who on a compromised OFT is owed what.
// Eligible = tokens that arrived through messages the home chain really sent (pathaudit OK), minus what the
// holder bridged back out, capped at the current balance. Forged mints count for nothing, so the attacker's
// balance is excluded no matter how it was moved around.
// Run: npm run snapshot -- <old deployments key, e.g. DEMOWEAK_V1> <home chain> <oft chain> [decimals=18]
import { decodeEventLog, formatUnits, getAddress, parseAbi, parseAbiItem, slice, type Address, type Log } from "viem";
import { loadChains, errMsg } from "./lib.ts";
import { auditPath } from "./pathaudit.ts";

const [key, homeName, oftName, decArg] = process.argv.slice(2);
if (!key || !homeName || !oftName) {
  console.error("usage: npm run snapshot -- <deployments key> <home chain> <oft chain> [decimals]");
  process.exit(2);
}
const DEC = Number(decArg ?? 18);
const SD_TO_LD = 10n ** BigInt(DEC - 6); // OFT messages carry amounts in 6 shared decimals
const oftSent = parseAbiItem("event OFTSent(bytes32 indexed guid, uint32 dstEid, address indexed fromAddress, uint256 amountSentLD, uint256 amountReceivedLD)");

try {
  const chains = loadChains();
  const home = chains.find((c) => c.name === homeName)!, oftChain = chains.find((c) => c.name === oftName)!;
  const oft = oftChain.deployments[key] as Address;

  const legitIn = new Map<Address, bigint>(), forgedNonces: bigint[] = [];
  for (const r of await auditPath(key, home, oftChain)) {
    if (r.status === "OK" && r.payload) { // OFT message: recipient (bytes32) + amount (uint64, shared decimals)
      const to = getAddress(slice(r.payload, 12, 32));
      legitIn.set(to, (legitIn.get(to) ?? 0n) + BigInt(slice(r.payload, 32, 40)) * SD_TO_LD);
    } else if (r.status.startsWith("FORGED")) forgedNonces.push(r.nonce);
  }

  const out = new Map<Address, bigint>();
  const latest = await oftChain.pub.getBlockNumber();
  for (let start = 1n; start <= latest; start += 1_000n) {
    const end = start + 999n < latest ? start + 999n : latest;
    const logs: Log[] = await oftChain.pub.getLogs({ address: oft, event: oftSent, fromBlock: start, toBlock: end });
    for (const l of logs) {
      const { args } = decodeEventLog({ abi: [oftSent], data: l.data, topics: l.topics });
      out.set(args.fromAddress, (out.get(args.fromAddress) ?? 0n) + args.amountSentLD);
    }
  }

  const erc20 = parseAbi(["function balanceOf(address) view returns (uint256)", "function totalSupply() view returns (uint256)"]);
  const holders = new Set<Address>([...legitIn.keys(), ...out.keys()]);
  let total = 0n;
  const rows = [];
  for (const h of holders) {
    const bal = await oftChain.pub.readContract({ address: oft, abi: erc20, functionName: "balanceOf", args: [h] });
    const net = (legitIn.get(h) ?? 0n) - (out.get(h) ?? 0n);
    const eligible = net <= 0n ? 0n : net < bal ? net : bal;
    total += eligible;
    rows.push({ holder: h, balance: formatUnits(bal, DEC), legitIn: formatUnits(legitIn.get(h) ?? 0n, DEC),
      out: formatUnits(out.get(h) ?? 0n, DEC), eligible: formatUnits(eligible, DEC), eligibleLD: eligible.toString() });
  }
  const supply = await oftChain.pub.readContract({ address: oft, abi: erc20, functionName: "totalSupply" });
  console.log(JSON.stringify({ key, oft, forgedNonces: forgedNonces.map(String), supply: formatUnits(supply, DEC),
    eligibleTotal: formatUnits(total, DEC), excluded: formatUnits(supply - total, DEC), holders: rows }, null, 2));
} catch (e) {
  console.error(`snapshot failed: ${errMsg(e)}`);
  process.exit(1);
}
