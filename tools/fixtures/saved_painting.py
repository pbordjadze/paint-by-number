#!/usr/bin/env python3
"""Writes the frozen saved painting `App/PaintByNumberTests/Saved15-*`: one painting's folder as
1.5 (build 109.1, main 0d726f8) leaves it on disk, a painting begun and refined, which every later
build must open with its progress (`SavedPaintingTests`). Never run it again over the committed
files: like the template fixtures, they are frozen, and a build that can't read them is the bug.

Each file is in the format 1.5 writes it in (the app's encoders at 0d726f8, which no format
change has touched since: `git diff 0d726f8 -- App/PaintByNumber/Model/Artwork.swift
App/Shared/Model/PaintProgress.swift App/PaintByNumber/Generation/TemplateRefinements.swift`):
  meta.json         `ArtworkStore.writeMeta`: JSONEncoder, pretty printed, sorted keys, dates
                    as seconds since 2001; the settings as pbn's stats.json encodes them (the
                    same `GenerationSettings` encoder)
  template.pbnt     `Template.encoded()` (pbn's template.pbnt) in LZFSE's stored-block framing,
                    which the app's LZFSE decoder reads as it reads its own compressed files
  progress.bin      `PaintProgress.encoded()`: "PBPR", version 1, regions, seconds, the strokes,
                    the paint in hand (1.2's trailing field)
  refinements.json  `TemplateRefinements`, one drawn line, editor version 7
  source.jpg        the photo (copied)
  thumbnail.png     pbn's areas.ppm, 256 px (Pillow), standing in for the gallery's picture

  tools/swift.sh build --product pbn
  .build/debug/pbn generate Tests/Corpus/<photo>.ppm <out> --auto --paint-mix beauty
  tools/fixtures/saved_painting.py <out> <photo.jpg> App/PaintByNumberTests
(the committed files: hibiscus at 384×256 with its maps from tools/baseline/lines/, --length relaxed)
"""
import json
import shutil
import struct
import sys
import uuid

from PIL import Image
from pathlib import Path

ID = "5A1E0015-0000-4000-8000-0000000000B5"
CREATED = 817_250_400.0  # November 24, 2026, 5 PM ET (1.5's day), seconds since 2001
PAINTED = [0, 2, 3, 5, 8, 13]


def lzfse_stored(raw: bytes) -> bytes:
    return b"bvx-" + struct.pack("<I", len(raw)) + raw + b"bvx$"


def progress(regions: int) -> bytes:
    out = struct.pack("<IIId", 0x52504250, 1, regions, 321.5)
    out += struct.pack("<I", len(PAINTED))
    for i, region in enumerate(PAINTED):
        out += struct.pack("<If", region, 12.0 * (i + 1))
    return out + struct.pack("<I", 2 + 1)  # paint 2 in hand


def main() -> None:
    out, photo, dest = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    stats = json.loads((out / "stats.json").read_text())
    # Auto's choice, with the mix pbn laid on it (`--paint-mix beauty`), as a new painting records.
    settings = dict(stats["auto"]["settings"], paintMix="beauty")
    regions = stats["regions"]
    assert max(PAINTED) < regions
    meta = {
        "activeSeconds": 321.5,
        "colorCount": stats["colors"],
        "createdAt": CREATED,
        "format": 2,
        "height": stats["height"],
        "id": str(uuid.UUID(ID)).upper(),
        "isFavorite": True,
        "modifiedAt": CREATED + 3600,
        "nicknameVersion": 2,
        "paintedCount": len(PAINTED),
        "paintingLength": "relaxed",
        "pipelineVersion": 14,
        "regionCount": regions,
        "settings": settings,
        "settingsOrigin": "suggested",
        "thumbnailVersion": 1,
        "title": "Saved by 1.5",
        "titled": True,
        "width": stats["width"],
    }
    w, h = stats["width"], stats["height"]
    refinements = {
        "edits": [{"kind": "draw", "points": [[w * 0.2, h * 0.5], [w * 0.8, h * 0.5]], "closed": False, "paints": []}],
        "editorVersion": 7,
    }
    files = {
        "meta.json": json.dumps(meta, indent=2, sort_keys=True).encode(),
        "template.pbnt": lzfse_stored((out / "template.pbnt").read_bytes()),
        "progress.bin": progress(regions),
        "refinements.json": json.dumps(refinements, separators=(",", ":")).encode(),
    }
    for name, data in files.items():
        (dest / f"Saved15-{name}").write_bytes(data)
    shutil.copy(photo, dest / "Saved15-source.jpg")
    thumbnail = Image.open(out / "areas.ppm")
    thumbnail.thumbnail((256, 256))
    thumbnail.save(dest / "Saved15-thumbnail.png")


if __name__ == "__main__":
    main()
