# Thai narration for eip7702-delegation.mp4, cut at the same points where the on-screen caption changes.
#   python3 make_narration.py -> narration-th.md (script with timecodes) + narration-th.srt (subtitles)
import pathlib, re

HERE = pathlib.Path(__file__).resolve().parent
SLOW = float(re.search(r"const SLOW = ([\d.]+)", (HERE / "eip7702-anim.html").read_text()).group(1))
DUR = [8, 11, 11, 10, 10, 20, 9, 9, 16, 14, 12]          # scene lengths before SLOW, as in eip7702-anim.html
SCENE = ["ตัวละครบนเชน", "ขั้น 1 สร้างข้อความ", "ขั้น 2 เซ็น 50 ใบ", "ขั้น 3 tx type 4", "ขั้น 4 เข้า block",
         "ขั้น 5 เชนตรวจทีละใบ", "ผลลัพธ์", "ระหว่างนั้น", "ขั้น 6 sweep", "ยกเลิก", "สรุป"]
# (scene, start as fraction of the scene = caption threshold in the html, narration)
LINES = [
    (0, 0, "นี่คือ Binance 14 กระเป๋าร้อนของ Binance เป็นกระเป๋าธรรมดาที่ไม่มีโค้ด เงินขยับได้เมื่อ Binance เซ็นเท่านั้น ส่วนทางขวาคือโจร ที่ deploy contract X ซึ่งมีฟังก์ชันโอนเงินออกทั้งหมด"),
    (1, 0, "ขั้นแรก สร้างใบอนุญาต ใบหนึ่งมีแค่สามช่อง คือเชนไหน ให้ใช้โค้ดของ contract ตัวไหน และ nonce ของกระเป๋าตอนที่ใบจะถูกใช้"),
    (1, .55, "เอาสามช่องนี้ต่อท้าย 0x05 แล้ว hash ได้ข้อความที่จะเซ็น สังเกตว่าไม่มีวงเงิน และไม่มีวันหมดอายุ"),
    (2, 0, "จากนั้น key ของ Binance 14 เซ็นข้อความนี้ ได้ลายเซ็นติดไปกับใบ"),
    (2, .45, "แต่ไม่ได้เซ็นแค่ใบเดียว เซ็นห้าสิบใบ ไล่ nonce เผื่อไว้ เพราะกระเป๋านี้ส่ง tx แทบทุกบล็อก"),
    (2, .85, "ตอนนี้ทุกอย่างยังอยู่นอกเชน"),
    (3, 0, "ขั้นที่สาม โจรเอาใบทั้งห้าสิบใส่ใน tx แบบ type 4 โจรเป็นคนส่ง และจ่ายค่า gas เอง เพราะ EIP-7702 ไม่สนว่าใครส่ง ขอแค่ลายเซ็นในใบถูกต้อง แถมยังตั้งค่า priority fee ไว้สูง ให้ tx เข้าบล็อกเร็วที่สุด"),
    (4, 0, "tx เข้าบล็อก ในบล็อกเดียวกันนี้ Binance 14 ส่ง tx ของตัวเองก่อน nonce จึงขยับไปเป็นเลขที่ลงท้ายสี่แปดศูนย์เก้า"),
    (4, .55, "แล้วก็ถึงคิว tx ของโจร nonce ตอนนี้ตรงกับใบหนึ่งในห้าสิบใบพอดี"),
    (5, 0, "เชนตรวจใบทีละใบ สี่ข้อ เชนถูกไหม ลายเซ็นเป็นของ Binance 14 ไหม กระเป๋ายังว่างไหม และ nonce ตรงไหม ใบแรกๆ nonce สูงกว่า เลยตกข้อสี่ แค่ถูกข้ามไป tx ไม่ล้ม"),
    (5, .45, "พอถึงใบสี่แปดศูนย์เก้า ผ่านครบสี่ข้อ เชนเขียนโค้ดให้กระเป๋าชี้ไปที่ X แล้วเพิ่ม nonce"),
    (5, .66, "ใบที่เหลือ nonce ต่ำกว่า เลยถูกข้ามหมด ส่วนใบสี่แปดหนึ่งศูนย์ ถูกตรวจผ่านไปก่อนแล้ว"),
    (5, .9, "สรุปใช้ไปใบเดียว ที่เหลือคือใบสำรอง"),
    (6, 0, "ผลคือโค้ดของ Binance 14 กลายเป็น 0xef0100 ตามด้วย address ของ X แปลว่าให้ไปใช้โค้ดที่ X ตรงนี้เงินยังไม่ขยับเลย กระเป๋าแค่ชี้ไปที่โค้ดของโจร รอคนมาเรียก"),
    (7, 0, "ระหว่างนั้น Binance ยังส่ง tx จากกระเป๋านี้ได้ตามปกติ เพราะ tx ที่กระเป๋าส่งเองไม่รันโค้ดของ X เงินฝากยังไหลเข้า ไม่มีใครรู้ตัว อยู่สามนาทียี่สิบสี่วินาที"),
    (8, 0, "แล้วโจรก็ส่ง tx ไปที่ address ของ Binance 14 สั่ง sweep"),
    (8, .2, "EVM โหลดโค้ดของกระเป๋า เจอ 0xef0100 เลยไปดึงโค้ดของ X มารัน โดยถือว่าตัวเองคือ Binance 14"),
    (8, .55, "โค้ดจึงใช้เงินของ Binance 14 ได้เต็มที่ ETH แสนหกหมื่นกว่า กับ token อีกหกสิบสามตัว ออกไปใน tx เดียว โดยไม่ต้องใช้ลายเซ็นของ Binance อีกเลย"),
    (9, 0, "สองร้อยยี่สิบหกนาทีต่อมา Binance เซ็นใบใหม่ให้ชี้ไปที่ศูนย์ โค้ดกลับเป็นว่าง โจรเรียกไม่ได้อีก"),
    (9, .45, "แต่ระวัง ถ้า nonce ยังไม่เลยช่วง โจรเอาใบสำรองส่งซ้ำ ก็ delegate กลับได้ทันที ต้องส่ง tx เปล่าให้ nonce เลยใบสุดท้ายก่อน แล้วค่อยถอน"),
    (10, 0, "สรุป ใบอนุญาตของ EIP-7702 ไม่มีวงเงิน ไม่มีวันหมดอายุ และไม่สนว่าใครส่ง สิ่งเดียวที่จำกัดคือ nonce ใครถือกระเป๋าที่มีเงินเยอะ ต้องเฝ้าดูทุกบล็อกว่าโค้ดของกระเป๋ายังว่างอยู่ ถ้าเปลี่ยนเมื่อไหร่ ต้องแจ้งเตือนทันที"),
]
CPS = 13.0   # comfortable Thai narration speed, characters per second (marks included)

