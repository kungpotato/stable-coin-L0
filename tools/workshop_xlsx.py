"""Builds workshop-layerzero.xlsx (the workshop runbook). Edit the data below, then:
    python3 -m venv .venv && .venv/bin/pip install openpyxl
    .venv/bin/python tools/workshop_xlsx.py
"""
import math
import sys
from pathlib import Path
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation

OUT = sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).resolve().parent.parent / "workshop-layerzero.xlsx")
F = "Arial"
HDR_FILL = PatternFill("solid", fgColor="1F3864")
HDR_FONT = Font(name=F, bold=True, color="FFFFFF", size=10)
BODY = Font(name=F, size=10)
MONO = Font(name="Menlo", size=9)
BOLD = Font(name=F, size=10, bold=True)
WRAP = Alignment(wrap_text=True, vertical="top")
THIN = Side(style="thin", color="BFBFBF")
BOX = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
STATUS_FILL = {
    "เสร็จ": PatternFill("solid", fgColor="E2EFDA"),
    "เสร็จบางส่วน": PatternFill("solid", fgColor="FFF2CC"),
    "ยังไม่เริ่ม": PatternFill("solid", fgColor="F2F2F2"),
}


THAI_MARKS = {chr(c) for c in range(0x0E31, 0x0E4F)} - {chr(0x0E32), chr(0x0E33), chr(0x0E40), chr(0x0E41),
                                                    chr(0x0E42), chr(0x0E43), chr(0x0E44), chr(0x0E46)}


def text_lines(text, width, mono):
    """Estimate wrapped line count: viewers like Numbers/Preview don't auto-fit row height."""
    per_char = 1.25 if mono else 1.05  # column width units per character (Menlo 9pt is wider)
    usable = max(width - 1, 1)
    n = 0
    for line in str(text).split("\n"):
        visible = sum(0 if ch in THAI_MARKS else 1 for ch in line)  # Thai vowel/tone marks take no width
        n += max(1, math.ceil(visible * per_char / usable))
    return n


def fit_rows(ws, widths, mono_cols=(), first_row=1):
    for row in ws.iter_rows(min_row=first_row, max_row=ws.max_row):
        lines = 1
        for c in row:
            if c.value is None or c.column_letter not in widths:
                continue
            lines = max(lines, text_lines(c.value, widths[c.column_letter], c.column_letter in mono_cols))
        ws.row_dimensions[row[0].row].height = 16 * lines + 6  # 16pt per line fits Thai ascenders/descenders


def table(ws, headers, rows, widths, mono_cols=(), status_col=None):
    ws.append(headers)
    for c in ws[1]:
        c.font, c.fill, c.alignment, c.border = HDR_FONT, HDR_FILL, WRAP, BOX
    for r in rows:
        for v in r:
            assert not (isinstance(v, str) and v.startswith('=') and not v.startswith('=COUNT')), v
        ws.append(r)
    for row in ws.iter_rows(min_row=2, max_row=ws.max_row):
        for c in row:
            c.alignment, c.border = WRAP, BOX
            c.font = MONO if c.column_letter in mono_cols else BODY
        if status_col:
            s = row[ord(status_col) - 65]
            if s.value in STATUS_FILL:
                s.fill = STATUS_FILL[s.value]
    for col, w in widths.items():
        ws.column_dimensions[col].width = w
    fit_rows(ws, widths, mono_cols)
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = ws.dimensions


wb = Workbook()

