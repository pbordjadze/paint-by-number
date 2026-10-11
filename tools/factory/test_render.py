"""Focused tests for the pixel gate and review-frame selection: python3 -m unittest discover
-s tools/factory -p 'test_*.py'. The full CLI/render contract is exercised by verify.py.
"""
import unittest
from unittest.mock import patch
import os
import xml.etree.ElementTree as ET
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

import render
import verify

TEST_OUT = os.environ.get("FACTORY_TEST_OUT", tempfile.gettempdir())


class ReviewTests(unittest.TestCase):
    def test_rasterizer_resolves_reference_beside_the_svg(self):
        with tempfile.TemporaryDirectory(prefix="figure-raster-test-", dir=TEST_OUT) as temporary:
            folder = Path(temporary)
            Image.new("RGB", (4, 4), "#BFD3D8").save(folder / "background & painting.png")
            svg = folder / "frame.svg"
            svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4">'
                           '<image href="background &amp; painting.png" width="4" height="4"/></svg>')
            jobs = folder / "jobs.json"
            jobs.write_text(json.dumps([{ "input": str(svg), "output": str(folder / f"frame-{i}.png") } for i in range(4)]))
            subprocess.run(["node", str(render.ROOT / "tools/factory/rasterize.mjs"), str(jobs)], check=True, cwd="/tmp")
            self.assertTrue(all((folder / f"frame-{i}.png").read_bytes() == (folder / "frame-0.png").read_bytes() for i in range(4)))
            with Image.open(folder / "frame-0.png") as image:
                self.assertEqual(image.getpixel((2, 2)), (191, 211, 216, 255))

    def test_parallel_composition_preserves_alpha_and_is_deterministic(self):
        with tempfile.TemporaryDirectory(prefix="f1-composite-", dir=TEST_OUT) as temporary:
            folder = Path(temporary)
            paths = [folder / f"frame-{i}.png" for i in range(4)]
            for path in paths:
                Image.new("RGBA", (4, 4), (255, 0, 0, 128)).save(path)
            render.composite_frames(paths, Image.new("RGB", (4, 4), (100, 100, 100)), folder)
            self.assertTrue(all(path.read_bytes() == paths[0].read_bytes() for path in paths))
            with Image.open(paths[0]) as image:
                self.assertEqual(image.getpixel((2, 2)), (178, 50, 50))

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


class ReviewFixTests(unittest.TestCase):
    def test_actual_hairpin_ink_has_no_raster_holes(self):
        with tempfile.TemporaryDirectory(prefix="f1-hairpin-", dir=TEST_OUT) as temporary:
            folder = Path(temporary)
            command = verify.swift_test_command(skip_build=True, filter="inkHairpinFillRule")
            result = subprocess.run(command, cwd=render.ROOT,
                           env={**os.environ, "FIGURE_TEST_ARTIFACTS": temporary},
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            if result.returncode or not (folder / 'hairpin.svg').is_file():
                self.fail('missing Swift test build or failed hairpin test; run swift test with the same '
                          'SWIFT_SCRATCH_PATH first. Command: ' + ' '.join(command) + '\n' + result.stdout)
            tree = render.isolated(ET.parse(folder / "hairpin.svg").getroot(), "figure")
            tree.set("viewBox", "390 190 120 70"); tree.set("width", "120"); tree.set("height", "70")
            render.write_svg(tree, folder / "hairpin.svg")
            jobs = [{"input": str(folder / "hairpin.svg"), "output": str(folder / "hairpin.png"), "width": 1200}]
            (folder / "jobs.json").write_text(json.dumps(jobs))
            subprocess.run(["node", str(render.ROOT / "tools/factory/rasterize.mjs"), str(folder / "jobs.json")], check=True)
            with Image.open(folder / "hairpin.png") as image:
                alpha = image.getchannel("A")
                transparent = alpha.point(lambda value: 255 if value < 128 else 0)
                render.ImageDraw.floodfill(transparent, (0, 0), 128)
                holes = transparent.histogram()[255]
                self.assertEqual(holes, 0)
                self.assertGreater(sum(alpha.histogram()[128:]), 10000)

    def test_render_returns_failure_for_failed_checks(self):
        with tempfile.TemporaryDirectory(prefix="f1-status-", dir=TEST_OUT) as temporary:
            folder = Path(temporary)
            for name, data in [("spec", {}), ("scene", {}), ("manifest", {"fps": 24, "frameCount": 1, "pixelWidth": 4}),
                               ("motion", []), ("checks", [{"name": "ikClamps", "pass": False}])]:
                (folder / (name + ".json")).write_text(json.dumps(data))
            args = ["render.py", str(folder / "spec.json"), str(folder / "scene.json"), temporary,
                    "--figures", str(Path(__file__))]
            with patch("sys.argv", args), patch.object(render, "render_engine"), \
                    patch.object(render, "run"), patch.object(render, "compose"):
                self.assertEqual(render.main(), 1)
                (folder / "checks.json").write_text('[{"name":"ikClamps","pass":true}]')
                self.assertEqual(render.main(), 0)

    def test_missing_review_font_is_reported_clearly(self):
        args = ["render.py", "spec.json", "scene.json", "/root/factory-out/f1-font"]
        with patch("sys.argv", args), patch.object(render.ImageFont, "truetype", side_effect=OSError), \
                patch("sys.stderr") as stderr:
            with self.assertRaises(SystemExit) as caught:
                render.main()
            self.assertEqual(caught.exception.code, 2)
            self.assertIn("missing DejaVu Sans", "".join(call.args[0] for call in stderr.write.call_args_list))

    def test_frames_only_keeps_the_render_and_checks_without_running_encoders(self):
        with tempfile.TemporaryDirectory(prefix="f16-frames-", dir=TEST_OUT) as temporary:
            folder = Path(temporary)
            for name, data in [("spec", {}), ("scene", {}), ("manifest", {"frameCount": 1}),
                               ("motion", []), ("checks", [{"name": "ikClamps", "pass": True}])]:
                (folder / (name + ".json")).write_text(json.dumps(data))
            args = ["render.py", str(folder / "spec.json"), str(folder / "scene.json"), temporary,
                    "--figures", str(Path(__file__)), "--frames-only"]
            with patch("sys.argv", args), patch.object(render, "run") as run, \
                    patch.object(render, "render_engine") as engine, patch.object(render, "compose") as compose:
                self.assertEqual(render.main(), 0)
                compose.assert_called_once()
                engine.assert_called_once()
                run.assert_not_called()

    def test_protected_source_diff_detects_committed_changes(self):
        with tempfile.TemporaryDirectory(prefix="f1-git-", dir=TEST_OUT) as temporary:
            root = Path(temporary)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.STDOUT)
            git("init"); git("config", "user.name", "Test"); git("config", "user.email", "test@example.com")
            git("config", "commit.gpgsign", "false")
            source = root / "Sources/PaintCore/example.swift"
            source.parent.mkdir(parents=True); source.write_text("before")
            git("add", "."); git("commit", "-m", "fixture [skip ci]")
            git("update-ref", "refs/remotes/origin/claude/vibe-factory", "HEAD")
            self.assertEqual(verify.protected_source_diff(root), b"")
            source.write_text("after"); git("add", "."); git("commit", "-m", "change [skip ci]")
            self.assertEqual(git("diff", "HEAD", "--", "Sources/PaintCore"), b"")
            self.assertNotEqual(verify.protected_source_diff(root), b"")


if __name__ == "__main__":
    unittest.main()
