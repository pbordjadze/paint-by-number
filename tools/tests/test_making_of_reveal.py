"""What the making-of show's parts share of their schedule (tools/factory/making_of_reveal.py), by hand.

    python3 -m unittest discover -s tools/tests -p 'test_making_of_reveal.py'

Needs numpy. Sources/MakingOf's OutlinesTests and ArrivalTests have the same hand-made cases; the
Python and the Swift agree bit for bit, so every comparison here is exact. The cards', the rings' and
the hand-off's cases are test_making_of_fields.py's TimelineTests."""

import math
from pathlib import Path
import re
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "factory"))
import making_of_reveal as reveal

STYLE = ROOT / "Sources" / "MakingOf" / "ScheduleStyle.swift"


def snake(name):
    return re.sub(r"(?<=[a-z])(?=[A-Z])", "_", name).upper()


class StyleTests(unittest.TestCase):
    def test_swift_style_has_the_same_numbers(self):
        # every `public var name = value` of ScheduleStyle is a constant of the module
        found = re.findall(r"^\s+public var (\w+) = ([\d.]+)$", STYLE.read_text(encoding="utf-8"), re.M)
        self.assertGreaterEqual(len(found), 12)
        for name, value in found:
            self.assertEqual(getattr(reveal, snake(name)), float(value), name)


class RegionTests(unittest.TestCase):
    def test_region_min_takes_the_earliest_pixel_of_each_region(self):
        times = np.array([[5.0, 3, 9, 1], [4, 8, 2, 7]])
        labels = np.array([[0, 0, 1, 1], [0, 2, 2, 1]])
        self.assertEqual(reveal.region_min(times, labels, 4).tolist(), [3, 1, 2, math.inf])


class OutlinesTests(unittest.TestCase):
    def test_a_straight_line_snaps_to_the_grid_and_keeps_its_pairs(self):
        jagged, smooth = reveal.staircase([(0, 0), (10, 0)], 5)
        self.assertEqual(jagged.tolist(), [[0, 0], [5, 0], [10, 0]])
        self.assertEqual(smooth[0].tolist(), [0, 0])
        self.assertAlmostEqual(smooth[1][0], 10 / 3, places=12)
        self.assertAlmostEqual(smooth[2][0], 25 / 3, places=12)

    def test_a_diagonal_climbs_in_steps(self):
        jagged, smooth = reveal.staircase([(0, 0), (20, 20)], 5)
        self.assertEqual(len(jagged), len(smooth))
        self.assertEqual((jagged[0].tolist(), jagged[-1].tolist()), ([0, 0], [20, 20]))
        for a, b in zip(jagged, jagged[1:]):
            self.assertNotEqual(a[0] == b[0], a[1] == b[1], "every step moves along one axis")
        self.assertTrue((jagged % 5 == 0).all())
        self.assertTrue(any((a == b).all() for a, b in zip(smooth, smooth[1:])), "a corner repeats its smooth point")

    def test_halfway_rounds_to_even(self):
        jagged, _ = reveal.staircase([(2.5, 0), (7.5, 0)], 5)
        self.assertEqual((jagged[0].tolist(), jagged[-1].tolist()), ([0, 0], [10, 0]))

    def test_a_line_that_snaps_to_one_point_still_has_two(self):
        jagged, smooth = reveal.staircase([(1, 1), (1.2, 1.1)], 5)
        self.assertEqual(jagged.tolist(), [[0, 0], [0, 0]])
        self.assertEqual(len(smooth), 2)

    def test_a_line_is_resampled_every_one_point_five_pixels_before_it_snaps(self):
        fine, smooth = reveal.staircase([(0, 0), (300, 0)], 0.01)
        self.assertEqual((len(fine), len(smooth)), (201, 201))
        self.assertEqual(len(reveal.staircase([(0, 0), (300, 0)], 5)[0]), 61)

    @staticmethod
    def strokes():
        """Two lines as the show keeps them, the ripple reaching the first's points from 10 s on, a tenth
        of a second apart, and the second's all at 11 s."""
        out = []
        for n, pts in enumerate(([(3.0, 4.0), (40.0, 22.0), (61.0, 9.0)], [(10.0, 30.0), (10.0, 50.0)])):
            jagged, smooth = reveal.staircase(pts, 5)
            relax = 10.0 + 0.1 * np.arange(len(jagged)) if n == 0 else np.full(len(jagged), 11.0)
            out.append(reveal.Stroke(n, 0.0, 1.0, jagged, smooth, relax))
        return out

    def test_the_finished_template_is_the_smooth_lines_and_the_first_the_stairs(self):
        plan = self.strokes()
        for (n, pts, value), s in zip(reveal.relaxed_lines(plan, -math.inf, 0.4), plan):
            self.assertEqual(pts.tolist(), s.jagged.tolist())
            self.assertEqual((n, value), (s.index, 1.0))
        for (_, pts, _), s in zip(reveal.relaxed_lines(plan, math.inf, 0.4), plan):
            self.assertEqual(pts.tolist(), s.smooth.tolist())

    def test_each_point_relaxes_when_the_ripple_reaches_it(self):
        plan = self.strokes()
        first, second = (pts for _, pts, _ in reveal.relaxed_lines(plan, 10.5, 0.4))
        a = plan[0]
        self.assertEqual(first[0].tolist(), a.smooth[0].tolist())       # reached 0.5 s ago: smooth
        self.assertEqual(first[1].tolist(), a.smooth[1].tolist())       # 0.4 s ago: just done, exactly
        self.assertEqual(first[5].tolist(), a.jagged[5].tolist())       # reached now: still the stairs
        self.assertEqual(first[-1].tolist(), a.jagged[-1].tolist())     # not reached yet
        m = 0.5 * 0.5 * (3 - 2 * 0.5)                                   # the third point, half way: eased
        self.assertTrue(np.allclose(first[3], a.jagged[3] * (1 - m) + a.smooth[3] * m, atol=1e-12))
        self.assertEqual(second.tolist(), plan[1].jagged.tolist())


class NumberTests(unittest.TestCase):
    """The discs are making_of_clip.py's: the number each pixel belongs to."""

    def test_a_disc_is_the_numbers_size_at_least_four_pixels_and_the_later_one_wins(self):
        discs = reveal.number_discs([(10, 10, 10), (14, 10, 1), (0, 0, 2)], (30, 40))
        self.assertTrue(discs[19, 10] == 0 and discs[20, 10] == -1)
        self.assertTrue(discs[10, 1] == 0 and discs[10, 0] == -1)
        self.assertTrue(discs[10, 14] == 1 and discs[10, 18] == 1 and discs[10, 19] == 0)
        self.assertTrue(discs[10, 11] == 1 and discs[10, 10] == 1)
        self.assertTrue(discs[0, 4] == 2 and discs[0, 5] == -1 and discs[2, 2] == 2 and discs[3, 3] == -1)
        self.assertEqual(reveal.number_discs([], (3, 3)).tolist(), [[-1] * 3] * 3)


class FingerprintTests(unittest.TestCase):
    def test_fnv1a_over_ieee_bytes(self):
        self.assertEqual(reveal.fingerprint([]), "cbf29ce484222325")
        self.assertEqual(reveal.fingerprint([0.0]), reveal.fingerprint(np.zeros(1)))
        self.assertNotEqual(reveal.fingerprint([0.0]), reveal.fingerprint([-0.0]))
        self.assertNotEqual(reveal.fingerprint([1.0, 2.0]), reveal.fingerprint([2.0, 1.0]))


if __name__ == "__main__":
    unittest.main()
