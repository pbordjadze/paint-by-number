"""Nickname traffic checks: python3 -m unittest discover -s tools/factory -p 'test_nickname_traffic.py'."""
from collections import Counter
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

import nickname_traffic as nt

TEST_OUT = os.environ.get("FACTORY_TEST_OUT", tempfile.gettempdir())


class NicknameTrafficTests(unittest.TestCase):
    def test_counts_resolved_names_and_keeps_zero_traffic_anchors(self):
        anchors = [{"index": i, "hex": h, "name": n} for i, (h, n) in enumerate([
            ("98A2A8", "Harbor Fog"), ("2B2D30", "Wet Asphalt"), ("F4F7FA", "Snowdrift")])]
        # Paint hexes differ from anchor hexes; fallbacks must not become anchors.
        output = "  1  Wet Asphalt       · dark gray · #292929\n  2  Harbor Fog        · light gray · #999999\n  3  Dark green        · dark green · #002200\n"
        counts = Counter(nt.assigned_names(output))
        counts.update(["Wet Asphalt"])
        rows = nt.traffic(anchors, counts)
        self.assertEqual([r["index"] for r in rows], [1, 0, 2])
        self.assertEqual([r["draws"] for r in rows], [2, 1, 0])
        self.assertEqual([r["share"] for r in rows], [2 / 3, 1 / 3, 0])
        self.assertEqual(rows[0]["hex"], "2B2D30")

    def test_ties_follow_table_order_and_empty_counts_have_zero_shares(self):
        anchors = nt.vocabulary()
        rows = nt.traffic(anchors, Counter())
        self.assertEqual(rows, [{**a, "draws": 0, "share": 0.0} for a in anchors])

    def test_unexpected_names_output_fails_instead_of_silently_losing_draws(self):
        for output in ("", "unexpected", "  2  Harbor Fog · light gray · #999999"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                nt.assigned_names(output)

    def test_work_directory_cannot_be_in_repository(self):
        with self.assertRaisesRegex(ValueError, "outside the repository"):
            nt.measure(Path("pbn"), nt.ROOT / "scratch")

    def test_every_catalog_picture_is_converted_generated_and_named_five_times(self):
        with tempfile.TemporaryDirectory(dir=TEST_OUT) as temporary:
            folder = Path(temporary)
            library = folder / "library.json"
            library.write_text(json.dumps([{"id": "second"}, {"id": "first"}]))
            for picture_id in ("second", "first"):
                Image.new("RGB", (16, 12), "#98A2A8").save(folder / f"{picture_id}.jpg")
            anchors = [{"index": 0, "hex": "98A2A8", "name": "Harbor Fog"}]
            calls = []

            def fake_run(pbn, *args):
                calls.append(args)
                if args[0] == "generate":
                    with Image.open(args[1]) as image:
                        self.assertEqual((image.format, image.mode, image.size), ("PPM", "RGB", (16, 12)))
                    self.assertEqual(args[3:-2], nt.GENERATE_OPTIONS)
                    self.assertEqual(args[-2], "--edges")
                    with Image.open(args[-1]) as image:
                        self.assertEqual((image.mode, image.size, image.getextrema()), ("L", (16, 12), (0, 0)))
                    (args[2] / "template.pbnt").write_bytes(b"template")
                    return "{}"
                self.assertTrue(args[1].is_file())
                self.assertEqual(args[4:], ("--vocabulary", 1))
                return "  1  Harbor Fog        · light gray · #999999\n"

            with patch.object(nt, "run", side_effect=fake_run):
                first = nt.measure(Path("pbn"), folder / "work", library, anchors)
                second = nt.measure(Path("pbn"), folder / "work", library, anchors)
            self.assertEqual(first, [{**anchors[0], "draws": 10, "share": 1.0}])
            self.assertEqual(json.dumps(first), json.dumps(second))
            self.assertEqual(len(calls), 24)
            self.assertEqual([call[3] for call in calls if call[0] == "names"], list(nt.SEEDS) * 4)


if __name__ == "__main__":
    unittest.main()
