#!/usr/bin/env python3
"""The evaluation set's edge maps, as the app's two models make them (`Tests/EvalSet/maps`).

    tools/evalset_maps.py [--set Tests/EvalSet] [--weights DIR] [--only id,id] [--force]

For every photo of the set's `manifest.json` without its maps (or every one, with --force), writes
`<set>/maps/<id>-contours.png` (HED, `tools/models/convert_hed.py --map`) and `<id>-drawing.png`
(the line drawing, `convert_lineart.py --map`) from the photo at most 1152 px on the long side
(`EdgeDetector.maximumLongSide`; Lanczos), as 8-bit PNGs. `tools/scene_eval.py` reads them.

--weights DIR holds `ControlNetHED.pth` and `sk_model.pth` (the converters' docstrings say where
they come from; `huggingface_hub.hf_hub_download` of `lllyasviel/Annotators` fetches both);
default `$SCENE_WEIGHTS` or `.claude/weights`. Needs the converters' Python (torch, controlnet_aux,
numpy, Pillow).
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAXIMUM_LONG_SIDE = 1152


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", default=os.path.join(ROOT, "Tests", "EvalSet"))
    ap.add_argument("--weights", default=os.environ.get("SCENE_WEIGHTS", os.path.join(ROOT, ".claude", "weights")))
    ap.add_argument("--only")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    with open(os.path.join(args.set, "manifest.json")) as f:
        photos = json.load(f)["photos"]
    wanted = set(args.only.split(",")) if args.only else None
    maps = os.path.join(args.set, "maps")
    os.makedirs(maps, exist_ok=True)
    converters = {"contours": ("convert_hed.py", "ControlNetHED.pth"), "drawing": ("convert_lineart.py", "sk_model.pth")}
    with tempfile.TemporaryDirectory() as work:
        for photo in photos:
            pid = photo["id"]
            if wanted and pid not in wanted:
                continue
            outputs = {k: os.path.join(maps, f"{pid}-{k}.png") for k in converters}
            if not args.force and all(os.path.exists(p) for p in outputs.values()):
                continue
            path = os.path.normpath(os.path.join(args.set, photo["file"]))
            if not os.path.exists(path):
                print(f"{pid}: {path} is missing, skipped", file=sys.stderr)
                continue
            image = Image.open(path).convert("RGB")
            if max(image.size) > MAXIMUM_LONG_SIDE:
                image.thumbnail((MAXIMUM_LONG_SIDE, MAXIMUM_LONG_SIDE), Image.LANCZOS)
            ppm = os.path.join(work, pid + ".ppm")
            image.save(ppm)
            for kind, (script, weights) in converters.items():
                pgm = os.path.join(work, f"{pid}-{kind}.pgm")
                subprocess.run(
                    [sys.executable, os.path.join(ROOT, "tools", "models", script), "--weights", os.path.join(args.weights, weights),
                     "--map", ppm, pgm], check=True, stdout=subprocess.DEVNULL)
                Image.open(pgm).save(outputs[kind], optimize=True)
            print(f"maps {pid}")


if __name__ == "__main__":
    main()
