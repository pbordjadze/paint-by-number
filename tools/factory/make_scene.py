#!/usr/bin/env python3
"""Rebuild hero-painted.png and hero-template.png using the real, unchanged pbn pipeline.

Prerequisites: npm ci --prefix tools; Pillow; a host pbn binary, built with
tools/swift.sh build -c release --product pbn --static-swift-stdlib.
All intermediate pipeline output lives in a temporary directory outside the repository.
"""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pbn", type=Path, default=ROOT / ".build/release/pbn")
    args = parser.parse_args()
    from PIL import Image
    scene = ROOT / "factory/scenes"
    with tempfile.TemporaryDirectory(prefix="figure-hero-") as temporary:
        scratch = Path(temporary)
        jobs = scratch / "jobs.json"
        jobs.write_text(json.dumps([{"input": str(scene / "hero.svg"),
                                     "output": str(scratch / "hero.png"), "width": 1100}]))
        subprocess.run(["node", str(ROOT / "tools/factory/rasterize.mjs"), str(jobs)], check=True)
        with Image.open(scratch / "hero.png") as image:
            image.convert("RGB").save(scratch / "hero.ppm")
        subprocess.run([str(args.pbn.resolve()), "generate", str(scratch / "hero.ppm"), str(scratch / "painting")], check=True)
        jobs.write_text(json.dumps([
            {"input": str(scratch / f"painting/{name}.svg"), "output": str(scene / f"hero-{name}.png"), "width": 1100}
            for name in ["painted", "template"]]))
        subprocess.run(["node", str(ROOT / "tools/factory/rasterize.mjs"), str(jobs)], check=True)


if __name__ == "__main__":
    main()
