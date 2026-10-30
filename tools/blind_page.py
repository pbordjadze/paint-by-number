#!/usr/bin/env python3
"""A blind A/B page from `tools/scene_eval.py blind`'s pairs: one HTML file, pictures embedded.

    tools/blind_page.py BLIND_DIR OUT_HTML [--width 720] [--lines [--stroke 2]]

BLIND_DIR holds `<n>.png` pairs (the photo, A and B) and `key.json`; the page shows every pair
with its number and A/B labels and nothing else, so a reader can say which they would rather
paint without knowing which method made it. The key stays out of the page: keep it apart and
compare afterwards. Pictures are re-encoded as JPEG at --width per panel (three panels a pair),
so eight pairs fit well under an artifact's size limit.

`--lines` shows each template's lines alone, as a printed sheet shows them without its numbers
(the drawing in ink over the color edges as dotted guides; no paint), in place of the finished
paintings: it reads `key.json`'s photo and method for each pair from the round directory
BLIND_DIR sits in (`<round>/<photo>/<method>/painted-outlined.svg`, pbn's) and rasterizes
them with `tools/svg2png.mjs`, the stroke --stroke times the SVG's print width, so they read
on a phone.
"""
import argparse
import base64
import html
import io
import json
import os
import re
import subprocess
import tempfile

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
<p class="lead">__LEAD__</p>
</header>
__SECTIONS__
<footer>__FOOTER__</footer>
</main>
"""


SVG2PNG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "svg2png.mjs")
INK = "#2a2622"


def lines_only(svg_path, png_path, width, stroke):
    """The template as a printed sheet shows it, without numbers: the drawing in ink, the color
    edges under it as dotted guides (`TemplateRasterizer`'s `.print`: the outline color at 0.7,
    dots 2.5 widths apart), no paint. From pbn's painted-outlined.svg: its region paths lose
    their fill and stroke the guides, its drawing group strokes `stroke` times as wide."""
    with open(svg_path) as f:
        svg = f.read()
    svg = re.sub(r"<text\b[^>]*>.*?</text>\s*", "", svg, flags=re.S)
    drawn = re.search(r'<g id="lines-drawing".*?</g>', svg, flags=re.S)
    width_attr = re.search(r'stroke-width="([0-9.]+)"', drawn.group(0)) if drawn else None
    w = float(width_attr.group(1)) * stroke if width_attr else 2.0
    head, _, _ = svg.partition("<g fill-rule")
    guides = re.findall(r'<path d="([^"]*)" fill="#[0-9a-fA-F]{6}" stroke="#[0-9a-fA-F]{6}"[^>]*/>', svg)
    out = head
    out += (f'<g fill="none" stroke="{INK}" stroke-opacity="0.7" stroke-width="{w:.2f}" stroke-linecap="round" '
            f'stroke-linejoin="round" stroke-dasharray="0 {w * 2.5:.2f}">\n')
    out += "".join(f'<path d="{d}"/>\n' for d in guides) + "</g>\n"
    if drawn:
        ink = re.sub(r'stroke-width="[0-9.]+"', f'stroke-width="{w:.2f}"', drawn.group(0))
        ink = re.sub(r'stroke="#(?!ffffff)[0-9a-fA-F]{6}"', f'stroke="{INK}"', ink)
        out += ink + "\n"
    out += "</svg>\n"
    tmp = png_path + ".svg"
    with open(tmp, "w") as f:
        f.write(out)
    subprocess.run(["node", SVG2PNG, tmp, png_path, str(width)], check=True)
    os.remove(tmp)
    return Image.open(png_path).convert("RGB")


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
    ap.add_argument("--lines", action="store_true", help="the templates' lines alone, from the round directory")
    ap.add_argument("--stroke", type=float, default=2.0, help="with --lines: the stroke, times the SVG's")
    args = ap.parse_args()
    round_dir = os.path.dirname(os.path.abspath(args.blind_dir))
    with open(os.path.join(args.blind_dir, "key.json")) as f:
        key = json.load(f)
    sections = []
    for entry in key:
        n = entry["pair"]
        sheet = Image.open(os.path.join(args.blind_dir, f"{n}.png")).convert("RGB")
        # The sheet is three panels of one width with 8-px gaps and a 40-px title band.
        cell = (sheet.width - 16) // 3
        panels = [sheet.crop((i * (cell + 8), 40, i * (cell + 8) + cell, sheet.height)) for i in range(3)]
        if args.lines:
            with tempfile.TemporaryDirectory() as tmp:
                panels[1:] = [
                    lines_only(os.path.join(round_dir, entry["photo"], entry[side], "painted-outlined.svg"),
                               os.path.join(tmp, f"{n}-{side}.png"), args.width * 2, args.stroke)
                    for side in ("A", "B")]
        figures = []
        for label, panel in zip(["the photo", "A", "B"], panels):
            caption = html.escape(label) if label == "the photo" else f"<b>{label}</b>"
            figures.append(f'<figure><img src="{jpeg_uri(panel, args.width)}" alt="pair {n}, {html.escape(label)}"><figcaption>{caption}</figcaption></figure>')
        sections.append(f'<section id="pair-{n}"><h2>Pair {n}</h2><div class="row">{"".join(figures)}</div></section>')
    lead = (f"{len(key)} photos, each made into a painting two ways; here are the lines of each template alone, as the app draws them. "
            "A and B change places from pair to pair. For each pair, say which you would rather paint, and why in a few words; the key is kept apart."
            if args.lines else
            f"{len(key)} photos, each made into a painting two ways. A and B change places from pair to pair. "
            "For each pair, say which finished painting you would rather have painted, and why in a few words; the key is kept apart.")
    footer = ("Paint by Moonlight, the template algorithm's evaluation set (painting-company row 188). The drawings are each template's lines, without numbers or paint."
              if args.lines else
              "Paint by Moonlight, the template algorithm's evaluation set (painting-company row 188). The paintings are what the app would show finished.")
    page = PAGE.replace("__LEAD__", lead).replace("__FOOTER__", footer).replace("__SECTIONS__", "\n".join(sections))
    with open(args.out_html, "w") as f:
        f.write(page)
    print(f"{args.out_html}: {len(key)} pairs, {os.path.getsize(args.out_html) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
