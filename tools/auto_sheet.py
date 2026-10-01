#!/usr/bin/env python3
"""Contact sheets of Auto's decisions, for judging suggested settings by eye.

    tools/auto_sheet.py DIR... [--out DIR]

Each DIR is a `pbn suggest <photo> --out DIR` output (decision.json, working.ppm,
candidate-<i>.ppm and candidate-<i>-boundaries.ppm), or a directory of such outputs. For
every decision it writes `auto-sheet.jpg` next to it (or `<out>/<name>.jpg` with --out): the
draft photo and its analysis, then every candidate's painted preview over its region
outlines with its settings and score terms; the winner is framed in green.

Requires Pillow.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

PANEL_W = 480
COLUMNS = 3
LINE = 22
GREEN = (20, 160, 60)


def decision_dirs(paths):
    for path in paths:
        if os.path.exists(os.path.join(path, "decision.json")):
            yield path
        elif os.path.isdir(path):
            for name in sorted(os.listdir(path)):
                sub = os.path.join(path, name)
                if os.path.exists(os.path.join(sub, "decision.json")):
                    yield sub


def analysis_lines(decision):
    a = decision["analysis"]
    curve = " ".join(f"{k}:{v:.3f}" for k, v in zip([8, 12, 16, 24, 32, 48, 64], a["paletteCurve"]))
    lines = [
        f"source {a['sourceWidth']}x{a['sourceHeight']}   length {decision['preference']}",
        f"curve {curve}",
        f"chromatic {a['chromaticFraction']:.3f}  spread {a['chromaSpread']:.3f}  noise {a['noise']:.3f}",
        f"structure {a['structureDensity']:.3f}  texture {a['textureFraction']:.3f}  smooth {a['smoothFraction']:.3f}",
        f"subject {a['subjectCoverage']:.3f}  entropy {a['importanceEntropy']:.3f}",
        f"faces {a['faceCoverage']:.3f}  animals {a['animalCoverage']:.3f}",
    ]
    if a.get("labels"):
        lines.append("labels " + ", ".join(f"{k} {v:g}" for k, v in sorted(a["labels"].items())))
    return lines


def candidate_lines(index, candidate, winner):
    s = candidate["settings"]
    lines = [f"#{index}{'  WINNER' if winner else ''}   {s['colorCount']} colors  detail {s['detail']:g}  "
             f"smooth {s['smoothness']:g}"]
    score = candidate.get("score")
    if score is None:
        return lines + ["not run"]
    return lines + [
        f"regions {score['regions']}  ~{score['estimatedSeconds'] / 60:.0f} min  rings {score['bandRings']}  "
        f"tiny {score['tinyRegions']}",
        f"dE {score['fidelity']:.4f}  p95 {score['fidelityP95']:.4f}  room {score['minLabelRoom']:.2f}",
        f"band {score['bandPenalty']:.4f}  total {score['total']:.4f}",
    ]


def sheet(directory):
    with open(os.path.join(directory, "decision.json")) as f:
        decision = json.load(f)
    working = Image.open(os.path.join(directory, "working.ppm")).convert("RGB")
    panel_h = round(working.height * PANEL_W / working.width)
    font = ImageFont.load_default(size=16)
    title_font = ImageFont.load_default(size=20)
    text_h = LINE * 4 + 10
    cell_h = 2 * panel_h + text_h
    cells = 1 + len(decision["candidates"])
    rows = (cells + COLUMNS - 1) // COLUMNS
    header = 40
    out = Image.new("RGB", (COLUMNS * PANEL_W + (COLUMNS + 1) * 8, header + rows * (cell_h + 8) + 8), "white")
    d = ImageDraw.Draw(out)
    name = os.path.basename(os.path.normpath(directory))
    d.text((10, 8), f"{name}: Auto, {decision['preference']}, winner #{decision['winner']}", fill=(0, 0, 0),
           font=title_font)

    def origin(cell):
        return 8 + (cell % COLUMNS) * (PANEL_W + 8), header + (cell // COLUMNS) * (cell_h + 8)

    x, y = origin(0)
    out.paste(working.resize((PANEL_W, panel_h), Image.LANCZOS), (x, y))
    for i, line in enumerate(analysis_lines(decision)):
        d.text((x + 4, y + panel_h + 8 + LINE * i), line, fill=(40, 40, 40), font=font)

    for i, candidate in enumerate(decision["candidates"]):
        x, y = origin(i + 1)
        for k, suffix in enumerate(("", "-boundaries")):
            path = os.path.join(directory, f"candidate-{i}{suffix}.ppm")
            if os.path.exists(path):
                img = Image.open(path).convert("RGB").resize((PANEL_W, panel_h), Image.LANCZOS)
                out.paste(img, (x, y + k * panel_h))
        winner = i == decision["winner"]
        for j, line in enumerate(candidate_lines(i, candidate, winner)):
            d.text((x + 4, y + 2 * panel_h + 6 + LINE * j), line, fill=GREEN if winner and j == 0 else (40, 40, 40),
                   font=font)
        if winner:
            d.rectangle([x - 5, y - 5, x + PANEL_W + 4, y + cell_h + 2], outline=GREEN, width=5)
    return out


def main(argv):
    out_dir = None
    paths = []
    it = iter(argv)
    for a in it:
        if a == "--out":
            out_dir = next(it, None)
        elif a.startswith("-"):
            print(__doc__, file=sys.stderr)
            return 2
        else:
            paths.append(a)
    if not paths or (out_dir is None and "--out" in argv):
        print(__doc__, file=sys.stderr)
        return 2
    written = 0
    for directory in decision_dirs(paths):
        image = sheet(directory)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
            target = os.path.join(out_dir, os.path.basename(os.path.normpath(directory)) + ".jpg")
        else:
            target = os.path.join(directory, "auto-sheet.jpg")
        image.save(target, quality=88)
        print(target)
        written += 1
    if not written:
        print("no decision.json found (run pbn suggest <photo> --out DIR first)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
