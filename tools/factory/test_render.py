"""Focused tests for the pixel gate and review-frame selection: python3 -m unittest discover
-s tools/factory -p 'test_*.py'. The full CLI/render contract is exercised by verify.py.
"""
import unittest
import xml.etree.ElementTree as ET
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

import render


class ReviewTests(unittest.TestCase):
    def test_rasterizer_resolves_reference_beside_the_svg(self):
        with tempfile.TemporaryDirectory(prefix="figure-raster-test-") as temporary:
            folder = Path(temporary)
            Image.new("RGB", (4, 4), "#BFD3D8").save(folder / "background & painting.png")
            svg = folder / "frame.svg"
            svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4">'
                           '<image href="background &amp; painting.png" width="4" height="4"/></svg>')
            jobs = folder / "jobs.json"
            jobs.write_text(json.dumps([{"input": str(svg), "output": str(folder / "frame.png")}]))
            subprocess.run(["node", str(render.ROOT / "tools/factory/rasterize.mjs"), str(jobs)], check=True, cwd="/tmp")
            with Image.open(folder / "frame.png") as image:
                self.assertEqual(image.getpixel((2, 2)), (191, 211, 216, 255))

    def test_wcag_contrast_measures_under_the_figure(self):
        background = Image.new("RGB", (4, 4), "white")
        background.putpixel((0, 0), (0, 0, 0))
        mask = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
        mask.putpixel((3, 3), (0, 0, 0, 255))
        self.assertEqual(render.ink_contrast(background, [mask], "#000000"), 21)
        mask.putpixel((0, 0), (0, 0, 0, 255))
        self.assertEqual(render.ink_contrast(background, [mask], "#000000"), 1)

    def test_transparent_layers_keep_defs_and_remove_background(self):
        tree = ET.fromstring('<svg xmlns="http://www.w3.org/2000/svg"><defs/><rect data-layer="background"/>'
                             '<path data-layer="figure"/><path data-layer="particles"/><path data-layer="card"/></svg>')
        isolated = render.isolated(tree, ["figure", "particles"])
        self.assertEqual(len(isolated), 3)
        self.assertEqual(len(tree), 5)
        self.assertEqual([p.get("data-layer") for p in list(isolated)[1:]], ["figure", "particles"])

    def test_review_keys_follow_pose_quantization_and_clip_bounds(self):
        manifest = {"fps": 24, "frameCount": 100, "duration": 4.1, "actions": [
            {"kind": "walk", "start": 0, "end": 2},
            {"kind": "cast", "start": 2, "end": 4.1, "windUp": 2.13, "release": 3.13}]}
        keys = render.key_frames(manifest, {})
        self.assertEqual([frame for _, frame in keys], [24, 52, 76, 99])
        singles = render.key_frames(manifest, {"motion": {"onTwos": False}})
        self.assertEqual([frame for _, frame in singles], [24, 52, 76, 99])
        manifest["actions"][1]["release"] = 3.01
        self.assertEqual(render.key_frames(manifest, {"motion": {"onTwos": False}})[2][1], 73)
        self.assertEqual(render.key_frames(manifest, {})[2][1], 74)


if __name__ == "__main__":
    unittest.main()