# ---------------- Overview ----------------
ov = wb.active
ov.title = "Overview"
topics = [
    (1, "ปัญหา cross-chain และภาพรวม LayerZero", "อธิบายได้ว่า LayerZero เป็น messaging layer ไม่ใช่ bridge และไม่ถือเงินผู้ใช้", "พื้นฐาน blockchain, อ่านเคส bridge hack (Ronin, Wormhole, Nomad)", "ยังไม่เริ่ม"),
    (2, "Architecture หลัก (V2)", "ไล่ lifecycle ได้: send → DVN verify → commit → lzReceive", "ผ่าน topic 1, เข้าใจ event/log, เปิด LayerZero Scan", "ยังไม่เริ่ม"),
    (3, "Security model และ configuration", "ออกแบบ DVN set / threshold / confirmations ที่เหมาะกับ stablecoin", "ผ่าน topic 2, รายชื่อเชนเป้าหมาย, risk appetite จากฝั่งธุรกิจ", "ยังไม่เริ่ม"),
    (4, "OApp: cross-chain app ตัวแรก", "deploy OApp 2 testnet แล้วส่งข้อความข้ามเชนได้", "Solidity ระดับกลาง, RPC + faucet 2 testnet", "ยังไม่เริ่ม"),
    (5, "OFT: token ข้ามเชน", "เลือก OFT vs OFT Adapter ได้ และโอน token ข้ามเชนได้", "ผ่าน topic 4, ERC-20, ตัดสินใจ home chain / decimals", "ยังไม่เริ่ม"),
    (6, "Stablecoin-specific controls", "มี rate limit, pause, blacklist และ supply invariant ข้ามเชน", "ผ่าน topic 5, AccessControl/Pausable, ข้อกำหนด compliance", "ยังไม่เริ่ม"),
    (7, "Advanced patterns", "ออกแบบ lzCompose / lzRead สำหรับ use case จริงได้", "ผ่าน topic 5, ABI encode/decode, DeFi พื้นฐาน", "ยังไม่เริ่ม"),
    (8, "Deployment, operations, debugging", "มี runbook deploy + incident response", "ผ่านทุก topic, explorer API key, Safe multisig", "ยังไม่เริ่ม"),
    (9, "ประเมินความพร้อมของ potato-chain", "ยืนยันว่า LayerZero V2 deploy และทำงานบน potato-chain ได้ และรู้ว่าต้องแก้หรือเลี่ยงอะไร", "potato localnet รันได้, อ่าน known-issues.md, เข้าใจ topic 2", "เสร็จบางส่วน"),
    (10, "เลือกเชนคู่ และวาง topology", "เลือกเชนคู่ + EID + home chain ของแต่ละ asset", "RPC/gas ของเชนคู่, คุยฝั่งธุรกิจเรื่อง home chain", "ยังไม่เริ่ม"),
    (11, "Deploy LayerZero V2 protocol เอง (2 เชน)", "Endpoint/ULN302 บนสองเชน + default config ข้ามเชน", "LayerZero-v2 sources, deployer key, ที่เก็บ address", "ยังไม่เริ่ม"),
    (12, "เขียน DVN + Executor ของเราเอง", "worker อัตโนมัติ ส่ง message ถึงปลายทางโดยไม่ต้อง relay มือ", "TypeScript+viem หรือ Go, workaround known issues, key แยก", "ยังไม่เริ่ม"),
    (13, "Bridge native crypto (POTATO)", "โอน POTATO ไป-กลับ โดย supply รวมถูกต้อง", "พฤติกรรม WPOTATO precompile, ผ่าน topic 5", "ยังไม่เริ่ม"),
    (14, "Bridge stablecoin (USDC)", "bridge USDC ถูก model + supply invariant + controls", "home chain decision, รายการ contract ที่ผูก USDC เดิม, ผ่าน topic 6", "ยังไม่เริ่ม"),
    (15, "Frontend + indexer + explorer", "ผู้ใช้กด bridge จาก web/ และเห็นสถานะ message", "web/ (wagmi/viem), indexer/ (Ponder), address จาก 11–14", "ยังไม่เริ่ม"),
    (16, "IBC vs LayerZero และทางไป production", "ตัดสินใจ asset ไหนใช้ IBC/LayerZero และรู้ขั้นตอน integration ทางการ", "ประสบการณ์ IBC bridge, แผนเปิด public network", "ยังไม่เริ่ม"),
]
rows = []
for i, (n, name, goal, prep, status) in enumerate(topics, start=2):
    rows.append([n, name, goal, prep, status,
                 f'=COUNTIF(Steps!$A:$A,A{i})',
                 f'=COUNTIFS(Steps!$A:$A,A{i},Steps!$J:$J,"ผ่าน")'])
