#!/usr/bin/env python3
"""Six wipe frames per reveal pair, with the worker path in snapshot pixel coordinates.

    tools/factory/reveal_sheet.py <snapshot-dir> <reveal-dir> /root/factory-out/reveal.png

Requires Pillow. Build fields with `figures reveal` first. Zero PGM bytes stay on A;
nonzero bytes decode to (value - 1) / 254. Frames run from time 0 through time 1.
"""
import argparse
import json
from pathlib import Path


from output_paths import outside_repo

STAGES = ("working-image.ppm", "structure.pgm", "smoothed.ppm", "palette.ppm",
          "simplified.ppm", "line-art.pgm", "vectorized.pgm")


def wipe(before, after, field, time):
    from PIL import Image
    if before.size != after.size or before.size != field.size:
        raise ValueError("snapshots and reveal field must have the same size")
    if field.mode != "L":
        raise ValueError("reveal field must be grayscale")
    mask = field.point([255 if value and (value - 1) / 254 <= time else 0
                        for value in range(256)])
    return Image.composite(after.convert("RGB"), before.convert("RGB"), mask)


def path_points(path):
    # RevealField emits only absolute M/L commands, separated by spaces.
    tokens = path.split()
    if len(tokens) % 3:
        raise ValueError("expected absolute M/L reveal path")
    points = []
    for i in range(0, len(tokens), 3):
        if tokens[i] != ("M" if i == 0 else "L"):
            raise ValueError("expected absolute M/L reveal path")
        points.append((float(tokens[i + 1]), float(tokens[i + 2])))
    return points


def make_sheet(snapshot_dir, reveal_dir, output):
    from PIL import Image, ImageDraw, ImageFont
    output = outside_repo(output)
    snapshots = [snapshot_dir / name for name in STAGES if (snapshot_dir / name).is_file()]
    if len(snapshots) < 2:
        raise ValueError("expected at least two named pbn snapshots")
    font = ImageFont.load_default()
    rows = []
    for first, second in zip(snapshots, snapshots[1:]):
        name = first.stem + "-" + second.stem
        metadata = json.loads((reveal_dir / (name + ".json")).read_text())
        with Image.open(first) as a, Image.open(second) as b, \
                Image.open(reveal_dir / (name + ".pgm")) as field:
            if field.size != (metadata["width"], metadata["height"]):
                raise ValueError(f"{name}: metadata dimensions disagree with PGM")
            scale = min(1, 320 / max(a.size))
            size = (max(1, round(a.width * scale)), max(1, round(a.height * scale)))
            frames = []
            points = path_points(metadata["path"])
            for index in range(6):
                frame = wipe(a, b, field, index / 5).resize(size, Image.Resampling.LANCZOS)
                draw = ImageDraw.Draw(frame)
                scaled = [(x * size[0] / a.width, y * size[1] / a.height) for x, y in points]
                if len(scaled) > 1:
                    draw.line(scaled, fill="#172e50", width=3)
                    draw.line(scaled, fill="#ffca52", width=1)
                if scaled:
                    x, y = scaled[0]
                    draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill="#ffca52", outline="#172e50")
                frames.append(frame)
        row = Image.new("RGB", (6 * (size[0] + 8) + 8, size[1] + 48), "#f6f1e7")
        draw = ImageDraw.Draw(row)
        draw.text((8, 4), f"{name} | {metadata['changed']:.1%} changed | "
                  f"{metadata['seed']} | {metadata['steps']} steps", font=font, fill="#2b2622")
        for index, frame in enumerate(frames):
            x = 8 + index * (size[0] + 8)
            row.paste(frame, (x, 24))
            draw.text((x, size[1] + 28), f"t = {index / 5:.1f}", font=font, fill="#2b2622")
        rows.append(row)
    sheet = Image.new("RGB", (max(row.width for row in rows), sum(row.height for row in rows)), "#f6f1e7")
    y = 0
    for row in rows:
        sheet.paste(row, (0, y)); y += row.height
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("snapshot_dir", type=Path)
    parser.add_argument("reveal_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        make_sheet(args.snapshot_dir, args.reveal_dir, args.output)
    except (OSError, ValueError, KeyError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
