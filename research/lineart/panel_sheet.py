"""Contact sheet of one option's stage-2 panels, for looking (not for the morning page).

    panel_sheet.py <option-dir> [--lines <stage1-option-dir>] [--width 2400] [--crop x0,y0,x1,y1]

Row 1: current template | current painted | lines alone (stage 1)
Row 2: plan C1 | finished C1 | flat C1
Row 3: plan C2 | finished C2 | flat C2
Writes sheet.jpg (or sheet_crop.jpg with --crop, fractions of the picture) in the option dir.
Stage 1's lines_alone.png is read from the option dir unless --lines names another.
"""

import argparse
import os

from PIL import Image, ImageDraw, ImageFont

from panels import FALLBACK_FONT, FONT_PATH


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--lines", default=None)
    ap.add_argument("--width", type=int, default=2400)
    ap.add_argument("--crop", default=None)
    a = ap.parse_args()
    d = a.dir.rstrip("/")
    pic_dir = os.path.dirname(d)
    cells = [
        [(os.path.join(pic_dir, "current_template.png"), "current template"),
         (os.path.join(pic_dir, "current_painted.png"), "current painted"),
         (os.path.join(a.lines or d, "lines_alone.png"), "lines alone")],
        [(os.path.join(d, "plan_c1.png"), "plan C1"), (os.path.join(d, "finished_c1.png"), "finished C1"),
         (os.path.join(d, "flat_c1.png"), "flat C1")],
        [(os.path.join(d, "plan_c2.png"), "plan C2"), (os.path.join(d, "finished_c2.png"), "finished C2"),
         (os.path.join(d, "flat_c2.png"), "flat C2")],
    ]
    crop = [float(v) for v in a.crop.split(",")] if a.crop else None
    cw = (a.width - 2 * 8) // 3
    font = ImageFont.truetype(FONT_PATH if os.path.exists(FONT_PATH) else FALLBACK_FONT, 22)
    rows = []
    for row in cells:
        ims = []
        for path, label in row:
            if path and os.path.exists(path):
                im = Image.open(path).convert("RGB")
                if crop:
                    w, h = im.size
                    im = im.crop((int(crop[0] * w), int(crop[1] * h), int(crop[2] * w), int(crop[3] * h)))
                im = im.resize((cw, max(1, round(im.height * cw / im.width))), Image.LANCZOS)
            else:
                im = Image.new("RGB", (cw, cw * 2 // 3), "#dddddd")
            ImageDraw.Draw(im).text((8, 6), label, fill=(200, 30, 60), font=font)
            ims.append(im)
        rows.append(ims)
    rh = [max(i.height for i in r) for r in rows]
    sheet = Image.new("RGB", (a.width, sum(rh) + 8 * (len(rows) - 1)), "white")
    y = 0
    for r, h in zip(rows, rh):
        x = 0
        for im in r:
            sheet.paste(im, (x, y))
            x += cw + 8
        y += h + 8
    sheet.save(os.path.join(d, "sheet_crop.jpg" if crop else "sheet.jpg"), quality=88)


if __name__ == "__main__":
    main()