table(ov, ["Topic", "ชื่อ", "Goal", "ต้องเตรียมก่อน", "สถานะ", "จำนวน step", "step ที่ผ่าน"],
      rows, {"A": 7, "B": 34, "C": 50, "D": 46, "E": 14, "F": 11, "G": 11}, status_col="E")
note_row = ov.max_row + 2
ov.cell(note_row, 1, "หมายเหตุ").font = BOLD
notes = [
    "Topic 9 = 'เสร็จบางส่วน': ผ่าน 3/4 เกณฑ์ เกณฑ์ known-issues รู้ workaround แล้วแต่จะพิสูจน์จริงใน topic 12 (worker ที่ใช้ viem)",
    "Topic 1–8 เป็นสาย LayerZero ทั่วไป ยังไม่ได้ทำ จึงยังไม่มี step / command",
    "แต่ละ step ใน sheet Steps อ้าง commit ใน repo stable-coin-L0 (git log --oneline)",
]
for k, t in enumerate(notes, start=1):
    c = ov.cell(note_row + k, 1, f"• {t}")
    c.font = BODY
    ov.merge_cells(start_row=note_row + k, start_column=1, end_row=note_row + k, end_column=7)

# ---------------- Steps ----------------
st = wb.create_sheet("Steps")
S = "stable-coin-L0"
L = "stable-coin-L0/lz-potato"
steps = [
    (9, 0, "ให้ shell เจอ forge / cast / anvil", "Foundry ติดตั้งไว้ที่ ~/.foundry/bin แต่ไม่อยู่ใน PATH (พิมพ์ forge แล้วขึ้น command not found)",
     S, 'export PATH="$HOME/.foundry/bin:$PATH" && forge --version',
     "forge Version: 1.8.3 ...", "—", "forge 1.8.3", "ผ่าน"),
    (9, 1, "เช็คว่าใครใช้ port 8545 อยู่", "README ของ potato บอกว่า JSON-RPC อยู่ที่ 8545 ต้องแน่ใจว่าคุยกับเชนถูกตัว",
     S, "curl -s -X POST -H 'content-type: application/json' --data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"web3_clientVersion\",\"params\":[]}' http://localhost:8545",
     'ถ้าเป็น potato จะไม่ใช่ "anvil/..." และ eth_chainId = 0xac9fe (707070)',
     "—", 'ได้ "anvil/v1.8.3", chainId 0x7a69 → เป็น anvil fork mainnet ที่รันค้างไว้ ไม่ใช่ potato (ไม่ปิดของเดิม)', "ผ่าน"),
    (9, 2, "รัน potato localnet บน port อื่น", "ไม่ชนกับ anvil เดิม และไม่ต้องแก้ไฟล์ใน potato-chain",
     S, "docker-compose -f ../potato-chain/docker-compose.yml -f potato-localnet/ports-override.yml up -d --build",
     "Container potato-node0..3 Started (build ครั้งแรกนานหลายนาทีเพราะ go build)",
     "a495737", "4 containers Up, node0 log: finalized block height=5333+", "ผ่าน"),
    (9, 3, "ยืนยันว่าคุยกับ potato จริง", "กันพลาด deploy ผิดเชน",
     S, "cast chain-id --rpc-url http://localhost:18545 && cast block-number --rpc-url http://localhost:18545",
     "707070 และ block number เพิ่มขึ้นทุกครั้งที่รัน", "a495737", "707070, block ~5337", "ผ่าน"),
    (9, 4, "ติดตั้ง dependency ของ LayerZero", "ได้ source ของ EndpointV2 / ULN302 / OApp / OFT",
     L, "git submodule update --init && npm ci --legacy-peer-deps",
     "node_modules/@layerzerolabs มี lz-evm-protocol-v2, lz-evm-messagelib-v2, oapp-evm, oft-evm",
     "e1473c5", "ครบ 4 package (protocol/messagelib 3.0.168, oapp 0.4.1, oft 4.0.1)", "ผ่าน"),
    (9, 5, "เช็ค license", "protocol ของ LayerZero ไม่ใช่ MIT ต้องรู้ก่อนเอาไป production",
     L, "grep '\"license\"' node_modules/@layerzerolabs/*/package.json",
     "protocol/messagelib = LZBL-1.2, oapp/oft = MIT", "e1473c5", "ตรงตามที่คาด", "ผ่าน"),
    (9, 6, "compile DVN + Executor จำลอง", "send lib ต้องเรียก getFee/assignJob ของ DVN และ executor",
     L, "git checkout 1a69ee4 && forge build", "Compiler run successful!", "1a69ee4", "Compiler run successful!", "ผ่าน"),
    (9, 7, "compile PingOApp", "OApp ที่เล็กที่สุดไว้ทดสอบ end-to-end",
     L, "git checkout d714a54 && forge build", "Compiler run successful! (มี lint warning reentrancy-events ได้ ไม่เป็นไร)",
     "d714a54", "Compiler run successful!", "ผ่าน"),
    (9, 8, "compile protocol จริง (EndpointV2, ULN302) ด้วย EVM Prague", "เกณฑ์ข้อ 1: bytecode เข้ากับ potato",
     L, "git checkout 3d5c683 && forge build",
     "Compiler run successful! ถ้าไม่มี context remapping จะเจอ error ของ OpenZeppelin v4/v5 ชนกัน",
     "3d5c683", "ผ่าน (ระหว่างทางเจอ Stack too deep → แตก script เป็น helper function)", "ผ่าน"),
    (9, 9, "เปิด anvil ทดสอบแยก", "แยกให้ออกว่าถ้าพังเป็นเพราะ script หรือเพราะเชน",
     S, "anvil --port 28545 --chain-id 31338 --hardfork prague", "Listening on 127.0.0.1:28545 + รายการ private key ทดสอบ",
     "—", "รันได้", "ผ่าน"),
    (9, 10, "loopback บน anvil", "พิสูจน์ว่า script ถูกก่อนไปเชนจริง",
     L, "git checkout main && ./lab-loopback.sh http://localhost:28545 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 40999",
     'output ท้ายสุด:\n== B.lastMessage: "hello from eid 40999 @ ..."\n== B.received: 1', "ea51410",
     'B.lastMessage = "hello from eid 40999 @ 1792019218", received = 1', "ผ่าน"),
    (9, 11, "loopback บน potato-chain", "เกณฑ์ข้อ 2: LayerZero ทำงานบนเชนเราจริง",
     L, ". ../../potato-chain/scripts/lib.sh && ./lab-loopback.sh http://localhost:18545 $DEV0_PRIVKEY 40707",
     'output (ใช้เวลา ~40 วินาที):\n== chain 707070 ...\n== B.lastMessage: "hello from eid 40707 @ ..."\n== B.received: 1', "ea51410",
     'endpoint 0xeD1E4145…dD7f, B.lastMessage = "hello from eid 40707 @ 1792019333", received = 1', "ผ่าน"),
    (9, 12, "เช็ค event ครบ lifecycle", "ยืนยันว่าผ่านทุกด่าน ไม่ใช่แค่ state เปลี่ยน",
     L, 'EP=$(jq -r .EndpointV2 deployments/707070.json); for e in "PacketSent(bytes,bytes,address)" "PacketVerified((uint32,bytes32,uint64),address,bytes32)" "PacketDelivered((uint32,bytes32,uint64),address)"; do cast logs --from-block 5337 --address $EP "$e" --rpc-url http://localhost:18545 --json | jq length; done',
     "1 / 1 / 1", "ea51410", "1 / 1 / 1", "ผ่าน"),
    (9, 13, "เทียบ gas potato vs anvil", "ถ้า EVM ของ potato ต่างจาก Ethereum gas จะเพี้ยน",
     L, "for c in 707070 31338; do jq -r '.receipts[].gasUsed' broadcast/Relay.s.sol/$c/run-latest.json | xargs -n1 cast to-dec | paste -sd' ' -; done",
     "ตัวเลข 3 ค่า (verify, commit, lzReceive) ใกล้เคียงกันมาก", "ea51410",
     "potato 55,615 / 79,357 / 173,989 vs anvil 55,627 / 79,369 / 174,001 (ต่าง 12 gas)", "ผ่าน"),
    (9, 14, "วัด block time และ finality", "เกณฑ์ข้อ 3: ใช้ตั้ง confirmations",
     S, "n1=$(cast block-number --rpc-url http://localhost:18545); sleep 10; n2=$(cast block-number --rpc-url http://localhost:18545); echo $((n2-n1))",
     "~8 block ต่อ 10 วินาที (CometBFT finality ทันที → confirmations = 1)", "—", "8 block / 10s ≈ 1.25s ต่อ block", "ผ่าน"),
    (9, 15, "ประเมิน known issues ของ potato", "เกณฑ์ข้อ 4: worker ต้องเลี่ยง bug อะไร",
     S, "cat ../potato-chain/docs/known-issues.md",
     "2 bug: eth_getLogs fromBlock 0 ซ้ำ, eth_fillTransaction ประเมิน gas ผิด", "ea51410",
     "เลี่ยงแล้วใน script (อ่าน log จาก deploy block) แต่ยังไม่ได้ reproduce bug และยังไม่ได้ทดสอบกับ viem → พิสูจน์ใน topic 12", "บางส่วน"),
    (9, 16, "บันทึกผล", "ให้ทีมอ่านผลได้โดยไม่ต้องรันใหม่",
     L, "git show a7337a2 --stat", "README.md มีตาราง Topic 9 result + deployments/707070.json", "a7337a2", "บันทึกแล้ว", "ผ่าน"),
    (9, 17, "(ทางเลือก) ปิด lab", "คืน resource เครื่อง ไม่แตะ anvil :8545 ตัวเดิม",
     S, 'docker-compose -f ../potato-chain/docker-compose.yml -f potato-localnet/ports-override.yml down && pkill -f "anvil --port 28545"',
     "Container potato-node0..3 Removed", "—", "ยังไม่ได้ปิด (ยังรันอยู่สำหรับ topic 10)", "ยังไม่ทำ"),
]
RERUN = {
    0: ("ได้", "มีผลแค่ terminal นั้น เปิด terminal ใหม่ต้องรันใหม่ (หรือใส่บรรทัด export ใน ~/.zshrc ถาวร)"),
    1: ("ได้", "อ่านอย่างเดียว ไม่เปลี่ยนอะไร"),
    2: ("ได้", "ถ้า image ไม่เปลี่ยนจะไม่มีอะไรเกิดขึ้น ถ้าโค้ด potato เปลี่ยนจะ rebuild และ restart node แต่ state ของเชนยังอยู่ (.localnet). ห้ามใช้ 'make localnet-up' แทน เพราะจะชน port 8545 กับ anvil เดิม และห้ามรัน 'make localnet-init' เพราะจะล้างเชน ทำให้ address ใน deployments/707070.json ใช้ไม่ได้"),
    3: ("ได้", "อ่านอย่างเดียว block number จะเพิ่มทุกครั้ง"),
    4: ("ได้", "npm ci ลบ node_modules แล้วติดตั้งใหม่ตาม package-lock.json ได้เวอร์ชันเดิมทุกครั้ง แค่ใช้เวลาและเน็ต"),
    5: ("ได้", "อ่านอย่างเดียว"),
    6: ("ได้", "git checkout <hash> ทำให้อยู่ในสถานะ detached HEAD ต้อง 'git checkout main' กลับ ถ้ามีไฟล์แก้ค้างอยู่ git อาจไม่ยอม checkout ให้ commit หรือ stash ก่อน. forge build รันซ้ำได้ ไม่มีผลข้างเคียง"),
    7: ("ได้", "เหมือน step 6"),
    8: ("ได้", "เหมือน step 6"),
    9: ("ได้ (ทีละตัว)", "ถ้ามี anvil :28545 รันอยู่แล้ว ตัวที่สองจะ error 'address in use'. ปิดแล้วเปิดใหม่ = state ใน anvil หายหมด address ใน deployments/31338.json ใช้ไม่ได้ (ไม่กระทบอะไร เพราะ step 10 deploy ใหม่ทุกครั้ง)"),
    10: ("ได้", "ทุกครั้ง deploy LayerZero ชุดใหม่ (address ใหม่) และเขียนทับ deployments/31338.json ชุดเก่ายังอยู่บน anvil แต่ไม่มีใครใช้ ไม่เสียหาย"),
    11: ("ได้ (มีผลข้างเคียง)", "potato เก็บ state ถาวร ทุกครั้งจะ deploy ชุดใหม่ ใช้ gas ของ dev0 (ยังเหลือ ~498 POTATO) และเขียนทับ deployments/707070.json ซึ่ง commit ไว้แล้ว → git จะเห็นไฟล์เปลี่ยน ต้องเลือกว่าจะ commit address ชุดใหม่ หรือ 'git checkout -- deployments/707070.json' คืน. ถ้ารัน script/Relay.s.sol ซ้ำด้วย PAYLOAD เดิม tx จะ revert (packet ถูกส่งไปแล้ว) ไม่เสียหาย แค่เสีย gas"),
    12: ("ได้", "อ่านอย่างเดียว ใช้ endpoint จาก deployments/707070.json ถ้ารัน step 11 ใหม่ ให้เปลี่ยน --from-block เป็นค่า 'start block' ใน output รอบใหม่"),
    13: ("ได้", "อ่านอย่างเดียว อ่านจากรอบล่าสุด (run-latest.json) ตัวเลขจะเป็นของรอบที่รันล่าสุด"),
    14: ("ได้", "อ่านอย่างเดียว ตัวเลขแกว่งได้เล็กน้อย"),
    15: ("ได้", "อ่านอย่างเดียว"),
    16: ("ได้", "อ่านอย่างเดียว"),
    17: ("ได้", "potato หยุดผลิต block แต่ state ยังอยู่ (.localnet) เปิดใหม่ด้วย step 2 แล้ว address เดิมยังใช้ได้. anvil :28545 state หาย. ถ้าไม่มีอะไรรันอยู่ pkill จะคืน exit code 1 ไม่เป็นไร. ไม่กระทบ anvil :8545 ตัวเดิม"),
}
rows = [[t, n, what, why, cwd, cmd, expect, commit, actual, status, *RERUN[n]]
        for (t, n, what, why, cwd, cmd, expect, commit, actual, status) in steps]
