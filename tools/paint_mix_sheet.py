#!/usr/bin/env python3
"""The paint mixes side by side: the photo and the finished painting with each mix, per picture.

    tools/paint_mix_sheet.py --out DIR NAME=RUN[/before|/after] ...

Each `RUN` is an output directory of `tools/kit_eval.py run` (`RUN/<id>/{before,after}/finished.png`
and `RUN/<id>/input.ppm`); `/before` or `/after` picks the variant (`after` if left out). Writes
`DIR/<id>.jpg` for every picture all the runs have: the photo, then one column per `NAME`, 660 px
wide each (`--width`), to look at with the Read tool or hand to a critic. For lively paint
(painting-company row 326):

    tools/kit_eval.py run --set SET --out A                                              # the photo's paints, kit paint
    tools/kit_eval.py run --set SET --out B --before "--paint-mix kit" -- --paint-mix lively
    tools/paint_mix_sheet.py --out sheets release=A/before kit=A/after lively=B/after

Requires Pillow.
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True)
    ap.add_argument("--width", type=int, default=660)
    ap.add_argument("columns", nargs="+", metavar="NAME=RUN[/before|/after]")
    args = ap.parse_args()
    columns = []
    for column in args.columns:
        name, _, run = column.partition("=")
        variant = "after"
        if os.path.basename(run) in ("before", "after"):
            run, variant = os.path.dirname(run), os.path.basename(run)
        columns.append((name, run, variant))
    os.makedirs(args.out, exist_ok=True)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    first = columns[0][1]
    for pid in sorted(os.listdir(first)):
        paths = [os.path.join(run, pid, variant, "finished.png") for _, run, variant in columns]
        photo = os.path.join(first, pid, "input.ppm")
        if not all(os.path.exists(p) for p in paths + [photo]):
            continue
        images = [Image.open(p).convert("RGB") for p in [photo] + paths]
        w, h = images[-1].size
        height = round(args.width * h / w)
        gap, top = 8, 34
        sheet = Image.new("RGB", (args.width * len(images) + gap * (len(images) - 1), height + top), "white")
        draw = ImageDraw.Draw(sheet)
        for i, (name, image) in enumerate(zip(["photo"] + [c[0] for c in columns], images)):
            x = i * (args.width + gap)
            sheet.paste(image.resize((args.width, height), Image.LANCZOS), (x, top))
            draw.text((x + 4, 4), name, fill="black", font=font)
        sheet.save(os.path.join(args.out, pid + ".jpg"), quality=92)
        print(pid)


if __name__ == "__main__":
    main()
