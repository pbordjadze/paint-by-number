"""Reveal sheet checks and CLI integration; set FIGURES_BIN to the built executable."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from PIL import Image

import reveal_sheet

TEST_OUT = os.environ.get("FACTORY_TEST_OUT", tempfile.gettempdir())
FIGURES = os.environ.get("FIGURES_BIN")


class SheetTests(unittest.TestCase):
    def test_wipe_distinguishes_unchanged_and_zero_time(self):
        before = Image.new("RGB", (4, 1), (30, 40, 50))
        after = Image.new("RGB", (4, 1), (230, 240, 250))
        field = Image.new("L", (4, 1)); field.putdata([0, 1, 128, 255])
        for time, expected in [(0, [False, True, False, False]),
                               (0.5, [False, True, True, False]),
                               (1, [False, True, True, True])]:
            frame = reveal_sheet.wipe(before, after, field, time)
            self.assertEqual([frame.getpixel((x, 0)) for x in range(4)],
                             [(230, 240, 250) if changed else (30, 40, 50) for changed in expected])

    def test_empty_and_absolute_paths(self):
        self.assertEqual(reveal_sheet.path_points(""), [])
        self.assertEqual(reveal_sheet.path_points("M 0.50 2.50 L 3.00 4.00"), [(0.5, 2.5), (3, 4)])
        for path in ["M 1", "m 1 2", "L 1 2", "M 1 2 C 3 4"]:
            with self.assertRaises(ValueError):
                reveal_sheet.path_points(path)


@unittest.skipUnless(FIGURES, "set FIGURES_BIN for CLI integration")
class CLITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="reveal-", dir=TEST_OUT)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.snapshots = self.root / "snapshots"; self.snapshots.mkdir()
        first = Image.new("RGB", (8, 4), (0, 0, 0))
        first.save(self.snapshots / "working-image.ppm")
        gray = Image.new("L", (8, 4), 0)
        gray.paste(255, (4, 0, 8, 4)); gray.save(self.snapshots / "structure.pgm")
        gray.convert("RGB").save(self.snapshots / "smoothed.ppm")
        gray.save(self.snapshots / "vectorized.pgm")
        # pbn's ordinary previews in the same directory must never be paired.
        first.save(self.snapshots / "working.ppm")
        first.save(self.snapshots / "raster.ppm")

    def run_cli(self, out, *options):
        return subprocess.run([FIGURES, "reveal", str(self.snapshots), str(out), *options],
                              capture_output=True, text=True)

    def test_every_option_and_byte_identical_bundles(self):
        for seed in ("left", "center", "strongest"):
            first, second = self.root / seed, self.root / (seed + "-again")
            for out in (first, second):
                result = self.run_cli(out, "--seed", seed, "--steps", "5")
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(sorted(p.name for p in first.iterdir()), sorted(p.name for p in second.iterdir()))
            self.assertEqual(len(list(first.iterdir())), 6)
            for file in first.iterdir():
                self.assertEqual(file.read_bytes(), (second / file.name).read_bytes())
            record = json.loads((first / "working-image-structure.json").read_text())
            self.assertEqual(set(record), {"width", "height", "changed", "seed", "steps", "path"})
            self.assertEqual((record["width"], record["height"], record["changed"], record["seed"], record["steps"]),
                             (8, 4, 0.5, seed, 5))
            self.assertEqual(json.loads((first / "structure-smoothed.json").read_text())["path"], "")
            sheet = self.root / (seed + ".png")
            reveal_sheet.make_sheet(self.snapshots, first, sheet)
            with Image.open(sheet) as image:
                self.assertEqual(image.size, (104, 156))
        default = self.root / "default"
        self.assertEqual(self.run_cli(default).returncode, 0)
        record = json.loads((default / "working-image-structure.json").read_text())
        self.assertEqual((record["seed"], record["steps"]), ("left", 12))

    def test_invalid_options_and_mismatched_snapshots_fail_before_writing(self):
        for options in [("--seed", "bad"), ("--steps", "0"), ("--steps", "-1"),
                        ("--steps", "x"), ("--steps",), ("--wat", "1"),
                        ("--seed", "left", "--seed", "center")]:
            out = self.root / "invalid"
            self.assertNotEqual(self.run_cli(out, *options).returncode, 0)
            self.assertFalse(out.exists())
        Image.new("L", (2, 2)).save(self.snapshots / "vectorized.pgm")
        out = self.root / "mismatched"
        result = self.run_cli(out)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("same positive size", result.stderr)
        self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main()
