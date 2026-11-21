#!/usr/bin/env python3
"""Watercolor's Making Of as a contact sheet and a film, for a critic (painting-company row 373).

    pbn watercolor <photo | template.pbnt> --out <dir> --making-of [--fps 15]
    tools/watercolor_making_of.py <dir> [--fps 15] [--tiles 12]

Reads <dir>/frame-NNNN.ppm (pbn's frames, 1/fps second shown apart) and making-of.csv (which
frame settled) and writes <dir>/contact.jpg (--tiles frames evenly spaced up to the settled one,
each with its time shown) and, when ffmpeg is on the path, <dir>/making-of.mp4: the frames, then
the app's ending on the frames after (the painting held, drying on, then lifted away, a little
larger and fading, off the bare pencilled sheet the painter paints, its numbers drawn at the
film's own size from labels.csv, as the painting screen draws them, fading in once the lift is
done; the last of these is also written as last-frame.png). Pillow only; the numbers in DejaVu
Sans where it is installed.
"""
import argparse
import csv
import glob
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

DESK = (232, 227, 217)
HOLD = 0.8  # seconds the finished painting is held (WatercolorMakingOfView.hold)
LIFT = 0.9  # seconds it lifts away (WatercolorMakingOfView.lift)
PUSH = 1.15  # the push in toward a drying bloom (WatercolorMakingOfView.pushIn)
PUSH_SECONDS = 2.6  # its ease in and out (WatercolorMakingOfView.pushSeconds)
NUMBERS_IN = 0.35  # seconds the numbers fade in over once the lift is done
NUMBER_INK = (48, 46, 51)  # WatercolorRenderer.numberInk, near enough
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def pushed(sheet, zoom, focus):
    """The sheet scaled `zoom` about `focus` (fractions) and clipped to its own frame."""
    if zoom <= 1.0001:
        return sheet
    w, h = sheet.size
    cw, ch = w / zoom, h / zoom
    fx, fy = focus[0] * w, focus[1] * h
    x0, y0 = fx - fx / zoom, fy - fy / zoom
    return sheet.crop((round(x0), round(y0), round(x0 + cw), round(y0 + ch))).resize((w, h), Image.LANCZOS)


def on_desk(sheet, size, zoom=1.0, focus=(0.5, 0.5)):
    """The sheet centred on the desk at 94% of the frame, as the app fits it."""
    w, h = size
    sheet = pushed(sheet, zoom, focus)
    s = min(w / sheet.width, h / sheet.height) * 0.94
    tile = sheet.resize((round(sheet.width * s), round(sheet.height * s)), Image.LANCZOS)
    out = Image.new("RGB", size, DESK)
    out.paste(tile, ((w - tile.width) // 2, (h - tile.height) // 2))
    return out


def lifted(finished, bare, size, u, zoom=1.0, focus=(0.5, 0.5)):
    """The ending at u (0…1): the finished sheet a little larger and fading over the bare one."""
    w, h = size
    base = on_desk(bare, size)
    finished = pushed(finished, zoom, focus)
    s = min(w / finished.width, h / finished.height) * 0.94 * (1 + 0.05 * u)
    tile = finished.resize((round(finished.width * s), round(finished.height * s)), Image.LANCZOS)
    top = base.copy()
    top.paste(tile, ((w - tile.width) // 2, (h - tile.height) // 2))
    ease = u * u * (3 - 2 * u)
    return Image.blend(top, base, ease)


def numbered(sheet, size, labels, alpha):
    """The bare sheet on the desk with its numbers at `alpha`, drawn at the film's pixels."""
    out = on_desk(sheet, size)
    if not labels or alpha <= 0:
        return out
    w, h = size
    s = min(w / sheet.width, h / sheet.height) * 0.94
    tw, th = round(sheet.width * s), round(sheet.height * s)
    x0, y0 = (w - tw) // 2, (h - th) // 2
    layer = Image.new("L", size, 0)
    draw = ImageDraw.Draw(layer)
    fonts = {}
    for x, y, frac, number in labels:
        px = max(round(frac * tw), 6)
        if px not in fonts:
            fonts[px] = ImageFont.truetype(FONT, px) if os.path.exists(FONT) else ImageFont.load_default()
        draw.text((x0 + x * tw, y0 + y * th), str(number), fill=round(255 * 0.9 * alpha), font=fonts[px], anchor="mm")
    ink = Image.new("RGB", size, NUMBER_INK)
    return Image.composite(ink, out, layer)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dir")
    ap.add_argument("--fps", type=float, default=15)
    ap.add_argument("--tiles", type=int, default=12)
    ap.add_argument("--width", type=int, default=2048, help="the film's width (16:10 frame; an iPad's 2048 by default)")
    args = ap.parse_args()
    paths = sorted(glob.glob(os.path.join(args.dir, "frame-*.ppm")))
    if not paths:
        raise SystemExit(f"no frame-*.ppm in {args.dir}")
    settled = len(paths) - 1
    drying = None
    with open(os.path.join(args.dir, "making-of.csv")) as f:
        for row in csv.DictReader(f):
            if drying is None and row.get("drying") == "1":
                drying = int(row["frame"])
            if row["settled"] == "1":
                settled = int(row["frame"])
                break
    focus = (0.5, 0.5)
    focus_file = os.path.join(args.dir, "focus.txt")
    if os.path.exists(focus_file):
        focus = tuple(float(v) for v in open(focus_file).read().split())

    def zoom(k):
        """The push in at film frame k: eased from the drying's first frame."""
        if drying is None or k < drying:
            return 1.0
        u = min((k - drying) / (PUSH_SECONDS * args.fps), 1)
        return 1 + (PUSH - 1) * u * u * (3 - 2 * u)
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
    bare_file = os.path.join(args.dir, "bare.ppm")
    bare = Image.open(bare_file if os.path.exists(bare_file) else paths[0]).convert("RGB")
    labels = []
    labels_file = os.path.join(args.dir, "labels.csv")
    if os.path.exists(labels_file):
        with open(labels_file) as f:
            labels = [(float(r["x"]), float(r["y"]), float(r["size"]), int(r["number"])) for r in csv.DictReader(f)]
    def ending_frame(j):
        return Image.open(ending[min(j, len(ending) - 1)]).convert("RGB")
    with tempfile.TemporaryDirectory() as tmp:
        k = 0
        for p in paths:
            on_desk(Image.open(p).convert("RGB"), size, zoom(k), focus).save(os.path.join(tmp, f"{k:05d}.png"))
            k += 1
        held = round(HOLD * args.fps)
        for j in range(1, held + 1):
            on_desk(ending_frame(j), size, zoom(k), focus).save(os.path.join(tmp, f"{k:05d}.png"))
            k += 1
        steps = round(LIFT * args.fps)
        for j in range(1, steps + 1):
            lifted(ending_frame(held + j), bare, size, j / steps, zoom(k), focus).save(os.path.join(tmp, f"{k:05d}.png"))
            k += 1
        fade_in = max(round(NUMBERS_IN * args.fps), 1)
        last = None
        for j in range(fade_in + round(0.8 * args.fps)):
            last = numbered(bare, size, labels, min((j + 1) / fade_in, 1))
            last.save(os.path.join(tmp, f"{k:05d}.png"))
            k += 1
        last.save(os.path.join(args.dir, "last-frame.png"))
        out = os.path.join(args.dir, "making-of.mp4")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(args.fps), "-i",
                        os.path.join(tmp, "%05d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p",
                        "-r", "30", out], check=True)
        print(f"{out}: {k / args.fps:.1f} s")


if __name__ == "__main__":
    main()
