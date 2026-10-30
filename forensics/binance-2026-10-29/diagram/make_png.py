# Render the EIP-7702 delegation/sweep stepper (8 steps) to PNG with headless Chrome:
# step-1.png .. step-8.png and all-steps.png.   python3 make_png.py
import html, os, subprocess, tempfile

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT = os.path.dirname(os.path.abspath(__file__))
B = {"fill": "#E1F5EE", "stroke": "#0F6E56", "t": "#085041", "s": "#0F6E56"}   # Binance (teal)
A = {"fill": "#FAECE7", "stroke": "#993C1D", "t": "#712B13", "s": "#993C1D"}   # attacker (coral)
NODES = {  # id: (x, y, w, h, colors, title, subtitle)
    "att": (30, 30, 150, 56, A, "โจร", "0x7c86…5ca0"),
    "x": (30, 200, 150, 56, A, "Contract X", "มีฟังก์ชัน sweep"),
    "sign": (250, 16, 190, 48, B, "ระบบเซ็นของ Binance", "ถือ key ของ B14"),
    "b14": (250, 108, 190, 84, B, "Binance 14", None),
    "sw": (500, 30, 150, 56, B, "Smart wallet", "รับคำสั่งจาก B14"),
    "exp": (500, 200, 150, 56, A, "Exploiter 2", None),
}
ARROWS = {"own": ("M345 64 L345 106", "#1D9E75", 1.6, False), "deploy": ("M105 86 L105 198", "#D85A30", 1.6, False),
          "sign": ("M250 40 L182 52", "#BA7517", 1.6, True), "send": ("M180 74 L248 124", "#D85A30", 2.2, False),
          "ptr": ("M250 176 L182 216", "#D85A30", 1.6, True), "sweep": ("M440 176 L498 216", "#D85A30", 2.8, False),
          "exec": ("M440 124 L498 70", "#D85A30", 2.2, False), "usdc": ("M575 86 L575 198", "#D85A30", 2.2, False)}
STEPS = [
    ("ก่อนเกิดเหตุ", "ปกติ: Binance 14 เป็นกระเป๋าธรรมดา", "code ของ Binance 14 คือ 0x ไม่มีโค้ด ทำงานได้เมื่อระบบเซ็นของ Binance เซ็น tx ให้เท่านั้น และ smart wallet อีกใบตั้งไว้ว่าเชื่อคำสั่งจาก Binance 14", ["sign", "b14", "sw"], ["own"], "code: 0x (กระเป๋าธรรมดา)", "167,465 ETH · 1.6B USDT", "ว่าง"),
    ("29 ต.ค. 15:59", "1. โจรสร้าง contract X เอง", "โจร deploy X ที่มีฟังก์ชัน sweep (โอนเงินทั้งหมดออก) X เป็นของโจรล้วนๆ Binance ไม่เคยรู้จัก", ["att", "x"], ["deploy"], "code: 0x (กระเป๋าธรรมดา)", "167,465 ETH · 1.6B USDT", "ว่าง"),
    ("ก่อน 20:20 (ไม่รู้เวลา)", "2. โจรได้ลายเซ็นใบอนุญาต 50 ใบ", "ใบอนุญาตเขียนว่า 'ให้ Binance 14 ใช้โค้ดของ X' และเซ็นด้วย key จริงของ Binance 14 ส่วนว่าโจรได้มาจากระบบเซ็นได้ยังไง ยังไม่มีใครรู้", ["sign", "att"], ["sign"], "code: 0x (กระเป๋าธรรมดา)", "167,465 ETH · 1.6B USDT", "ว่าง"),
    ("20:20:59", "3. ส่งใบอนุญาตขึ้นเชน: เปลี่ยนสมอง", "โจรส่ง tx type 4 พร้อมใบอนุญาตไปที่ Binance 14 ตอนนี้ code ของ Binance 14 กลายเป็นตัวชี้ไปหา X แต่ยังไม่มีเงินขยับ", ["att", "b14", "x"], ["send", "ptr"], "code: → ชี้ไปที่ X", "167,465 ETH · 1.6B USDT", "ว่าง"),
    ("20:21 – 20:24", "4. ช่วง 3 นาทีที่ไม่มีใครรู้", "Binance ยังเซ็น tx ของตัวเองส่งออกจาก Binance 14 ได้ตามปกติ เพราะ tx ที่ Binance 14 ส่งเองไม่ได้รันโค้ดของ X โค้ดของ X จะรันเฉพาะตอนมีคนเรียกเข้ามาหา Binance 14", ["sign", "b14", "x"], ["own", "ptr"], "code: → ชี้ไปที่ X", "167,465 ETH · 1.6B USDT", "ว่าง"),
    ("20:24:23", "5. โจรกดปุ่ม sweep", "โจรส่ง tx ไปที่ address ของ Binance 14 พร้อมคำสั่ง sweep EVM เห็นตัวชี้ เลยรันโค้ดของ X ในฐานะ Binance 14 ใช้เงินของ Binance 14 เงินจึงไหลออกทั้งหมดใน tx เดียว", ["att", "b14", "x", "exp"], ["send", "ptr", "sweep"], "code: → ชี้ไปที่ X", "1 ETH · 0 USDT", "167,464 ETH + 63 เหรียญ"),
    ("20:41 และ 20:59", "6. สั่ง smart wallet ในชื่อ Binance 14", "โจรเรียก callExecute ที่ Binance 14 โค้ดของ X สั่ง smart wallet ให้โอน USDC smart wallet เห็นว่าคนสั่งคือ Binance 14 ซึ่งมีสิทธิ์อยู่แล้ว จึงโอน USDC 823 ล้านให้", ["att", "b14", "sw", "exp"], ["send", "exec", "usdc"], "code: → ชี้ไปที่ X", "1 ETH · 0 USDT", "+ USDC 823M"),
    ("30 ต.ค. 00:10:35", "7. Binance ถอนตัวชี้ออก", "หลังผ่านไป 226 นาที (ระหว่างนั้นโจรกวาดซ้ำอีก 9 รอบ) Binance เซ็นใบอนุญาตใหม่ให้ชี้ไปที่ 0x0 code กลับเป็น 0x และโจรกดปุ่มไม่ได้อีก", ["sign", "b14"], ["own"], "code: 0x (กลับเป็นปกติ)", "เงินออกไปแล้ว", "ถูกแช่แข็งบางส่วน"),
]
FONT = "'Sukhumvit Set', 'Thonburi', sans-serif"
e = html.escape


