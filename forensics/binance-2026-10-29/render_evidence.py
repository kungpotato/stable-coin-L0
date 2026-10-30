# Render evidence.json into the evidence appendix of binance-incident-2026-10-29.html (between the EVIDENCE markers).
import html, json, time

ev = json.load(open("evidence.json"))
PAGE = "../../binance-incident-2026-10-29.html"
SEL = {"0x8a179be4": "sweep(address,address[])", "0x043ff9d2": "callExecute(address,address,uint256,bytes)",
       "0x4782f779": "withdrawETH(address,uint256)", "0x095ea7b3": "approve(address,uint256)", "0x60808060": "(contract creation)",
       "0xb438689f": "Tornado withdraw", "0x": "(no calldata)"}
LABEL = {b["address"]: b["label"] for b in ev["balances"]}
LABEL.update({"0x63e842b054bd624a465454d533c33f573e9c6fae": "sweeper contract", "0xee7ae85f2fe2239e27d9c1e23fffe168d63b4055": "Binance smart wallet",
              "0x19bee294a6daab49c9e5ab69a5da6c035c70f2bf": "test sweeper", "0x837810e3be7a3e89c570e7a01a13d3b566aafbc3": "rehearsal EOA 1",
              "0x9c29ba2de4b2d6c3630685650663cfe7b70dbb6b": "rehearsal EOA 2", "0x43aedb9bad6219677a2c8d6858321c16988404bd": "rehearsal EOA 3",
              "0xd90e2f925da726b50c4ed8d0fb90ad053324f31b": "Tornado Cash Router", "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45": "Uniswap SwapRouter02",
              "0x7a250d5630b4cf539739df2c5dacb4c659f2488d": "Uniswap V2 Router02", "0xe592427a0aece92de3edee1f18e0157c05861564": "Uniswap V3 SwapRouter",
              "0xdac17f958d2ee523a2206206994597c13d831ec7": "USDT", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": "USDC"})
esc = html.escape


def t(ts):
    return time.strftime("%m-%d %H:%M:%S", time.gmtime(ts))


def addr(a, full=True):
    if not a:
        return "—"
    lab = LABEL.get(a.lower())
    text = a if full else a[:8] + "…" + a[-4:]
    return f'<a class="mono" href="https://etherscan.io/address/{a}">{text}</a>' + (f' <span class="lab">{esc(lab)}</span>' if lab else "")


def txh(h):
    return f'<a class="mono" href="https://etherscan.io/tx/{h}">{h}</a>'


def n(x, d=4):
    return f"{x:,.{d}f}".rstrip("0").rstrip(".") if isinstance(x, float) else f"{x:,}"


def table(head, rows, cls="ev"):
    return (f'<div class="table-wrap"><table class="{cls}"><thead><tr>' + "".join(f"<th>{h}</th>" for h in head) + "</tr></thead><tbody>"
            + "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows) + "</tbody></table></div>")


def txrow(x):
    return [txh(x["hash"]), f'<span class="num">{x["block"]}</span>', f'<span class="num">{t(x["ts"])}</span>',
            f'<span class="num">{x["index"]}/{x["txs_in_block"]}</span>', str(x["type"]), addr(x["from"], False), addr(x["to"], False) if x["to"] else "CREATE",
            esc(SEL.get(x["selector"], x["selector"])), n(x["value_eth"]), f'{x["gas_used"]:,}', n(x["priority_gwei"], 6), esc(x["builder_tag"][:24]), x["status"]]


TXHEAD = ["tx hash", "block", "เวลา UTC", "idx", "type", "from", "to", "call", "ETH", "gas used", "prio gwei", "builder", "status"]
out = [f'<section id="evidence"><h2>ภาคผนวก: หลักฐานทั้งหมด</h2>'
       f'<p>ทุกตัวเลขในส่วนนี้สร้างโดย <code>forensics/binance-2026-10-29/evidence.py</code> จากเชนโดยตรง (RPC <code>{esc(ev["rpc"])}</code>, '
       f'เก็บเมื่อ {esc(ev["collected_at"])}, ยอดคงเหลือ ณ block <span class="num">{ev["snapshot_block"]}</span>) แล้ว render ด้วย <code>render_evidence.py</code> '
       f'ไม่มีการพิมพ์ตัวเลขด้วยมือ ทุก hash และ address ลิงก์ไปที่ Etherscan</p>']

# E1 attacker txs
out.append('<h3 id="ev-attacker">E1 · ทุก tx ของ EOA ผู้โจมตี</h3>')
out.append(f'<p>EOA {addr("0x7c8601d4645b93cea45f71e118a729332e6b5ca0")} ส่งทั้งหมด {len(ev["attacker_txs"])} tx (nonce 0–{len(ev["attacker_txs"]) - 1})</p>')
out.append(table(["nonce"] + TXHEAD + ["หมายเหตุ"], [[str(x["nonce"])] + txrow(x) + [
    (f'authorization {x["authorizations"]} ตัว → ' + ", ".join(addr(a, False) for a in x.get("delegated_accounts_target", [])) if x["authorizations"] else "")
    + (f'สร้าง {addr(x["contract_created"], False)}' if x["contract_created"] else "")] for x in ev["attacker_txs"]], "ev wide"))

# E2 funding
f = ev["funding"]
out.append('<h3 id="ev-funding">E2 · เงินตั้งต้น</h3>')
out.append(table(TXHEAD, [txrow(f)], "ev wide"))
out.append(f'<p>ยอดของ EOA ผู้โจมตีหลัง block นี้: <span class="num">{n(f["attacker_balance_after"], 8)}</span> ETH (tx ถูกส่งโดย relayer ไปที่ Tornado Cash Router)</p>')

# E3 delegation
d = ev["delegation"]
out.append('<h3 id="ev-delegation">E3 · tx delegation และ authorization ทั้ง 50 ตัว</h3>')
out.append(table(TXHEAD, [txrow(d)], "ev wide"))
out.append("<p>tx ของ Binance 14 เองใน block เดียวกัน: " + "; ".join(f'{txh(o["hash"])} (index {o["index"]}, nonce {o["nonce"]})' for o in d["b14_own_txs_same_block"]) + "</p>")
signers = {a["signer"] for a in ev["authorizations"]}
out.append(f'<p>ผู้เซ็นที่กู้ได้ด้วย <code>cast recover-authority</code>: {", ".join(addr(s) for s in signers)} · ใช้ได้จริง: nonce '
           + ", ".join(str(a["nonce"]) for a in ev["authorizations"] if a["used"]) + "</p>")
out.append('<details><summary>authorization ทั้ง 50 ตัว</summary>' + table(["#", "nonce", "chainId", "delegate to", "yParity", "r", "s", "signer (recovered)", "used"],
           [[str(i + 1), f'<span class="num">{a["nonce"]}</span>', str(a["chainId"]), addr(a["address"], False), str(a["yParity"]),
             f'<span class="mono">{a["r"]}</span>', f'<span class="mono">{a["s"]}</span>', addr(a["signer"], False), "✅" if a["used"] else ""]
            for i, a in enumerate(ev["authorizations"])], "ev wide") + "</details>")

# E4 state
out.append('<h3 id="ev-state">E4 · สถานะของ Binance 14 ทีละ block</h3>')
out.append(table(["block", "เวลา UTC", "code", "nonce", "ETH", "USDT"],
                 [[f'<span class="num">{s["block"]}</span>', f'<span class="num">{t(s["ts"])}</span>', f'<span class="mono">{s["code"]}</span>',
                   f'<span class="num">{s["nonce"]:,}</span>', n(s["eth"], 2), n(s["usdt"], 2)] for s in ev["b14_state"]]))
sw = ev["sweeper"]
out.append(f'<p>contract {addr(sw["address"])}: {sw["code_bytes"]:,} byte, selector ที่ cast อ่านได้:</p><pre><code>' + esc("\n".join(sw["selectors"])) + "</code></pre>")
out.append(f'<p>smart wallet {addr(ev["smart_wallet"]["address"])}: {ev["smart_wallet"]["code_bytes"]} byte (proxy)</p>')

# E5 replays
out.append('<h3 id="ev-replays">E5 · replay ทุกการกวาดและการดึงเงิน (cast run)</h3>')
for x in ev["attacker_txs"]:
    r = ev["replays"].get(x["hash"])
    if not r:
        continue
    eth = sum(e["eth"] for e in r["eth"])
    title = f'nonce {x["nonce"]} · {t(x["ts"])} · {esc(SEL.get(x["selector"], x["selector"]))} · ETH {n(eth)} · ERC-20 transfer {len(r["tokens"])} ครั้ง'
    body = f'<p>{txh(x["hash"])}</p><pre><code>{esc(r["call"])}</code></pre>'
    rows = [["ETH", "—", addr(e["to"], False), n(e["eth"], 6)] for e in r["eth"]]
    rows += [[esc(k["symbol"]), addr(k["token"], False), f'{addr(k["from"], False)} → {addr(k["to"], False)}', n(k["amount"], 6)] for k in r["tokens"]]
    body += table(["asset", "token", "from → to", "amount"], rows, "ev wide")
    out.append(f'<details{" open" if x["nonce"] == 11 else ""}><summary>{title}</summary>{body}</details>')

# E6 Binance 16, revoke
b = ev["b16_tx"]
out.append('<h3 id="ev-b16">E6 · Binance 16 และการถอน delegation</h3>')
out.append(table(TXHEAD, [txrow(b), txrow(ev["revoke"])], "ev wide"))
out.append(f'<p>Binance 16 ก่อน tx: code <code>{b["b16_code_before"] or "0x"}</code>, ETH {n(b["b16_eth_before"], 2)} → หลัง {n(b["b16_eth_after"], 2)} · '
           f'การถอน: authorization ชี้ไป {", ".join(addr(a) for a in ev["revoke"]["auth_targets"])}</p>')

# E7 money trail
out.append('<h3 id="ev-money">E7 · เส้นทางของเงิน</h3>')
pa = ev.get("post_sweep_activity")
if pa:
    out.append(f'<p>tx ที่ address ผู้โจมตีส่งหลังการกวาด (ถึง block <span class="num">{pa["scanned_to_block"]}</span>): '
               + ", ".join(f'{addr(a, False)} {c:,} tx' for a, c in pa["tx_count"].items()) + "</p>")
    top = sorted(pa["routers"].items(), key=lambda kv: -kv[1])[:14]
    out.append(table(["from", "to", "tx"], [[addr(k.split("|")[0], False), addr(k.split("|")[1], False), f"{v:,}"] for k, v in top]))
    out.append("<p><b>ETH ที่ย้าย (≥ 1 ETH)</b></p>" + table(["เวลา UTC", "from", "to", "ETH", "tx"],
               [[f'<span class="num">{t(m["ts"])}</span>', addr(m["from"], False), addr(m["to"], False), n(m["eth"], 4), txh(m["hash"])] for m in pa["eth_moves"]], "ev wide"))
    out.append("<p><b>USDT ที่ออกจาก Exploiter 2</b></p>" + table(["เวลา UTC", "to", "USDT", "tx"],
               [[f'<span class="num">{t(u["ts"])}</span>', addr(u["to"], False), n(u["amount"], 2), txh(u["hash"])] for u in ev.get("exp2_usdt_out", [])], "ev wide"))
for label, h in ev["usdt_hops"].items():
    out.append(f'<p><b>{esc(label)}</b> {addr(h["address"])}: ทุก tx</p>' + table(TXHEAD + ["USDT ออก"], [txrow(x) + [
        "<br>".join(f'{n(u["amount"], 2)} → {addr(u["to"], False)}' for u in x["usdt_out"])] for x in h["txs"]], "ev wide"))
out.append("<p><b>สาย ETH ที่ไปลงที่ 0x897c</b> (EOA ระหว่างทาง: code ตอนนี้)</p>" + table(TXHEAD, [txrow(x) for x in ev["chain_897c"]], "ev wide"))
out.append(table(["address", "code ตอนนี้"], [[addr(a), f'<span class="mono">{c[:48]}</span>'] for a, c in ev["chain_codes"].items()]))

# E8 balances
out.append(f'<h3 id="ev-balances">E8 · ยอดคงเหลือและสถานะแช่แข็ง ณ block {ev["snapshot_block"]}</h3>')
out.append(table(["address", "ETH", "USDT", "Tether blacklist", "USDC", "Circle blacklist", "nonce", "code"],
                 [[addr(x["address"]), n(x["eth"], 4), n(x["usdt"], 2), "🔒" if x["tether_blacklisted"] else "", n(x["usdc"], 2),
                   "🔒" if x["circle_blacklisted"] else "", f'{x["nonce"]:,}', f'<span class="mono">{x["code"]}</span>'] for x in ev["balances"]], "ev wide"))
out.append("</section>")

page = open(PAGE).read()
start, end = "<!--EVIDENCE-->", "<!--/EVIDENCE-->"
frag = start + "\n" + "\n".join(out) + "\n" + end
if start in page:
    page = page[:page.index(start)] + frag + page[page.index(end) + len(end):]
else:
    page = page.replace('<section id="repro">', frag + '\n\n<section id="repro">')
open(PAGE, "w").write(page)
print("rendered", len(frag), "bytes of evidence")
