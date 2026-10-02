"""Contact sheet of stage-1 options, for judging by eye.

    python lines_sheet.py <out-dir> [--options o1,o2,...|--detail medium] [--file lines_alone.png]
                          [--width 760] [--cols 3] [--photo <pic-dir>] --save sheet.png

Each tile is the option's `--file` (default lines_alone.png) downscaled to `--width`, captioned
with the option name, stroke count, ink coverage and strong-edge recall. `--photo` adds the
working photo as the first tile.
"""

import argparse
import json
import os

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                 "/usr/share/fonts/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--options")
    ap.add_argument("--detail")
    ap.add_argument("--file", default="lines_alone.png")
    ap.add_argument("--width", type=int, default=760)
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--photo")
    ap.add_argument("--save", required=True)
    a = ap.parse_args()
    if a.options:
        opts = a.options.split(",")
    else:
        opts = sorted(d for d in os.listdir(a.out_dir)
                      if os.path.isdir(os.path.join(a.out_dir, d)) and not d.startswith("_"))
        if a.detail:
            opts = [o for o in opts if o.endswith("-" + a.detail)]
    tiles = []
    if a.photo:
        im = Image.open(os.path.join(a.photo, "working.ppm")).convert("RGB")
        tiles.append(("photo", im))
    for o in opts:
        p = os.path.join(a.out_dir, o, a.file)
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        cap = o
        mp = os.path.join(a.out_dir, o, "metrics.json")
        if os.path.exists(mp):
            m = json.load(open(mp))
            cap += f"  n={m['strokes']} ink={m['ink_coverage']:.3f} rec={m['strong_edge_recall']}"
        tiles.append((cap, im))
    if not tiles:
        raise SystemExit("nothing to show")
    tw = a.width
    th = max(int(round(im.height * tw / im.width)) for _, im in tiles)
    cap_h = 22
    cols = min(a.cols, len(tiles))
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (tw + 6), rows * (th + cap_h + 6)), "white")
    d = ImageDraw.Draw(sheet)
    f = font(15)
    for k, (cap, im) in enumerate(tiles):
        im = im.resize((tw, int(round(im.height * tw / im.width))), Image.Resampling.LANCZOS)
        x = (k % cols) * (tw + 6)
        y = (k // cols) * (th + cap_h + 6)
        sheet.paste(im, (x, y + cap_h))
        d.text((x + 4, y + 3), cap, fill=(0, 0, 0), font=f)
    sheet.save(a.save)


if __name__ == "__main__":
    main()