def svg(step):
    _, _, _, on, arrows, code, bal, exp = step
    out = ['<svg width="680" height="290" viewBox="0 0 680 290" xmlns="http://www.w3.org/2000/svg"><defs>'
           '<marker id="ah" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">'
           '<path d="M2 1L8 5L2 9" fill="none" stroke="context-stroke" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></marker></defs>']
    for nid, (x, y, w, h, c, title, sub) in NODES.items():
        op = 1 if nid in on else 0.28
        out.append(f'<g opacity="{op}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{c["fill"]}" stroke="{c["stroke"]}" stroke-width="0.8"/>')
        cx = x + w / 2
        if nid == "b14":
            out.append(f'<text x="{cx}" y="{y+22}" text-anchor="middle" dominant-baseline="central" font-size="14" font-weight="600" fill="{c["t"]}">{e(title)}</text>'
                       f'<text x="{cx}" y="{y+43}" text-anchor="middle" dominant-baseline="central" font-size="12" fill="{c["s"]}">{e(code)}</text>'
                       f'<text x="{cx}" y="{y+64}" text-anchor="middle" dominant-baseline="central" font-size="12" fill="{c["s"]}">{e(bal)}</text></g>')
        else:
            sub = exp if nid == "exp" else sub
            out.append(f'<text x="{cx}" y="{y+h/2-9}" text-anchor="middle" dominant-baseline="central" font-size="14" font-weight="600" fill="{c["t"]}">{e(title)}</text>'
                       f'<text x="{cx}" y="{y+h/2+9}" text-anchor="middle" dominant-baseline="central" font-size="12" fill="{c["s"]}">{e(sub)}</text></g>')
    for aid in arrows:
        d, col, wdt, dash = ARROWS[aid]
        out.append(f'<path d="{d}" stroke="{col}" stroke-width="{wdt}" fill="none" marker-end="url(#ah)"{" stroke-dasharray=\"5 4\"" if dash else ""}/>')
    out.append("</svg>")
    return "".join(out)


def panel(i, step):
    w, h, b = step[:3]
    return (f'<div class="panel">{svg(step)}<div class="cap"><div class="when">{e(w)} · ขั้น {i+1}/{len(STEPS)}</div>'
            f'<div class="head">{e(h)}</div><div class="body">{e(b)}</div></div></div>')


CSS = (f"body{{margin:0;background:#ffffff;font-family:{FONT};color:#1f1d1a}}"
       ".panel{width:680px;padding:16px;background:#fff}"
       ".cap{background:#f4f2ec;border-radius:8px;padding:12px 14px;margin-top:6px;min-height:92px}"
       ".when{font-size:12px;color:#8a867c}.head{font-size:16px;font-weight:600;margin:2px 0 4px}"
       ".body{font-size:14px;color:#5b574e;line-height:1.6}"
       ".legend{font-size:12px;color:#5b574e;margin:6px 16px 0}.legend span{margin-right:14px}"
       ".sw{display:inline-block;width:10px;height:10px;border-radius:2px;vertical-align:-1px;margin-right:4px}"
       ".grid{display:grid;grid-template-columns:712px 712px;gap:0;background:#fff}"
       "h1{font-size:20px;margin:18px 16px 0}")
LEGEND = ('<div class="legend"><span><i class="sw" style="background:#E1F5EE;border:1px solid #0F6E56"></i>ของ Binance</span>'
          '<span><i class="sw" style="background:#FAECE7;border:1px solid #993C1D"></i>ของโจร</span></div>')


def shoot(body, name, width, height):
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(f"<!doctype html><html><head><meta charset='utf-8'><style>{CSS}</style></head><body>{body}</body></html>")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=2",
                    f"--window-size={width},{height}", f"--screenshot={os.path.join(OUT, name)}", "file://" + f.name],
                   capture_output=True)
    os.unlink(f.name)
    print("wrote", name)


for i, s in enumerate(STEPS):
    shoot(LEGEND + panel(i, s), f"step-{i+1}.png", 712, 470)
shoot('<h1>Binance 14 ถูกกวาดด้วย EIP-7702: ทีละขั้น</h1>' + LEGEND + '<div class="grid">' + "".join(panel(i, s) for i, s in enumerate(STEPS)) + "</div>",
      "all-steps.png", 1424, 1890)