table(st, ["Topic", "Step", "ทำอะไร", "ทำไม", "รันจากโฟลเดอร์", "Command", "จะเห็นอะไร (expected)", "Commit", "ผลจริงของเรา", "ผล",
           "รันซ้ำได้ไหม", "ถ้ารันซ้ำจะกระทบอะไร"],
      rows, {"A": 7, "B": 6, "C": 28, "D": 32, "E": 20, "F": 60, "G": 40, "H": 10, "I": 42, "J": 9, "K": 14, "L": 60},
      mono_cols=("F", "H"))
dv = DataValidation(type="list", formula1='"ผ่าน,บางส่วน,ไม่ผ่าน,ยังไม่ทำ"', allow_blank=True)
st.add_data_validation(dv)
dv.add(f"J2:J500")
fills = {"ผ่าน": "E2EFDA", "บางส่วน": "FFF2CC", "ยังไม่ทำ": "F2F2F2", "ไม่ผ่าน": "F8CBAD"}
for c in st["J"][1:]:
    if c.value in fills:
        c.fill = PatternFill("solid", fgColor=fills[c.value])
for c in st["K"][1:]:
    c.fill = PatternFill("solid", fgColor="E2EFDA" if c.value == "ได้" else "FFF2CC")

# ---------------- Commits ----------------
cm = wb.create_sheet("Commits")
commits = [
    ("a495737", "chore: run potato localnet next to existing anvil", ".gitignore, potato-localnet/ports-override.yml", "9.2–9.3", "— (ไม่มี Solidity)"),
    ("e1473c5", "build(lz-potato): foundry project with LayerZero V2 deps", "foundry.toml, remappings.txt, package.json, package-lock.json, lib/forge-std (submodule v1.16.2)", "9.4–9.5", "ยังไม่มี source (toolchain อย่างเดียว)"),
    ("1a69ee4", "feat(lz-potato): zero-fee lab DVN and executor", "src/lab/LabDVN.sol, src/lab/LabExecutor.sol", "9.6", "forge build ผ่าน"),
    ("d714a54", "feat(lz-potato): PingOApp for end-to-end message tests", "src/lab/PingOApp.sol", "9.7", "forge build ผ่าน"),
    ("3d5c683", "feat(lz-potato): deploy self-hosted LayerZero V2 stack", "script/DeployLab.s.sol", "9.8", "forge build ผ่าน"),
    ("ea51410", "feat(lz-potato): manual relay and loopback runner", "script/Relay.s.sol, lab-loopback.sh", "9.10–9.15", "forge build ผ่าน"),
    ("a7337a2", "docs(lz-potato): topic 9 readiness result on potato-chain", "README.md, deployments/707070.json", "9.16", "forge build ผ่าน"),
]
table(cm, ["Commit", "Message", "ไฟล์", "ใช้ใน step", "ตรวจแล้วว่า build ได้ลำพัง"],
      [list(c) for c in commits], {"A": 10, "B": 52, "C": 58, "D": 12, "E": 30}, mono_cols=("A",))
