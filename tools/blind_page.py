#!/usr/bin/env python3
"""A blind A/B page from `tools/scene_eval.py blind`'s pairs: one HTML file, pictures embedded.

    tools/blind_page.py BLIND_DIR OUT_HTML [--width 720]

BLIND_DIR holds `<n>.png` pairs (the photo, A and B) and `key.json`; the page shows every pair
with its number and A/B labels and nothing else, so a reader can say which they would rather
paint without knowing which method made it. The key stays out of the page: keep it apart and
compare afterwards. Pictures are re-encoded as JPEG at --width per panel (three panels a pair),
so eight pairs fit well under an artifact's size limit.
"""
import argparse
import base64
import html
import io
import json
import os

from PIL import Image

PAGE = """<title>Which would you paint?</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
/* Layout: one column of pairs, each a photo and two paintings side by side, stacking on a phone. */
:root {
  --paper: #f7f4ee; --ink: #23201b; --muted: #6d665b; --line: #d9d2c5; --mark: #5a4a8a;
  --display: "New York", "Iowan Old Style", Georgia, serif;
  --body: -apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper: #1b1917; --ink: #ece7dd; --muted: #a39b8d; --line: #3a3530; --mark: #b9aee6; color-scheme: dark } }
:root[data-theme="dark"] { --paper: #1b1917; --ink: #ece7dd; --muted: #a39b8d; --line: #3a3530; --mark: #b9aee6; color-scheme: dark }
body { background: var(--paper); color: var(--ink); font-family: var(--body); line-height: 1.5;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); padding-block: 24px 48px; }
main { max-width: 1400px; margin: 0 auto; display: grid; gap: 40px; }
h1 { font-family: var(--display); font-weight: 500; font-size: 1.9rem; margin: 0; text-wrap: balance; }
p.lead { color: var(--muted); max-width: 60ch; margin: 6px 0 0; }
section { display: grid; gap: 10px; }
section h2 { font-family: var(--display); font-weight: 500; font-size: 1.15rem; margin: 0; }
.row { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
@media (max-width: 720px) { .row { grid-template-columns: 1fr; } }
figure { margin: 0; min-width: 0; display: grid; gap: 6px; }
figure img { width: 100%; height: auto; display: block; border: 1px solid var(--line); }
figcaption { font-size: 0.85rem; letter-spacing: 0.04em; text-transform: uppercase; color: var(--muted); }
figcaption b { color: var(--mark); font-weight: 600; }
footer { color: var(--muted); font-size: 0.9rem; border-top: 1px solid var(--line); padding-top: 16px; }
</style>
<main>
<header>
<h1>Which would you paint?</h1>
<p class="lead">__COUNT__ photos, each made into a painting two ways. A and B change places from pair to pair. For each pair, say which finished painting you would rather have painted, and why in a few words; the key is kept apart.</p>
</header>
__SECTIONS__
<footer>Paint by Moonlight, the template algorithm's evaluation set (painting-company row 188). The paintings are what the app would show finished.</footer>
</main>
"""


def jpeg_uri(image, width):
    if image.width > width:
        image = image.resize((width, int(image.height * width / image.width)), Image.LANCZOS)
    buf = io.BytesIO()
    image.convert("RGB").save(buf, format="JPEG", quality=82, optimize=True)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("blind_dir")
    ap.add_argument("out_html")
    ap.add_argument("--width", type=int, default=720)
    args = ap.parse_args()
    with open(os.path.join(args.blind_dir, "key.json")) as f:
        key = json.load(f)
    sections = []
    for entry in key:
        n = entry["pair"]
        sheet = Image.open(os.path.join(args.blind_dir, f"{n}.png")).convert("RGB")
        # The sheet is three panels of one width with 8-px gaps and a 40-px title band.
        cell = (sheet.width - 16) // 3
        panels = [sheet.crop((i * (cell + 8), 40, i * (cell + 8) + cell, sheet.height)) for i in range(3)]
        figures = []
        for label, panel in zip(["the photo", "A", "B"], panels):
            caption = html.escape(label) if label == "the photo" else f"<b>{label}</b>"
            figures.append(f'<figure><img src="{jpeg_uri(panel, args.width)}" alt="pair {n}, {html.escape(label)}"><figcaption>{caption}</figcaption></figure>')
        sections.append(f'<section id="pair-{n}"><h2>Pair {n}</h2><div class="row">{"".join(figures)}</div></section>')
    page = PAGE.replace("__COUNT__", str(len(key))).replace("__SECTIONS__", "\n".join(sections))
    with open(args.out_html, "w") as f:
        f.write(page)
    print(f"{args.out_html}: {len(key)} pairs, {os.path.getsize(args.out_html) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
