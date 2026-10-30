# Export eip7702-anim.html as carousel slides: one PNG per caption (the frame just before the caption changes).
#   python3 make_slides.py  -> slides-7702/slide-01.png .. slide-21.png
import pathlib, shutil
from playwright.sync_api import sync_playwright

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "slides-7702"
URL = (HERE / "eip7702-anim.html").as_uri() + "?capture"
# per scene: progress points where each caption is fully built (matches the caption thresholds in the html)
POINTS = [[.98], [.44, .98], [.44, .84, .98], [.98], [.54, .98], [.41, .65, .89, .98], [.98], [.98], [.14, .49, .98], [.44, .98], [.98]]

shutil.rmtree(OUT, ignore_errors=True)
OUT.mkdir()
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=CHROME)
    page = browser.new_page(viewport={"width": 1280, "height": 720}, device_scale_factor=1.5)
    page.goto(URL)
    page.evaluate("document.fonts.ready")
    starts = page.evaluate("(() => { let a = 0; return SCENES.map(s => { const r = [a, s.d]; a += s.d; return r; }); })()")
    assert len(starts) == len(POINTS)
    n = 0
    for (t0, d), pts in zip(starts, POINTS):
        for p in pts:
            n += 1
            page.evaluate(f"render({t0 + p * d})")
            page.screenshot(path=str(OUT / f"slide-{n:02d}.png"))
    browser.close()
print(f"saved {n} slides in {OUT}")
