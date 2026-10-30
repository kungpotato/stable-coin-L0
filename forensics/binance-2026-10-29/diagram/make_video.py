# Render eip7702-anim.html frame by frame with headless Chrome (Playwright) and encode an MP4 with ffmpeg.
#   python3 make_video.py              -> eip7702-delegation.mp4
#   python3 make_video.py 12.5 40 75   -> preview-<t>.png at those seconds only
import os, pathlib, shutil, subprocess, sys, tempfile
from playwright.sync_api import sync_playwright

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HERE = pathlib.Path(__file__).resolve().parent
URL = (HERE / "eip7702-anim.html").as_uri() + "?capture"

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=CHROME)
    page = browser.new_page(viewport={"width": 1280, "height": 720}, device_scale_factor=1.5)
    page.goto(URL)
    page.evaluate("document.fonts.ready")
    total, fps = page.evaluate("[TOTAL, FPS]")
    if len(sys.argv) > 1:
        for t in map(float, sys.argv[1:]):
            page.evaluate(f"render({t})")
            page.screenshot(path=str(HERE / f"preview-{t:g}.png"))
            print("preview", t)
        sys.exit()
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="anim-"))
    n = int(total * fps)
    for i in range(n):
        page.evaluate(f"render({i / fps})")
        page.screenshot(path=str(tmp / f"f{i:05d}.jpg"), type="jpeg", quality=92)
        if i % 300 == 0:
            print(f"frame {i}/{n}", flush=True)
    browser.close()

out = HERE / "eip7702-delegation.mp4"
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(fps), "-i", str(tmp / "f%05d.jpg"),
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart", str(out)], check=True)
shutil.rmtree(tmp)
print(f"saved {out} ({out.stat().st_size / 1e6:.1f} MB, {total}s)")
