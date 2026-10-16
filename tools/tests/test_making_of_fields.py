"""The making-of show with no crew (tools/factory/making_of_fields.py): its fields by hand, and the
show built from the small show fixture.

    python3 -m unittest discover -s tools/tests -p 'test_making_of_fields.py'

Needs numpy and Pillow."""

import json
import math
from pathlib import Path
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "factory"))
import making_of_fields as fields
import making_of_show as show_module

SNAPSHOTS = ROOT / "Tests" / "MakingOfTests" / "Fixtures" / "show-small"
RESOURCES = ROOT / "App" / "PaintByNumber" / "Resources"
SEED = 7


def load_spec():
    return json.loads((RESOURCES / "making-of.json").read_text(encoding="utf-8"))


def small_show():
    return fields.FieldShow(str(SNAPSHOTS), str(SNAPSHOTS / "template.svg"), load_spec(), SEED)


class GeodesicTests(unittest.TestCase):
    def test_a_uniform_field_is_nearly_the_distance(self):
        T = fields.geodesic(np.ones((41, 41)), [(0.0, 20, 20)])
        ys, xs = np.mgrid[0:41, 0:41]
        d = np.hypot(xs - 20, ys - 20)
        self.assertEqual(T[20, 40], 20.0)                       # straight along a row
        self.assertAlmostEqual(T[40, 40], 20 * math.sqrt(2))    # and along a diagonal
        far = d > 5
        self.assertLess(np.max(np.abs(T[far] - d[far]) / d[far]), 0.09)   # eight neighbours: within 8 %

    def test_seeds_start_at_their_time(self):
        T = fields.geodesic(np.ones((9, 9)), [(5.0, 0, 0), (1.0, 8, 8)])
        self.assertEqual(T[0, 0], 5.0)
        self.assertEqual(T[8, 8], 1.0)
        self.assertEqual(T[4, 8], 5.0)                          # four cells from the seed lit at 1

    def test_a_wall_holds_the_front_back(self):
        cost = np.ones((21, 21))
        cost[:, 10] = 50.0
        T = fields.geodesic(cost, [(0.0, 2, 10)])
        self.assertGreater(T[10, 18], T[10, 2] + 50)            # through the wall, never round it

    def test_a_start_field_is_a_front_of_its_own(self):
        start = np.full((5, 9), np.inf)
        start[:, 0] = 0.0
        T = fields.geodesic(np.ones((5, 9)), start=start)
        self.assertTrue(np.array_equal(T, np.tile(np.arange(9.0), (5, 1))))


class PacedTests(unittest.TestCase):
    def test_an_outlier_doesnt_rush_the_rest(self):
        T = np.concatenate([np.arange(1000.0), [1e9]])
        out = fields.paced(T, 10.0, 12.0)
        self.assertEqual(out.min(), 10.0)
        self.assertEqual(out.max(), 12.0)
        self.assertTrue(np.all(np.diff(out) >= 0))              # nothing changes order
        # half the picture by about half time; a plain stretch would leave it all to the first instant
        self.assertTrue(10.7 < float(np.median(out)) < 11.1)

    def test_it_paces_over_a_mask_and_sends_inf_last(self):
        T = np.array([0.0, 1.0, 2.0, 3.0, 4.0, 100.0, np.inf])
        over = np.array([True] * 5 + [False] * 2)
        out = fields.paced(T, 0.0, 1.0, over=over)
        self.assertEqual((out[0], out[4], out[5], out[6]), (0.0, 1.0, 1.0, 1.0))
        self.assertTrue(np.all(np.diff(out) >= 0))

    def test_cells_of_one_time_change_together(self):
        T = np.array([0.0] * 10 + [1.0] * 10 + [2.0] * 10)
        out = fields.paced(T, 0.0, 1.0)
        self.assertEqual(len(set(out[10:20])), 1)
        self.assertTrue(0.3 < out[15] < 0.7)


class FieldShowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.show = small_show()
        cls.starts = [cls.show.intro + k * cls.show.step for k in range(7)]

    def test_each_step_changes_within_itself(self):
        s = self.starts
        for name, k in (("sketch", 0), ("shading", 1), ("paints", 2), ("merged", 3), ("lift", 4), ("clear", 5)):
            T = self.show.times[name]
            self.assertGreaterEqual(float(T.min()), s[k], name)
            self.assertLessEqual(float(T.max()), s[k + 1] - 0.1, name)

    def test_every_line_burns_in_the_ink_step_with_time_to_darken(self):
        ramp = load_spec()["outlines"]["inkRamp"]
        for at in self.show.fuses:
            self.assertGreaterEqual(float(at.min()), self.starts[4])
            self.assertLessEqual(float(at.max()) + ramp, self.starts[5])
        lines, _ = self.show.burning(self.starts[5] - 1e-6)
        drawn = {line["stroke"] for line in lines}
        self.assertEqual(drawn, {s.index for s in self.show.strokes})
        self.assertTrue(all(line["value"] == 1.0 for line in lines))

    def test_numbers_come_out_after_their_area_clears(self):
        H, W = self.show.times["clear"].shape
        for (x, y, _), at in zip(self.show.built.numbers, self.show.number_times):
            clear = float(self.show.times["clear"][min(max(int(y), 0), H - 1), min(max(int(x), 0), W - 1)])
            self.assertGreater(at, clear)
            self.assertLessEqual(at, self.starts[6])

    def test_the_paints_drop_the_crew_shows_own_seeds(self):
        pictures, template, built = show_module.crew_inputs(
            str(SNAPSHOTS), str(SNAPSHOTS / "template.svg"), load_spec(), SEED)
        self.assertEqual(self.show.seeds, built.seeds)

    def test_the_same_show_twice(self):
        again = small_show()
        for name, T in self.show.times.items():
            self.assertTrue(np.array_equal(T, again.times[name]), name)
        self.assertEqual(self.show.number_times, again.number_times)
        for a, b in zip(self.show.fuses, again.fuses):
            self.assertTrue(np.array_equal(a, b))

    def test_frames_have_no_crew_and_their_own_marks(self):
        s = self.starts
        self.assertEqual(self.show.duration, s[6] + fields.OUTRO)
        for t in np.linspace(0, self.show.duration - 1e-6, 40):
            frame = self.show.frame(float(t))
            self.assertEqual(frame["sprites"], [])
            picture = self.show.composite(frame)
            self.assertEqual(picture.shape, (self.show.size[1], self.show.size[0], 3))
            self.assertTrue(np.isfinite(picture).all())
        self.assertTrue(any(self.show.frame(s[4] + f * self.show.step)["sparks"] for f in (0.2, 0.4, 0.6)))
        self.assertTrue(any(self.show.frame(s[5] + f * self.show.step)["stars"] for f in (0.5, 0.7, 0.9)))
        self.assertEqual(self.show.frame(s[6] + 0.5)["sparks"] + self.show.frame(s[6] + 0.5)["stars"], [])


if __name__ == "__main__":
    unittest.main()