r = cm.max_row + 2
cm.cell(r, 1, "Small batch (Accelerate)").font = BOLD
for k, t in enumerate([
    "1 commit = 1 การเปลี่ยนแปลงที่ทำงานได้เอง และ build ผ่านลำพัง (ตรวจทีละ commit ด้วย git worktree แล้ว)",
    "ลำดับ commit = ลำดับ step ของ workshop → git checkout <commit> แล้วทำตาม step ได้",
    "หมายเหตุ: repo นี้ git init หลังทำงานเสร็จ commit จึงแบ่งย้อนหลังตาม step ไม่ใช่ commit ระหว่างทำจริง ตั้งแต่ topic 10 จะ commit ทันทีทีละ step",
], start=1):
    c = cm.cell(r + k, 1, f"• {t}")
    c.font = BODY
    cm.merge_cells(start_row=r + k, start_column=1, end_row=r + k, end_column=5)

# ---------------- How to use ----------------
hw = wb.create_sheet("วิธีใช้")
lines = [
    ("วิธีใช้ไฟล์นี้", True),
    ("1. Overview: ดู goal / สิ่งที่ต้องเตรียม / สถานะของแต่ละ topic (จำนวน step คำนวณจาก sheet Steps อัตโนมัติ)", False),
    ("2. Steps: ทำตามทีละแถว รัน Command จาก 'รันจากโฟลเดอร์' แล้วเทียบกับ 'จะเห็นอะไร'", False),
    ("3. ช่องที่ต้องกรอกเอง: 'ผลจริงของเรา' และ 'ผล' (dropdown: ผ่าน / บางส่วน / ไม่ผ่าน / ยังไม่ทำ)", False),
    ("4. รันซ้ำได้ไหม: เขียว = รันซ้ำได้ ไม่มีผลข้างเคียง / เหลือง = รันได้แต่มีเงื่อนไขหรือผลข้างเคียง ให้อ่าน 'ถ้ารันซ้ำจะกระทบอะไร' ก่อน", False),
    ("5. Commits: commit ไหนแก้อะไร → git show <hash> เพื่อดู diff", False),
    ("6. Key ในคำสั่งเป็น dev key สาธารณะของ anvil / potato localnet เท่านั้น ห้ามใช้กับเงินจริง", False),
    ("ตัวอย่างแถว: Topic 9 Step 3 → รัน cast chain-id ... ต้องเห็น 707070", False),
]
for i, (t, b) in enumerate(lines, start=1):
    c = hw.cell(i, 1, t)
    c.font = BOLD if b else BODY
    c.alignment = WRAP
hw.column_dimensions["A"].width = 120
fit_rows(hw, {"A": 120})

wb.move_sheet("วิธีใช้", offset=-3)
wb.active = 0
# no LibreOffice here to cache formula results: make Excel/Numbers compute them on open
from openpyxl.workbook.properties import CalcProperties
wb.calculation = CalcProperties(fullCalcOnLoad=True)
wb.save(OUT)
print("saved", OUT)