start = [sum(DUR[:i]) * SLOW for i in range(len(DUR))]
total = sum(DUR) * SLOW
cues = []
for i, (sc, f, text) in enumerate(LINES):
    t0 = start[sc] + f * DUR[sc] * SLOW
    nxt = LINES[i + 1] if i + 1 < len(LINES) else None
    t1 = start[nxt[0]] + nxt[1] * DUR[nxt[0]] * SLOW if nxt else total
    cues.append((sc, t0, t1, text))

mmss = lambda t: f"{int(t // 60)}:{t % 60:04.1f}"
srt = lambda t: f"{int(t // 3600):02d}:{int(t % 3600 // 60):02d}:{int(t % 60):02d},{int(round(t % 1 * 1000)) % 1000:03d}"
md = [f"# บทบรรยาย: EIP-7702 delegation ทีละขั้น\n",
      f"ใช้กับ `eip7702-delegation.mp4` ยาว {mmss(total)} นาที แต่ละช่วงเริ่มตรงกับตอนที่ caption บนจอเปลี่ยน "
      f"อ่านด้วยความเร็วพูดปกติ (ราว {CPS:g} ตัวอักษรต่อวินาที) แล้วจะจบพร้อมคลิป\n",
      "| เวลา | ฉาก | บรรยาย | ใช้เวลาพูด / มีเวลา |", "|---|---|---|---|"]
out = []
for k, (sc, t0, t1, text) in enumerate(cues, 1):
    need = len(text) / CPS
    md.append(f"| {mmss(t0)}–{mmss(t1)} | {SCENE[sc]} | {text} | {need:.1f}s / {t1 - t0:.1f}s |")
    out.append(f"{k}\n{srt(t0)} --> {srt(t1 - .05)}\n{text}\n")
    if need > t1 - t0 + .5:
        print(f"TOO LONG cue {k}: needs {need:.1f}s, has {t1 - t0:.1f}s")
(HERE / "narration-th.md").write_text("\n".join(md) + "\n")
(HERE / "narration-th.srt").write_text("\n".join(out))
print(f"{len(cues)} cues, {total:.1f}s")
