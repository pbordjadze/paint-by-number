#!/usr/bin/env python3
r"""Measure nickname-anchor traffic across every bundled library picture.

Build pbn with Swift 6.2, then run:
    python3 tools/factory/nickname_traffic.py --pbn /path/to/pbn \
        --work-dir /root/factory-out/F5/traffic

Requires Pillow. Converts the library's <id>.jpg files to full-size RGB PPM and
generates at GenerationSettings() defaults: 24 colors, detail/smoothness 0.5,
pipeline seed 0x5eed, coloringBook style, no tuning. Linux pbn has no app Vision
or line-detection models; no importance map is supplied. pbn requires an edge map
for coloringBook, so a full-size all-zero PGM supplies an explicit empty drawing.
This measures books with no detected lines at default generator settings, rather
than each photo's Auto suggestion or the app's model-derived line art.

Each template is named with seeds 0, 1, 42, 0x5eed and 0xdeadbeef, using frozen
vocabulary 1 and the real Swift assignment (including uniqueness resolution).
traffic.json is an array of all anchors: zero-based table index, uppercase hex
(without #), name, draws and share of all anchor assignments. Structured-name
fallbacks are excluded from that denominator and reported on stdout. Sort by
descending draws, then table index. No times or scratch paths enter the file.
PPMs, templates, stats and raw names stay in --work-dir, outside the repository;
every invocation regenerates them so stale templates cannot affect the counts.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / "App/PaintByNumber/Resources/Samples/library.json"
VOCABULARY = ROOT / "Sources/PaintCore/Foundation/ColorNicknameVocabulary.swift"
OUTPUT = ROOT / "factory/pieces/color-names/traffic.json"
SEEDS = (0, 1, 42, 0x5EED, 0xDEADBEEF)
GENERATE_OPTIONS = ("--colors", "24", "--detail", "0.5", "--smooth", "0.5",
                    "--seed", str(0x5EED), "--line-style", "coloringBook")


def vocabulary(path=VOCABULARY):
    table = path.read_text(encoding="utf-8").split('static let table = """', 1)[1].split('"""', 1)[0]
    anchors = []
    for line in table.splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r"([0-9A-F]{6}) (.+)", line)
        if match is None:
            raise ValueError(f"invalid vocabulary entry: {line!r}")
        anchors.append({"index": len(anchors), "hex": match[1], "name": match[2]})
    if not anchors or len({a["name"] for a in anchors}) != len(anchors):
        raise ValueError("nickname vocabulary must be nonempty with unique names")
    return anchors


def assigned_names(output):
    """Read pbn's numbered rows; the final hex is the paint, not the anchor."""
    names = []
    for number, line in enumerate(output.splitlines(), 1):
        match = re.fullmatch(r"\s*(\d+)\s+(.+?)\s+·\s+(.+?)\s+·\s+#[0-9A-F]{6}", line)
        if match is None or int(match[1]) != number:
            raise ValueError(f"unexpected pbn names row: {line!r}")
        names.append(match[2].strip())
    if not names:
        raise ValueError("pbn names returned no palette colors")
    return names


def traffic(anchors, counts):
    total = sum(counts[a["name"]] for a in anchors)
    rows = [{**a, "draws": counts[a["name"]],
             "share": counts[a["name"]] / total if total else 0.0} for a in anchors]
    return sorted(rows, key=lambda row: (-row["draws"], row["index"]))


def run(pbn, *arguments):
    return subprocess.check_output([str(pbn), *map(str, arguments)], text=True, encoding="utf-8")


def measure(pbn, work_dir, library=LIBRARY, anchors=None):
    work_dir = work_dir.resolve()
    if work_dir == ROOT or ROOT in work_dir.parents:
        raise ValueError("--work-dir must be outside the repository")
    pictures = json.loads(library.read_text(encoding="utf-8"))
    ids = [picture["id"] for picture in pictures]
    if not ids or len(set(ids)) != len(ids) or any(not re.fullmatch(r"[a-z0-9-]+", i) for i in ids):
        raise ValueError("library must contain unique picture ids")
    anchors = vocabulary() if anchors is None else anchors
    counts = Counter()
    assigned = 0
    for position, picture_id in enumerate(ids, 1):
        folder = work_dir / picture_id
        folder.mkdir(parents=True, exist_ok=True)
        ppm = folder / "source.ppm"
        edges = folder / "empty-edges.pgm"
        with Image.open(library.parent / f"{picture_id}.jpg") as image:
            image.convert("RGB").save(ppm)
            Image.new("L", image.size, 0).save(edges)
        run(pbn, "generate", ppm, folder, *GENERATE_OPTIONS, "--edges", edges)
        for seed in SEEDS:
            output = run(pbn, "names", folder / "template.pbnt", "--seed", seed, "--vocabulary", 1)
            (folder / f"names-{seed}.txt").write_text(output, encoding="utf-8")
            names = assigned_names(output)
            counts.update(names)
            assigned += len(names)
        print(f"{position}/{len(ids)} {picture_id}", flush=True)
    rows = traffic(anchors, counts)
    draws = sum(row["draws"] for row in rows)
    print(f"{len(ids)} pictures × {len(SEEDS)} seeds: {draws} anchor assignments, "
          f"{assigned - draws} structured-name fallbacks", flush=True)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pbn", type=Path, default=ROOT / ".build/release/pbn")
    parser.add_argument("--work-dir", type=Path, default=Path("/root/factory-out/nickname-traffic"))
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    rows = measure(args.pbn.resolve(), args.work_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(rows)} anchors to {args.output}")


if __name__ == "__main__":
    main()
