#!/usr/bin/env python3
"""Watercolor's Making Of as a contact sheet and a film, for a critic (painting-company row 373).

    pbn watercolor <photo | template.pbnt> --out <dir> --making-of [--fps 15]
    tools/watercolor_making_of.py <dir> [--fps 15] [--tiles 12]

Reads <dir>/frame-NNNN.ppm (pbn's frames, 1/fps second shown apart) and making-of.csv (which
frame settled) and writes <dir>/contact.jpg (--tiles frames evenly spaced up to the settled one,
each with its time shown) and, when ffmpeg is on the path, <dir>/making-of.mp4: the frames, then
the app's ending on the frames after (the painting held, drying on, then lifted away, a little
larger and fading, off the bare pencilled sheet the painter paints). Pillow only.
"""
import argparse
import csv
import glob
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw

DESK = (232, 227, 217)
HOLD = 0.8  # seconds the finished painting is held (WatercolorMakingOfView.hold)
LIFT = 0.9  # seconds it lifts away (WatercolorMakingOfView.lift)


def on_desk(sheet, size):
    """The sheet centred on the desk at 94% of the frame, as the app fits it."""
    w, h = size
    s = min(w / sheet.width, h / sheet.height) * 0.94
    tile = sheet.resize((round(sheet.width * s), round(sheet.height * s)), Image.LANCZOS)
    out = Image.new("RGB", size, DESK)
    out.paste(tile, ((w - tile.width) // 2, (h - tile.height) // 2))
    return out


def lifted(finished, bare, size, u):
    """The ending at u (0…1): the finished sheet a little larger and fading over the bare one."""
    w, h = size
    base = on_desk(bare, size)
    s = min(w / finished.width, h / finished.height) * 0.94 * (1 + 0.05 * u)
    tile = finished.resize((round(finished.width * s), round(finished.height * s)), Image.LANCZOS)
    top = base.copy()
    top.paste(tile, ((w - tile.width) // 2, (h - tile.height) // 2))
    ease = u * u * (3 - 2 * u)
    return Image.blend(top, base, ease)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dir")
    ap.add_argument("--fps", type=float, default=15)
    ap.add_argument("--tiles", type=int, default=12)
    ap.add_argument("--width", type=int, default=1280, help="the film's width (16:10 frame)")
    args = ap.parse_args()
    paths = sorted(glob.glob(os.path.join(args.dir, "frame-*.ppm")))
    if not paths:
        raise SystemExit(f"no frame-*.ppm in {args.dir}")
    settled = len(paths) - 1
    with open(os.path.join(args.dir, "making-of.csv")) as f:
        for row in csv.DictReader(f):
            if row["settled"] == "1":
                settled = int(row["frame"])
                break
    ending = paths[settled:]
    paths = paths[:settled + 1]

    n = min(args.tiles, len(paths))
    picks = [round(i * (len(paths) - 1) / max(n - 1, 1)) for i in range(n)]
    first = Image.open(paths[0])
    tw = 420
    th = round(first.height * tw / first.width)
    cols = 4
    rows = (n + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (tw + 12) + 12, rows * (th + 34) + 12), DESK)
    draw = ImageDraw.Draw(sheet)
    for k, i in enumerate(picks):
        im = Image.open(paths[i]).convert("RGB").resize((tw, th), Image.LANCZOS)
        x, y = 12 + (k % cols) * (tw + 12), 12 + (k // cols) * (th + 34)
        sheet.paste(im, (x, y))
        draw.text((x, y + th + 6), f"{i / args.fps:.1f} s", fill=(60, 60, 70))
    sheet.save(os.path.join(args.dir, "contact.jpg"), quality=90)

    if not shutil.which("ffmpeg"):
        print("no ffmpeg: contact sheet only")
        return
    size = (args.width, round(args.width * 10 / 16) // 2 * 2)
    bare = Image.open(paths[0]).convert("RGB")
    def ending_frame(j):
        return Image.open(ending[min(j, len(ending) - 1)]).convert("RGB")
    with tempfile.TemporaryDirectory() as tmp:
        k = 0
        for p in paths:
            on_desk(Image.open(p).convert("RGB"), size).save(os.path.join(tmp, f"{k:05d}.png"))
            k += 1
        held = round(HOLD * args.fps)
        for j in range(1, held + 1):
            on_desk(ending_frame(j), size).save(os.path.join(tmp, f"{k:05d}.png"))
            k += 1
        steps = round(LIFT * args.fps)
        for j in range(1, steps + 1):
            lifted(ending_frame(held + j), bare, size, j / steps).save(os.path.join(tmp, f"{k:05d}.png"))
            k += 1
        for _ in range(round(0.6 * args.fps)):
            on_desk(bare, size).save(os.path.join(tmp, f"{k:05d}.png"))
            k += 1
        out = os.path.join(args.dir, "making-of.mp4")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(args.fps), "-i",
                        os.path.join(tmp, "%05d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p",
                        "-r", "30", out], check=True)
        print(f"{out}: {k / args.fps:.1f} s")


if __name__ == "__main__":
    main()
