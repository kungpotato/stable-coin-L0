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
    (9, "ประเมินความพร้อมของ potato-chain", "ยืนยันว่า LayerZero V2 deploy และทำงานบน potato-chain ได้ และรู้ว่าต้องแก้หรือเลี่ยงอะไร", "potato localnet รันได้, อ่าน known-issues.md, เข้าใจ topic 2", "เสร็จ"),
    (10, "เลือกเชนคู่ และวาง topology", "เลือกเชนคู่ + EID + home chain ของแต่ละ asset", "RPC/gas ของเชนคู่, คุยฝั่งธุรกิจเรื่อง home chain", "เสร็จ"),
    (11, "Deploy LayerZero V2 protocol เอง (2 เชน)", "Endpoint/ULN302 บนสองเชน + default config ข้ามเชน", "LayerZero-v2 sources, deployer key, ที่เก็บ address", "เสร็จ"),
    (12, "เขียน DVN + Executor ของเราเอง", "worker อัตโนมัติ ส่ง message ถึงปลายทางโดยไม่ต้อง relay มือ", "TypeScript+viem หรือ Go, workaround known issues, key แยก", "เสร็จ"),
    (13, "Bridge native crypto (POTATO)", "โอน POTATO ไป-กลับ โดย supply รวมถูกต้อง", "พฤติกรรม WPOTATO precompile, ผ่าน topic 5", "เสร็จ"),
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
    "Topic 9 ปิดครบ 4/4 เกณฑ์แล้ว: เกณฑ์ known-issues พิสูจน์ใน step 12.7–12.8",
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
W = "stable-coin-L0/workers"
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
     "ตอน topic 9: เลี่ยงไว้แต่ยังไม่ได้พิสูจน์ → พิสูจน์แล้วใน step 12.7 (out of gas เมื่อไม่มี workaround) และ 12.8 (getLogs ซ้ำเมื่อเริ่มที่ block 0)", "ผ่าน"),
    (9, 16, "บันทึกผล", "ให้ทีมอ่านผลได้โดยไม่ต้องรันใหม่",
     L, "git show a7337a2 --stat", "README.md มีตาราง Topic 9 result + deployments/707070.json", "a7337a2", "บันทึกแล้ว", "ผ่าน"),
    (9, 17, "(ทางเลือก) ปิด lab", "คืน resource เครื่อง ไม่แตะ anvil :8545 ตัวเดิม",
     S, 'docker-compose -f ../potato-chain/docker-compose.yml -f potato-localnet/ports-override.yml down && pkill -f "anvil --port 28545"',
     "Container potato-node0..3 Removed", "—", "ยังไม่ได้ปิด (ยังรันอยู่สำหรับ topic 10+)", "ยังไม่ทำ"),
    (10, 0, "ตัดสินใจเชนคู่ + home chain ของ USDC", "เป็น business decision ต้องให้เจ้าของโปรเจกต์ตัดสิน ไม่ใช่ dev",
     S, "(ไม่มี command) ตอบ 2 คำถาม: เชนคู่คืออะไร / USDC home อยู่เชนไหน",
     "ได้คำตอบ 2 ข้อ แล้วบันทึกเป็น ADR", "997572d", "เชนคู่ = anvil local, USDC home = anvil (เชนคู่)", "ผ่าน"),
    (10, 1, "ปิด anvil ทดสอบตัวเก่า", "ตัวเก่าไม่เก็บ state แต่ anvil กำลังจะเป็น home ของ USDC",
     S, 'pkill -f "anvil --port 28545"', "ไม่มี output (exit 0 ถ้ามีตัวให้ปิด)", "—", "ปิดแล้ว", "ผ่าน"),
    (10, 2, "เปิด anvil-home ที่เก็บ state ได้", "USDC ตัวจริงอยู่บน anvil ถ้า state หาย supply หายหมด",
     S, "potato-localnet/anvil-home.sh && cast chain-id --rpc-url http://localhost:28545",
     "anvil-home pid ... (log: potato-localnet/anvil-home.log)\n31338", "a0679cf", "pid 20261, chainId 31338", "ผ่าน"),
    (10, 3, "พิสูจน์ว่า state รอด restart", "อย่าเชื่อ flag ต้องเห็นกับตา",
     S, 'cast send 0x000000000000000000000000000000000000dEaD --value 1ether --rpc-url http://localhost:28545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 && pkill -f "anvil --port 28545"; sleep 2; potato-localnet/anvil-home.sh; sleep 3; cast balance 0x000000000000000000000000000000000000dEaD --ether --rpc-url http://localhost:28545 && cast block-number --rpc-url http://localhost:28545',
     "balance ของ 0x…dEaD ยังอยู่ (เพิ่มขึ้น 1 ทุกครั้งที่รัน) และ block number ไม่กลับไปเริ่ม 0", "a0679cf",
     "ก่อน: block 10, balance 1.0 → หลัง restart: block 12, balance 1.0, state file 29,700 bytes", "ผ่าน"),
    (10, 4, "อ่าน ADR 0001", "เหตุผลและผลที่ตามมาของ decision อยู่ที่เดียว คนมาทีหลังเข้าใจได้",
     S, "cat docs/adr/0001-counterpart-chain-and-home-chains.md",
     "ตาราง decision (EID 40707/40338, USDC home = anvil + OFTAdapter, potato = OFT) + ผลที่ตามมา (potato จะมี USDC 2 ตัว)",
     "997572d", "ตามที่คาด", "ผ่าน"),
    (10, 5, "ตรวจ topology กับเชนจริง", "ทุก topic ต่อจากนี้อ่าน EID/RPC/home จากไฟล์นี้ ผิดตรงนี้ = deploy ผิดเชน",
     L, "./check-topology.sh",
     "✅ ทุกบรรทัด และบรรทัดสุดท้าย '== topology OK' (exit 0)", "6dc991b", "✅ 16/16, == topology OK", "ผ่าน"),
    (10, 6, "negative test: checker จับผิดได้จริง", "checker ที่ไม่เคยเห็นมัน fail = ยังไม่รู้ว่ามันทำงาน",
     L, "jq '.chains.potato.rpc=\"http://localhost:8545\" | .assets.USDC.legs.potato.kind=\"adapter\"' config/topology.json > /tmp/bad-topology.json && ./check-topology.sh /tmp/bad-topology.json; echo exit=$?",
     "❌ potato: ... is chainId 31337, expected 707070\n❌ USDC: adapters on [anvil,potato], expected exactly [anvil]\nexit=1",
     "6dc991b", "จับได้ทั้ง 2 จุด, exit code 1", "ผ่าน"),
    (11, 0, "โหลด dev key และตรวจ topology", "ทุก script ของ topic 11 อ่าน KEY_<chain> จาก env และ RPC/EID จาก topology.json",
     L, "set -a; . config/dev-keys.env; set +a; ./check-topology.sh | tail -1",
     "บรรทัดสุดท้าย: == topology OK", "acd3612", "บรรทัดสุดท้าย: == topology OK", "ผ่าน"),
    (11, 1, "deploy protocol บน anvil", "anvil ยังไม่มี LayerZero (state ของ topic 9 หายตอน restart ใน topic 10)",
     L, "forge script script/DeployProtocol.s.sol --rpc-url http://localhost:28545 --broadcast --slow",
     "chain anvil eid 40338\ndeployed EndpointV2 / SendUln302 / ReceiveUln302 / LabDVN / LabExecutor\nONCHAIN EXECUTION COMPLETE & SUCCESSFUL.",
     "acd3612", "deployed ครบ 5 ตัว, EndpointV2 0x9fE4…a6e0", "ผ่าน"),
    (11, 2, "deploy protocol บน potato", "potato มี stack จาก topic 9 อยู่แล้ว ต้องเห็นว่า script ใช้ของเดิม ไม่ deploy ซ้อน",
     L, "forge script script/DeployProtocol.s.sol --rpc-url http://localhost:18545 --broadcast --slow",
     "reused ทั้ง 5 ตัว + 'Warning: No transactions to broadcast.'", "acd3612",
     "reused ครบ 5 ตัว (EndpointV2 0xeD1E…dD7f), ไม่มี tx", "ผ่าน"),
    (11, 3, "wire path potato <-> anvil ทั้งสองฝั่ง", "endpoint ต้องรู้ว่าส่ง/รับกับ EID อีกฝั่งด้วย library, DVN, executor, confirmations อะไร",
     L, "for r in http://localhost:18545 http://localhost:28545; do forge script script/WireProtocol.s.sol --rpc-url $r --broadcast --slow; done",
     "รอบแรก: 'set' 5 บรรทัดต่อเชน (send ULN, receive ULN, executor, default send lib, default receive lib)\nรันซ้ำ: 'ok' ทั้งหมด + No transactions to broadcast",
     "a51a20b", "รอบแรก set 5/5 ต่อเชน, รอบสอง ok 5/5 ไม่มี tx", "ผ่าน"),
    (11, 4, "อ่าน config กลับจากเชนด้วย cast", "ไม่เชื่อ log ของ script ที่ตั้งค่าเอง ต้องอ่านจาก state จริง",
     L, "./check-wiring.sh",
     "✅ 6 บรรทัดต่อเชน (endpoint eid, default send/receive lib, send/receive ULN, executor) แล้ว '== wiring OK'",
     "7dcc37b", "✅ 12/12, == wiring OK (ระหว่างทางแก้ bug ที่ cast พิมพ์ '40338 [4.033e4]')", "ผ่าน"),
    (11, 5, "negative test: checker จับ DVN ผิดได้", "เห็น checker fail อย่างน้อยหนึ่งครั้ง",
     L, "cp deployments/31338.json /tmp/d31338.bak && jq '.LabDVN=\"0x000000000000000000000000000000000000dEaD\"' /tmp/d31338.bak > deployments/31338.json; ./check-wiring.sh | grep -E '❌|=='; cp /tmp/d31338.bak deployments/31338.json",
     "❌ send ULN ... DVNs [0xa513…] (want [0x…dead])\n❌ receive ULN ... เหมือนกัน\n== wiring has errors", "7dcc37b",
     "จับได้ 2 จุด แล้วคืนไฟล์", "ผ่าน"),
    (11, 6, "ส่ง ping potato -> anvil (relay ด้วยมือ)", "goal หลักของ topic: ข้อความข้ามเชนจริงผ่าน stack ที่เรา deploy เอง",
     L, "./lab-crosschain.sh potato anvil",
     "output:\n== sent on potato in block N\n== PacketSent on potato after 1 confirmation(s)\n== anvil Ping.received: n -> n+1\n== anvil Ping.lastSrcEid: 40707\n== anvil Ping.lastMessage: \"hello potato -> anvil @ ...\"",
     "eec40d7", "received 0 -> 1, lastSrcEid 40707 (รันซ้ำ: 1 -> 2)", "ผ่าน"),
    (11, 7, "ส่ง ping anvil -> potato", "ทางกลับใช้ config คนละชุด (send ของ anvil + receive ของ potato) ต้องทดสอบแยก",
     L, "./lab-crosschain.sh anvil potato",
     "output:\n== potato Ping.received: n -> n+1\n== potato Ping.lastSrcEid: 40338", "eec40d7",
     "received 0 -> 1, 1 -> 2, lastSrcEid 40338", "ผ่าน"),
    (11, 8, "ตรวจ nonce ทั้งสองทางตรงกัน", "ถ้า outbound > inbound = มี message ค้าง (ส่งแล้วยังไม่ถึง)",
     L, "P=$(jq -r .Ping deployments/31338.json); PP=$(jq -r .Ping deployments/707070.json); EA=$(jq -r .EndpointV2 deployments/31338.json); EP=$(jq -r .EndpointV2 deployments/707070.json); A=$(cast abi-encode 'f(address)' $P); B=$(cast abi-encode 'f(address)' $PP); echo \"anvil->potato out $(cast call $EA 'outboundNonce(address,uint32,bytes32)(uint64)' $P 40707 $B --rpc-url http://localhost:28545) in $(cast call $EP 'inboundNonce(address,uint32,bytes32)(uint64)' $PP 40338 $A --rpc-url http://localhost:18545)\"; echo \"potato->anvil out $(cast call $EP 'outboundNonce(address,uint32,bytes32)(uint64)' $PP 40338 $A --rpc-url http://localhost:18545) in $(cast call $EA 'inboundNonce(address,uint32,bytes32)(uint64)' $P 40707 $B --rpc-url http://localhost:28545)\"",
     "out = in ทั้งสองบรรทัด", "eec40d7", "anvil->potato 2/2, potato->anvil 2/2 (ก่อนรันรอบ stress)", "ผ่าน"),
    (11, 9, "(incident) anvil-home ค้าง: ตรวจและกู้คืน", "เจอจริงระหว่าง step 11.7 รอบ 2: process ยังอยู่ แต่ RPC ไม่ตอบ, CPU 0%, หยุด dump state, SIGTERM ไม่ได้ผล",
     S, "curl -s -m 5 -X POST -H 'content-type: application/json' --data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_blockNumber\",\"params\":[]}' http://localhost:28545 || { cp potato-localnet/anvil-home-state.json /tmp/anvil-home-state.bak; pkill -9 -f 'anvil --port 28545'; sleep 1; potato-localnet/anvil-home.sh; }",
     "ปกติ: {\"result\":\"0x...\"}\nถ้าค้าง: curl timeout → backup state → kill -9 → เปิดใหม่ (state ย้อนไปไม่เกิน 10 วินาทีจาก --state-interval) แล้วรัน step 11.8 ดู nonce",
     "—", "เกิด 1 ครั้ง กู้แล้ว nonce ตรงทั้งสองทาง ไม่มีข้อมูลหาย. สาเหตุยังไม่รู้: stress test 3 แบบ (block-time+state-interval / state-interval / block-time) ~7 นาทียังไม่ค้าง", "บางส่วน"),
    (12, 0, "ติดตั้งและทดสอบ workers", "worker เขียนด้วย TypeScript + viem 2.56.9 (เวอร์ชันเดียวกับ potato web/) รันตรงด้วย Node 24",
     W, "npm ci && npm test && npm run typecheck",
     "✔ decodePacket reads PacketV1 fields\nℹ pass 1 / fail 0 และ typecheck ไม่มี error", "20d111f", "pass 1, typecheck ok", "ผ่าน"),
    (12, 1, "แยก key ให้ DVN และ Executor", "DVN key ยืนยัน packet ได้อย่างเดียว, executor key แค่จ่าย gas ส่งของ — ไม่ใช้ key deployer",
     L, "./setup-worker-keys.sh",
     "<chain>: LabDVN owner 0x… -> 0x7099…79C8 และ funded 10ether บน potato\nรันซ้ำ: 'already DVN key' / 'has 10.0'", "ff6c3ba",
     "เปลี่ยน owner ทั้ง 2 เชน, เติม 10 POTATO ให้ทั้งสอง key บน potato", "ผ่าน"),
    (12, 2, "regression: relay ด้วยมือยังใช้ได้", "หลังเปลี่ยน owner ของ LabDVN, Relay.s.sol ต้องเซ็นด้วย DVN key",
     L, "./lab-crosschain.sh potato anvil", "output:\n== anvil Ping.received: n -> n+1", "ff6c3ba", "received 2 -> 3", "ผ่าน"),
    (12, 3, "เปิด DVN worker (terminal ที่ 1)", "ยืนยัน packet อัตโนมัติ หลัง source chain ครบ confirmations",
     W, "npm run dvn",
     "[dvn] signer 0x7099…79C8, chains potato(eid 40707, 1 conf), anvil(eid 40338, 1 conf)\nข้อความเก่า: 'already delivered' (ไม่ส่ง tx)\nข้อความใหม่: 'verified on <dst> (tx …, gas 55627)'",
     "2edc869", "ข้อความเก่า 6 อัน already delivered, ping ใหม่ nonce 4 verified บน anvil", "ผ่าน"),
    (12, 4, "เปิด Executor worker (terminal ที่ 2)", "commit verification แล้วเรียก lzReceive ส่งของถึงปลายทาง",
     W, "npm run executor",
     "[executor] … nonce N: committed on <dst>\n[executor] … nonce N: delivered to 0x… (gas ~58k)", "726b003",
     "nonce 4 ที่ค้างอยู่ delivered ภายใน 8 วินาที, Ping ได้ 'dvn-only test'", "ผ่าน"),
    (12, 5, "end-to-end อัตโนมัติ ทั้งสองทาง", "goal หลักของ topic: ไม่ต้อง relay ด้วยมืออีก",
     L, "./lab-auto.sh potato anvil && ./lab-auto.sh anvil potato",
     "✅ delivered to anvil in ~10s: \"auto potato -> anvil @ …\"\n✅ delivered to potato in ~10s", "80a80a9",
     "4 รอบ: 11s, 6s, 10s, 11s", "ผ่าน"),
    (12, 6, "restart test: ส่งตอน worker ปิด", "worker ต้องตามเก็บ backlog เองหลังเปิดใหม่ ไม่หาย ไม่ซ้ำ",
     L, "pkill -f 'src/dvn.ts'; pkill -f 'src/executor.ts'; . config/dev-keys.env; for i in 1 2; do cast send $(jq -r .Ping deployments/707070.json) 'ping(uint32,string)' 40338 \"down #$i\" --rpc-url http://localhost:18545 --private-key $KEY_potato; done   # แล้วเปิด npm run dvn / npm run executor ใหม่",
     "executor: 'waiting for DVN verification' → DVN verified → executor committed → delivered ครบทุกอัน เรียงตาม nonce", "726b003",
     "3 ping (2 ทาง potato->anvil, 1 ทาง anvil->potato) delivered ครบ, nonce 7 ก่อน 8", "ผ่าน"),
    (12, 7, "พิสูจน์ bug eth_fillTransaction (เกณฑ์ข้อ 4 ของ topic 9)", "ดูว่าถ้าไม่มี workaround จะพังจริงไหม",
     W, "pkill -f 'src/dvn.ts'; WORKAROUND_GAS=0 npm run dvn   # terminal อื่น: cd lz-potato && ./lab-auto.sh anvil potato 'no workaround' 20  # เห็น ERROR แล้ว Ctrl+C ทันที แล้ว npm run dvn ตามปกติ",
     "[dvn] ERROR anvil: tx … reverted on potato (used 26750 of gas limit 26750 = out of gas)\nเปิด dvn ปกติแล้ว: verified (gas 55627) → executor delivered", "6b36b2e",
     "out of gas 26,750/26,750 บน potato (ฝั่ง anvil ผ่านปกติ) แล้วกู้คืนได้เอง", "ผ่าน"),
    (12, 8, "พิสูจน์ bug eth_getLogs fromBlock 0", "worker ต้องไม่ query จาก block 0",
     L, "./probe-getlogs-bug.sh",
     "t+1: fromBlock 0 -> N+1 logs, fromBlock 1 -> N logs (DIFFERENT <- bug)\nt+2..: same", "c69e671",
     "t+1: 43 vs 42 (DIFFERENT), t+2..4: same", "ผ่าน"),
    (12, 9, "แก้ bug ที่ต้นทาง: build potato กับ cosmos/evm ที่ patch แล้ว", "workaround ต้องใส่ทุก client (worker, web, script) แก้ที่ node ครั้งเดียวหายทุกที่",
     "potato-chain", "git switch main && make build   # branch fix/cosmos-evm-rpc-bugs merge เข้า main แล้ว",
     "applied patches/cosmos-evm/0001-rpc-getlogs-from-block-zero.patch\napplied patches/cosmos-evm/0002-rpc-filltransaction-estimate-at-latest.patch\nbuilt third_party/cosmos-evm from github.com/cosmos/evm@v0.7.3",
     "potato 817ca80, c785000, 1a3ff05", "build ผ่าน, go.sum ไม่เปลี่ยน", "ผ่าน"),
    (12, 10, "regression test ของ patch getLogs", "test ต้อง fail บนโค้ดเดิม และผ่านบนโค้ดที่ patch",
     "potato-chain", "cd third_party/cosmos-evm && go test ./rpc/namespaces/ethereum/eth/filters/",
     "ok  github.com/cosmos/evm/rpc/namespaces/ethereum/eth/filters", "potato c785000",
     "โค้ดเดิม: FAIL (heights [0 1 2 3] และ [0]) → patch แล้ว: ok", "ผ่าน"),
    (12, 11, "rebuild image + restart potato", "เปลี่ยนแค่ RPC ไม่แตะ consensus/state จึง restart บน state เดิมได้",
     S, "pkill -f 'src/(dvn|executor).ts'; docker-compose -f ../potato-chain/docker-compose.yml -f potato-localnet/ports-override.yml up -d --build",
     "ใน build log: applied ...0001... / ...0002...\nContainer potato-node0..3 Started และ Ping.received ค่าเดิม (state อยู่)", "potato 1a3ff05",
     "block เดินต่อ (8254 → 8257), potato Ping.received = 7 เท่าเดิม", "ผ่าน"),
    (12, 12, "ยืนยัน bug eth_fillTransaction หายแล้ว", "ใช้ repro เดียวกับใน known-issues.md",
     S, "D=../potato-chain/deployments/localnet.json; DATA=$(cast calldata 'approve(address,uint256)' $(jq -r .UniswapV2Router02 $D) 1000000); for m in eth_estimateGas eth_fillTransaction; do cast rpc $m \"{\\\"from\\\":\\\"0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101\\\",\\\"to\\\":\\\"$(jq -r .USDC $D)\\\",\\\"data\\\":\\\"$DATA\\\"}\" --rpc-url http://localhost:18545; done",
     "gas ของสองคำสั่งเท่ากัน (0xb4fa = 46330) — ก่อน patch fillTransaction ได้ 22490", "potato 1a3ff05",
     "estimateGas 46330, fillTransaction 46330", "ผ่าน"),
    (12, 13, "ยืนยัน bug getLogs หายแล้ว", "probe เดิมจาก step 12.8",
     L, "./probe-getlogs-bug.sh", "ทุกบรรทัด (same) รวม t+1", "potato c785000",
     "4 รอบ t+1 ทุกรอบ same (43/43, 44/44, 45/45, 46/46)", "ผ่าน"),
    (12, 14, "workers แบบไม่มี workaround บน potato ที่ patch แล้ว", "พิสูจน์ว่า client ธรรมดา (viem ไม่ใส่ gas เอง) ใช้กับ potato ได้แล้ว",
     W, "WORKAROUND_GAS=0 npm run dvn   # terminal 1\nWORKAROUND_GAS=0 npm run executor   # terminal 2\ncd ../lz-potato && ./lab-auto.sh anvil potato && ./lab-auto.sh potato anvil   # terminal 3",
     "✅ delivered ทั้งสองทาง และ log ไม่มี ERROR (เทียบ step 12.7 ที่ out of gas)", "potato 1a3ff05",
     "delivered ทั้งสองทาง (37s รวมเคลียร์ backlog, 10s), ไม่มี ERROR", "ผ่าน"),
    (13, 0, "ตรวจว่า WPOTATO คืออะไรจริงๆ", "ข้อมูลประกอบการเลือก adapter: ถ้าเป็น wrapped token จริงจะต่างจาก native",
     L, "W=0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; A=0x70997970C51812dc3A010C7d01b50e0d17dc79C8; cast balance $A --rpc-url http://localhost:18545; cast call $W 'balanceOf(address)(uint256)' $A --rpc-url http://localhost:18545; cast call $W 'totalSupply()(uint256)' --rpc-url http://localhost:18545",
     "native balance = WPOTATO balance (ตัวเลขเดียวกัน), totalSupply = supply ทั้งเชน (เพิ่มทุก block)", "76970dd",
     "10 POTATO = 10 POTATO, totalSupply 401,069 POTATO; อ่าน precompile: deposit คืนเหรียญ, withdraw แค่ emit event", "ผ่าน"),
    (13, 1, "ตัดสินใจ adapter + อ่าน ADR 0002", "business/tech decision: NativeOFTAdapter หรือ OFTAdapter(WPOTATO)",
     S, "cat docs/adr/0002-potato-native-oft-adapter.md",
     "decision = NativeOFTAdapter, invariant = locked ≥ minted", "76970dd", "เลือก NativeOFTAdapter (ตามคำแนะนำ)", "ผ่าน"),
    (13, 2, "deploy + wire POTATO bridge ทั้งสองเชน", "adapter บน home (potato), OFT บน anvil, peer + enforced options",
     L, "set -a; . config/dev-keys.env; set +a; for pass in 1 2; do for r in http://localhost:18545 http://localhost:28545; do forge script script/DeployPotatoBridge.s.sol --rpc-url $r --broadcast --slow; done; done",
     "pass 1: deployed PotatoNativeAdapter / PotatoOFT, peer pending ฝั่งแรก\npass 2: set peer ที่ค้าง แล้ว ok ทั้งหมด", "7c85929",
     "adapter 0xa1e1…D382, OFT 0xc3e5…3690, peer + enforced options ครบ", "ผ่าน"),
    (13, 3, "ตรวจ supply ก่อนโอน", "baseline ต้องเป็น 0 = 0",
     L, "./check-supply.sh", "locked 0, minted 0, ✅ locked == minted, nothing in flight", "6f5c2e4", "✅ 0 = 0", "ผ่าน"),
    (13, 4, "โอน 100 POTATO potato -> anvil", "goal: lock native บน potato แล้ว mint บน anvil",
     L, "./bridge-potato.sh potato anvil 100 && ./check-supply.sh",
     "✅ delivered … recipient on anvil 0 -> 100\nlocked 100 = minted 100 ✅", "148befd",
     "delivered 11s, locked 100 = minted 100", "ผ่าน"),
    (13, 5, "โอนกลับ anvil -> potato พร้อมเศษ (dust)", "burn บน anvil แล้ว unlock native บน potato; เศษต่ำกว่า 10^-6 ต้องไม่ข้าม",
     L, "./bridge-potato.sh anvil potato 40.123456789123456789 && ./check-supply.sh",
     "dust kept by sender: 789123456789 wei\nrecipient on potato +40.123456\nlocked 59.876544 = minted 59.876544 ✅", "148befd",
     "+40.123456 บน potato, dust 789,123,456,789 wei ค้างใน wallet, invariant ✅", "ผ่าน"),
    (13, 6, "invariant ระหว่าง message ยังไม่ถึง", "checker ต้องแยก 'ค้างระหว่างทาง (ปกติ)' ออกจาก 'mint เกิน (อันตราย)'",
     L, "./bridge-potato.sh potato anvil 5 &  sleep 3; ./check-supply.sh | tail -2; wait; ./check-supply.sh | tail -1",
     "ระหว่างทาง: ⏳ locked - minted = 5 with 1 message(s) in flight\nหลังถึง: ✅ locked == minted", "6f5c2e4",
     "⏳ 5 POTATO, 1 in flight → ✅ 64.876544 = 64.876544", "ผ่าน"),
    (13, 7, "negative test: msg.value ต้องพอดี", "NativeOFTAdapter รับเฉพาะ fee + amount (ตัด dust) เท่านั้น",
     L, "L=$(jq -r .POTATO deployments/707070.json); TO=$(cast abi-encode 'f(address)' 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266); cast call $L 'send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)' \"(40338,$TO,1000000000000000000,1000000000000000000,0x,0x,0x)\" '(0,0)' 0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101 --value 1000000000000000001 --from 0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101 --rpc-url http://localhost:18545",
     "execution reverted: IncorrectMessageValue(1000000000000000001, 1000000000000000000)", "148befd",
     "1e18 พอดี = ผ่าน, 1e18+1 = IncorrectMessageValue", "ผ่าน"),
    (13, 8, "(ยังไม่ทดสอบ) ผู้รับที่รับ native ไม่ได้", "NativeOFTAdapter จ่ายด้วย call{value} ถ้าผู้รับเป็น contract ไม่มี receive() → CreditFailed",
     L, "(ไม่ได้รัน) จะทำให้ message ค้างถาวรใน lab และ check-supply ขึ้น ⏳ ตลอด",
     "—", "—", "ตั้งใจไม่ทดสอบบนเชนจริง เพราะ message ค้างถาวร ต้องทดสอบใน unit test ก่อน (งานค้าง)", "ยังไม่ทำ"),
]
RERUN = {
    (9, 0): ("ได้", "มีผลแค่ terminal นั้น เปิด terminal ใหม่ต้องรันใหม่ (หรือใส่บรรทัด export ใน ~/.zshrc ถาวร)"),
    (9, 1): ("ได้", "อ่านอย่างเดียว ไม่เปลี่ยนอะไร"),
    (9, 2): ("ได้", "ถ้า image ไม่เปลี่ยนจะไม่มีอะไรเกิดขึ้น ถ้าโค้ด potato เปลี่ยนจะ rebuild และ restart node แต่ state ของเชนยังอยู่ (.localnet). ห้ามใช้ 'make localnet-up' แทน เพราะจะชน port 8545 กับ anvil เดิม และห้ามรัน 'make localnet-init' เพราะจะล้างเชน ทำให้ address ใน deployments/707070.json ใช้ไม่ได้"),
    (9, 3): ("ได้", "อ่านอย่างเดียว block number จะเพิ่มทุกครั้ง"),
    (9, 4): ("ได้", "npm ci ลบ node_modules แล้วติดตั้งใหม่ตาม package-lock.json ได้เวอร์ชันเดิมทุกครั้ง แค่ใช้เวลาและเน็ต"),
    (9, 5): ("ได้", "อ่านอย่างเดียว"),
    (9, 6): ("ได้", "git checkout <hash> ทำให้อยู่ในสถานะ detached HEAD ต้อง 'git checkout main' กลับ ถ้ามีไฟล์แก้ค้างอยู่ git อาจไม่ยอม checkout ให้ commit หรือ stash ก่อน. forge build รันซ้ำได้ ไม่มีผลข้างเคียง"),
    (9, 7): ("ได้", "เหมือน step 6"),
    (9, 8): ("ได้", "เหมือน step 6"),
    (9, 9): ("ได้ (ทีละตัว)", "ตั้งแต่ topic 10 ให้ใช้ potato-localnet/anvil-home.sh แทน (port เดียวกัน แต่เก็บ state) ถ้า anvil-home รันอยู่ คำสั่งนี้จะ error 'address in use'. ถ้ามี anvil :28545 รันอยู่แล้ว ตัวที่สองจะ error 'address in use'. ปิดแล้วเปิดใหม่ = state ใน anvil หายหมด address ใน deployments/31338.json ใช้ไม่ได้ (ไม่กระทบอะไร เพราะ step 10 deploy ใหม่ทุกครั้ง)"),
    (9, 10): ("ได้", "ทุกครั้ง deploy LayerZero ชุดใหม่ (address ใหม่) และเขียนทับ deployments/31338.json ชุดเก่ายังอยู่บน anvil แต่ไม่มีใครใช้ ไม่เสียหาย"),
    (9, 11): ("ได้ (มีผลข้างเคียง)", "potato เก็บ state ถาวร ทุกครั้งจะ deploy ชุดใหม่ ใช้ gas ของ dev0 (ยังเหลือ ~498 POTATO) และเขียนทับ deployments/707070.json ซึ่ง commit ไว้แล้ว → git จะเห็นไฟล์เปลี่ยน ต้องเลือกว่าจะ commit address ชุดใหม่ หรือ 'git checkout -- deployments/707070.json' คืน. ถ้ารัน script/Relay.s.sol ซ้ำด้วย PAYLOAD เดิม tx จะ revert (packet ถูกส่งไปแล้ว) ไม่เสียหาย แค่เสีย gas"),
    (9, 12): ("ได้", "อ่านอย่างเดียว ใช้ endpoint จาก deployments/707070.json ถ้ารัน step 11 ใหม่ ให้เปลี่ยน --from-block เป็นค่า 'start block' ใน output รอบใหม่"),
    (9, 13): ("ได้", "อ่านอย่างเดียว อ่านจากรอบล่าสุด (run-latest.json) ตัวเลขจะเป็นของรอบที่รันล่าสุด"),
    (9, 14): ("ได้", "อ่านอย่างเดียว ตัวเลขแกว่งได้เล็กน้อย"),
    (9, 15): ("ได้", "อ่านอย่างเดียว"),
    (9, 16): ("ได้", "อ่านอย่างเดียว"),
    (9, 17): ("ได้", "potato หยุดผลิต block แต่ state ยังอยู่ (.localnet) เปิดใหม่ด้วย step 2 แล้ว address เดิมยังใช้ได้. anvil :28545 (ตั้งแต่ topic 10 คือ anvil-home) จะ dump state ลงไฟล์ก่อนปิด ไม่หาย. ถ้าไม่มีอะไรรันอยู่ pkill จะคืน exit code 1 ไม่เป็นไร. ไม่กระทบ anvil :8545 ตัวเดิม"),
    (10, 0): ("ไม่ต้องรัน", "เป็นการตัดสินใจ ถ้าจะเปลี่ยนต้องเขียน ADR ใหม่ (0002) มาแทน แล้วแก้ config/topology.json"),
    (10, 1): ("ได้", "ส่ง SIGTERM ให้ anvil :28545 ถ้าเป็น anvil-home จะ dump state ก่อนปิด ไม่หาย ถ้าไม่มีอะไรรันอยู่จะคืน exit code 1 ไม่เป็นไร ไม่กระทบ anvil :8545 ตัวเดิม"),
    (10, 2): ("ได้", "ถ้ารันอยู่แล้วจะขึ้น 'anvil :28545 already running' แล้วจบ ไม่เปิดซ้อน ถ้าปิดอยู่จะเปิดใหม่ด้วย state เดิม. ห้ามลบ potato-localnet/anvil-home-state.json = USDC หายทั้งระบบ"),
    (10, 3): ("ได้ (มีผลข้างเคียง)", "ทุกครั้งโอน ETH ทดสอบ 1 ETH ไป address 0x…dEaD (เงินทดสอบ ไม่มีมูลค่า) และ restart anvil สั้นๆ ระหว่างนั้น RPC :28545 ใช้ไม่ได้ ~3 วินาที"),
    (10, 4): ("ได้", "อ่านอย่างเดียว"),
    (10, 5): ("ได้", "อ่านอย่างเดียว ต้องเปิดทั้ง potato (:18545) และ anvil-home (:28545) ก่อน ไม่งั้นจะขึ้น ❌ RPC not reachable"),
    (10, 6): ("ได้", "อ่านอย่างเดียว เขียนไฟล์ทดสอบที่ /tmp/bad-topology.json เท่านั้น ไม่แตะ config จริง"),
    (11, 0): ("ได้", "อ่านอย่างเดียว. set -a ... ใส่ key ลง env ของ terminal นั้นเท่านั้น"),
    (11, 1): ("ได้", "รันซ้ำ = reused ทั้งหมด ไม่มี tx. ถ้า anvil ถูกล้าง state (ลบ anvil-home-state.json) script จะเห็นว่าไม่มี code แล้ว deploy ใหม่ + เขียนทับ deployments/31338.json (address ใหม่ ต้อง wire ใหม่ทั้งหมด)"),
    (11, 2): ("ได้", "เหมือน 11.1 สำหรับ potato"),
    (11, 3): ("ได้", "ค่าที่ตรงแล้วจะ skip (endpoint revert ถ้าตั้งค่าเดิมซ้ำ script จึงเช็คก่อน). ถ้าแก้ confirmations ใน topology.json แล้วรัน = อัปเดต config บนเชนจริง"),
    (11, 4): ("ได้", "อ่านอย่างเดียว"),
    (11, 5): ("ได้ (มีผลข้างเคียง)", "แก้ deployments/31338.json ชั่วคราว ถ้าหยุดกลางคัน (Ctrl+C) ไฟล์จะค้างค่าผิด → ให้ 'git checkout -- deployments/31338.json' คืน"),
    (11, 6): ("ได้ (มีผลข้างเคียง)", "ทุกครั้งส่ง message ใหม่จริงบนสองเชน (nonce +1) ใช้ gas ทดสอบเล็กน้อย. ส่วน deploy/peer ใน script รันซ้ำแล้วไม่มี tx. ถ้า script ตายหลัง 'sent' แต่ก่อน relay → message ค้าง (outbound > inbound) ต้อง relay เอง (ดู step 11.8) ไม่ใช่ส่งใหม่"),
    (11, 7): ("ได้ (มีผลข้างเคียง)", "เหมือน 11.6 ทางกลับ"),
    (11, 8): ("ได้", "อ่านอย่างเดียว"),
    (11, 9): ("ได้ (มีผลข้างเคียง)", "ถ้า RPC ตอบปกติจะไม่ทำอะไร. ถ้าค้าง: kill -9 แล้ว state ย้อนกลับไป dump ล่าสุด (≤10 วินาที) tx ที่อยู่ในช่วงนั้นหาย ต้องตรวจ nonce (11.8) ถ้า outbound ฝั่ง anvil ลดลงแต่อีกฝั่งรับไปแล้ว = state สองเชนไม่ตรงกัน ต้องแจ้งก่อนทำต่อ"),
    (12, 0): ("ได้", "npm ci ลบ node_modules แล้วติดตั้งตาม lockfile ใหม่"),
    (12, 1): ("ได้", "รันซ้ำไม่ทำอะไร (owner ถูกแล้ว / balance ≥ 5). ข้อสังเกต: หลัง step นี้ LabDVN.verify ใช้ได้เฉพาะ DVN key → script เก่าที่ใช้ key deployer จะ revert"),
    (12, 2): ("ได้ (มีผลข้างเคียง)", "เหมือน 11.6: ส่ง message ใหม่จริง. ถ้า worker เปิดอยู่ worker กับ script อาจแย่งกัน verify/commit ตัวที่ช้ากว่าจะ revert (ไม่เสียหาย แค่เสีย gas)"),
    (12, 3): ("ได้ (ทีละตัว)", "เปิดซ้อน 2 ตัว = verify packet เดียวกันซ้ำ ตัวที่สองเสีย gas เปล่า. ปิดด้วย Ctrl+C. ลบ workers/state/dvn.json = สแกนใหม่ตั้งแต่ block 1 (ปลอดภัย เพราะเช็ค state บนเชนก่อนทุกครั้ง แค่ช้า)"),
    (12, 4): ("ได้ (ทีละตัว)", "เหมือน 12.3 สำหรับ workers/state/executor.json"),
    (12, 5): ("ได้ (มีผลข้างเคียง)", "ทุกครั้งส่ง message ใหม่ (nonce +1) ถ้า worker ไม่ได้เปิดจะขึ้น ❌ not delivered แต่ message ยังอยู่ จะถูกส่งเมื่อเปิด worker"),
    (12, 6): ("ได้ (มีผลข้างเคียง)", "ส่ง message ใหม่ + ต้องจำเปิด worker กลับ ไม่งั้น message ค้าง"),
    (12, 7): ("ได้ (มีผลข้างเคียง)", "ระหว่างปิด workaround DVN จะ retry ทุก 2 วินาที แต่ละครั้งเสีย gas บน potato (~26,750) → Ctrl+C ทันทีที่เห็น ERROR ห้ามทิ้งไว้"),
    (12, 8): ("ได้ (มีผลข้างเคียง)", "ส่ง ping 1 อัน (worker จะ deliver ให้). bug เห็นแค่ ~1 block หลัง tx บางรอบอาจเห็น same ทุกบรรทัด ให้รันใหม่"),
    (12, 9): ("ได้", "build ซ้ำจะไม่สร้าง third_party ใหม่ถ้า patch ไม่เปลี่ยน (เช็คด้วย hash). ถ้า switch กลับ main แล้ว build = ได้ binary ที่มี bug เดิม"),
    (12, 10): ("ได้", "อ่านอย่างเดียว"),
    (12, 11): ("ได้ (มีผลข้างเคียง)", "เชนหยุดหลายวินาทีระหว่าง restart; worker จะขึ้น ERROR ระหว่างนั้น (ปิดก่อนตามคำสั่ง แล้วเปิดใหม่หลังเสร็จ). build ครั้งแรกนานหลายนาที"),
    (12, 12): ("ได้", "อ่านอย่างเดียว (fillTransaction ไม่ส่ง tx)"),
    (12, 13): ("ได้ (มีผลข้างเคียง)", "ส่ง ping 1 อันต่อรอบ (worker deliver ให้)"),
    (12, 14): ("ได้ (มีผลข้างเคียง)", "ส่ง message ใหม่. ถ้าไปรันกับ potato ที่ยังไม่ patch จะ out of gas ซ้ำทุก 2 วินาที (ดู 12.7) — เปิด workaround ไว้เป็นค่า default"),
    (13, 0): ("ได้", "อ่านอย่างเดียว totalSupply เพิ่มทุก block"),
    (13, 1): ("ไม่ต้องรัน", "เป็นการตัดสินใจ ถ้าจะเปลี่ยนต้องมี ADR ใหม่ และต้องย้ายเหรียญที่ lock อยู่ใน adapter เดิมก่อน"),
    (13, 2): ("ได้", "รันซ้ำไม่มี tx (reused / ok). ถ้า anvil ถูกล้าง state จะ deploy PotatoOFT ใหม่ แต่ adapter บน potato ยังถือ POTATO เดิมอยู่ → invariant พัง (locked > minted ถาวร)"),
    (13, 3): ("ได้", "อ่านอย่างเดียว"),
    (13, 4): ("ได้ (มีผลข้างเคียง)", "ย้าย POTATO จริงของ dev0 ไป lock (ยังเป็นของเราบน anvil). ต้องเปิด worker ไว้ ไม่งั้นขึ้น ❌ not delivered แต่ message ยังอยู่และจะถึงเมื่อเปิด worker"),
    (13, 5): ("ได้ (มีผลข้างเคียง)", "เหมือน 13.4 ทางกลับ ต้องมี POTATO บน anvil พอ (ไม่งั้น revert ตอน burn)"),
    (13, 6): ("ได้ (มีผลข้างเคียง)", "เหมือน 13.4. บางรอบ message อาจถึงก่อน check ทัน จะเห็น ✅ เลย ให้รันใหม่"),
    (13, 7): ("ได้", "cast call = จำลอง ไม่ส่ง tx ไม่เสียอะไร"),
    (13, 8): ("—", "ยังไม่ได้รัน"),
}
rows = [[t, n, what, why, cwd, cmd, expect, commit, actual, status, *RERUN[(t, n)]]
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
    ("0804013", "docs: workshop runbook xlsx for topic 9", "workshop-layerzero.xlsx", "—", "— (เอกสาร)"),
    ("e59714c", "docs: fit xlsx row heights and fix '=' text read as formula", "workshop-layerzero.xlsx", "—", "— (เอกสาร)"),
    ("a0679cf", "chore: persistent anvil as the USDC home chain", ".gitignore, potato-localnet/anvil-home.sh", "10.2–10.3", "— (shell script)"),
    ("997572d", "docs: ADR 0001 counterpart chain and home chains", "docs/adr/0001-counterpart-chain-and-home-chains.md", "10.0, 10.4", "— (เอกสาร)"),
    ("6dc991b", "feat(lz-potato): topology config and live checker", "lz-potato/config/topology.json, lz-potato/check-topology.sh", "10.5–10.6", "check-topology.sh ผ่าน"),
    ("f19681f", "build: keep the workshop xlsx generator in the repo", "tools/workshop_xlsx.py, .gitignore", "—", "สร้าง xlsx ได้"),
    ("8933d8d", "docs: topic 10 steps in the workshop runbook", "tools/workshop_xlsx.py, workshop-layerzero.xlsx", "—", "สร้าง xlsx ได้"),
    ("acd3612", "feat(lz-potato): re-runnable protocol deploy from topology", "script/LabBase.s.sol, script/DeployProtocol.s.sol, config/dev-keys.env, foundry.toml, deployments/31338.json", "11.0–11.2", "forge build ผ่าน"),
    ("a51a20b", "feat(lz-potato): re-runnable default pathway wiring", "script/WireProtocol.s.sol", "11.3", "forge build ผ่าน"),
    ("7dcc37b", "feat(lz-potato): check-wiring reads pathway config back with cast", "check-wiring.sh", "11.4–11.5", "check-wiring.sh ผ่าน"),
    ("eec40d7", "feat(lz-potato): cross-chain ping potato <-> anvil with manual relay", "script/DeployPing.s.sol, lab-crosschain.sh, deployments/*.json", "11.6–11.8", "forge build ผ่าน"),
    ("d638f4b", "fix(lz-potato): avoid broken pipe when decoding PacketSent", "lab-loopback.sh", "9.10–9.11", "—"),
    ("fbdc858", "docs: topic 11 steps in the workshop runbook", "tools/workshop_xlsx.py, workshop-layerzero.xlsx", "—", "สร้าง xlsx ได้"),
    ("20d111f", "feat(workers): shared lib for lab DVN/executor", "workers/package.json, tsconfig.json, src/lib.ts, src/lib.test.ts", "12.0", "npm test + typecheck ผ่าน"),
    ("ff6c3ba", "feat(lz-potato): separate DVN and executor keys", "config/dev-keys.env, setup-worker-keys.sh, lab-crosschain.sh", "12.1–12.2", "— (shell)"),
    ("2edc869", "feat(workers): lab DVN worker", "workers/src/dvn.ts, src/lib.ts", "12.3", "typecheck ผ่าน"),
    ("726b003", "feat(workers): lab executor worker", "workers/src/executor.ts", "12.4, 12.6", "typecheck ผ่าน"),
    ("80a80a9", "feat(lz-potato): lab-auto.sh sends a ping and waits for the workers", "lab-auto.sh", "12.5", "— (shell)"),
    ("6b36b2e", "fix(workers): say when a reverted tx ran out of gas", "workers/src/lib.ts", "12.7", "npm test + typecheck ผ่าน"),
    ("c69e671", "feat(lz-potato): probe for the cosmos/evm getLogs fromBlock 0 bug", "probe-getlogs-bug.sh", "12.8", "— (shell)"),
    ("27fed02", "docs: topic 12 steps in the workshop runbook", "tools/workshop_xlsx.py, workshop-layerzero.xlsx", "—", "สร้าง xlsx ได้"),
    ("potato 817ca80", "build: build against a locally patched cosmos/evm  [repo potato-chain, merged to main (ff)]", "scripts/patch_deps.sh, go.mod, Makefile, Dockerfile, .gitignore, .dockerignore", "12.9", "make build ผ่าน (binary เดิม)"),
    ("potato c785000", "fix(rpc): eth_getLogs fromBlock 0 no longer duplicates tip logs", "patches/cosmos-evm/0001-rpc-getlogs-from-block-zero.patch", "12.9–12.10, 12.13", "go test filters ผ่าน"),
    ("potato 1a3ff05", "fix(rpc): eth_fillTransaction estimates gas at the latest block", "patches/cosmos-evm/0002-rpc-filltransaction-estimate-at-latest.patch", "12.11–12.12, 12.14", "make build + docker build ผ่าน"),
    ("potato bf45eb4", "docs: mark both cosmos/evm RPC known issues fixed by local patches", "docs/known-issues.md", "—", "— (เอกสาร)"),
    ("5043435", "docs(lz-potato): probe comment for patched potato", "lz-potato/probe-getlogs-bug.sh", "12.13", "— (shell)"),
    ("73a0247", "docs: potato patch steps (12.9-12.14) in the runbook", "tools/workshop_xlsx.py, workshop-layerzero.xlsx", "—", "สร้าง xlsx ได้"),
    ("76970dd", "docs: ADR 0002 lock POTATO with NativeOFTAdapter", "docs/adr/0002-potato-native-oft-adapter.md, config/topology.json", "13.0–13.1", "check-topology ผ่าน"),
    ("f3c8578", "feat(lz-potato): PotatoNativeAdapter and PotatoOFT", "src/token/PotatoNativeAdapter.sol, src/token/PotatoOFT.sol", "13.2", "forge build ผ่าน"),
    ("7c85929", "feat(lz-potato): deploy and wire the POTATO bridge from topology", "script/DeployPotatoBridge.s.sol, deployments/*.json", "13.2", "forge build ผ่าน"),
    ("6f5c2e4", "feat(lz-potato): check-supply.sh for the bridge supply invariant", "check-supply.sh", "13.3, 13.6", "— (shell)"),
    ("148befd", "feat(lz-potato): bridge-potato.sh sends POTATO through the OFT legs", "bridge-potato.sh", "13.4–13.7", "— (shell)"),
    ("(commit นี้)", "docs: topic 13 steps in the workshop runbook", "tools/workshop_xlsx.py, workshop-layerzero.xlsx", "—", "สร้าง xlsx ได้"),
]
table(cm, ["Commit", "Message", "ไฟล์", "ใช้ใน step", "ตรวจแล้วว่า build ได้ลำพัง"],
      [list(c) for c in commits], {"A": 10, "B": 52, "C": 58, "D": 12, "E": 30}, mono_cols=("A",))
r = cm.max_row + 2
cm.cell(r, 1, "Small batch (Accelerate)").font = BOLD
for k, t in enumerate([
    "1 commit = 1 การเปลี่ยนแปลงที่ทำงานได้เอง และ build ผ่านลำพัง (ตรวจทีละ commit ด้วย git worktree แล้ว)",
    "ลำดับ commit = ลำดับ step ของ workshop → git checkout <commit> แล้วทำตาม step ได้",
    "หมายเหตุ: repo นี้ git init หลังทำงานเสร็จ commit จึงแบ่งย้อนหลังตาม step ไม่ใช่ commit ระหว่างทำจริง ตั้งแต่ topic 10 commit ทันทีทีละ step ระหว่างทำจริง",
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
