#!/usr/bin/env python3
"""Lays the iPhone Duo's poses out as one contact sheet per scenario, from a CI report.

  tools/duo_sheet.py <report>/duo/shots <outdir> [--scenarios paint gallery ...] [--height 520]

ci/duo.sh writes duo-<scenario>-<n>-<pose>.png for each pose (and its layout as .json beside it);
this puts a scenario's poses side by side at one height, each labelled with its pose, its size in
points and, where the app reported one, the fold drawn as a dashed band, so a reader (a session,
the Lamplit Table, Paul) sees every pose of a screen at once. Writes <outdir>/<scenario>.jpg.
Needs Pillow.
"""
import argparse
import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SHOT = re.compile(r"^duo-(?P<scenario>.+)-(?P<n>\d)-(?P<pose>[a-z-]+)\.png$")
LABELS = {
    "closed": "closed", "turned": "closed, on its side", "open": "open like a book",
    "book": "half open like a book", "open-turned": "open, upright", "laptop": "half open like a laptop",
    "closed-again": "closed again",
}


def font(size):
    for name in ("DejaVuSans.ttf", "Arial.ttf", "Helvetica.ttc"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def poses(shots):
    found = {}
    for path in sorted(Path(shots).glob("duo-*.png")):
        match = SHOT.match(path.name)
        if match:
            found.setdefault(match["scenario"], []).append((int(match["n"]), match["pose"], path))
    return {scenario: sorted(items) for scenario, items in found.items()}


def tile(path, pose, height):
    image = Image.open(path).convert("RGB")
    layout = {}
    try:
        layout = json.loads(path.with_suffix(".json").read_text())
    except (OSError, ValueError):
        pass
    size = layout.get("size")
    points = size[0] if size else image.width / 3
    scale = image.width / points if points else 3
    draw = ImageDraw.Draw(image, "RGBA")
    for x, y, w, h in layout.get("folds", []):
        box = [x * scale, y * scale, (x + w) * scale, (y + h) * scale]
        draw.rectangle(box, fill=(255, 64, 160, 40), outline=(255, 64, 160, 200), width=4)
    image = image.resize((max(1, round(image.width * height / image.height)), height), Image.LANCZOS)
    label = LABELS.get(pose, pose)
    if size:
        label += f"\n{size[0]:.0f}×{size[1]:.0f} pt"
    return image, label


def sheet(scenario, items, height):
    tiles = [tile(path, pose, height) for _, pose, path in items]
    gap, caption = 24, 44
    width = sum(t.width for t, _ in tiles) + gap * (len(tiles) + 1)
    out = Image.new("RGB", (width, height + caption + gap * 2 + 60), (238, 236, 241))
    draw = ImageDraw.Draw(out)
    draw.text((gap, 14), scenario, fill=(30, 26, 34), font=font(30))
    x = gap
    for image, label in tiles:
        out.paste(image, (x, 60))
        draw.multiline_text((x, 60 + height + 10), label, fill=(60, 56, 64), font=font(20), spacing=6)
        x += image.width + gap
    return out


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("shots")
    parser.add_argument("out")
    parser.add_argument("--scenarios", nargs="*")
    parser.add_argument("--height", type=int, default=520)
    args = parser.parse_args(argv[1:])
    found = poses(args.shots)
    if not found:
        print(f"no duo-*.png in {args.shots}", file=sys.stderr)
        return 1
    Path(args.out).mkdir(parents=True, exist_ok=True)
    for scenario in args.scenarios or sorted(found):
        if scenario not in found:
            print(f"{scenario}: no shots", file=sys.stderr)
            continue
        path = Path(args.out) / f"{scenario}.jpg"
        sheet(scenario, found[scenario], args.height).save(path, quality=88)
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
