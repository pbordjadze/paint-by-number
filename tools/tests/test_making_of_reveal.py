"""The making-of show's reveal schedule (tools/factory/making_of_reveal.py) against its Swift port's
fixture, and by hand.

    python3 -m unittest discover -s tools/tests -p 'test_making_of_reveal.py'

Needs numpy and Pillow (making_of_pets.py imports them). Sources/MakingOf's tests (ValueNoiseTests,
ArrivalTests, OutlinesTests; the numbers' cases left with the crew show) replay the same fixture and the same hand-made
cases; the Python and the Swift agree bit for bit, so every comparison here is exact."""

import json
import math
from pathlib import Path
import re
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "factory"))
import making_of_pets as pets
import making_of_reveal as reveal

FIXTURE = ROOT / "Tests" / "MakingOfTests" / "Fixtures" / "reveal-small.json"
SPEC = ROOT / "App" / "PaintByNumber" / "Resources" / "making-of.json"
STYLE = ROOT / "Sources" / "MakingOf" / "ScheduleStyle.swift"


def snake(name):
    return re.sub(r"(?<=[a-z])(?=[A-Z])", "_", name).upper()


class StyleTests(unittest.TestCase):
    def test_swift_style_has_the_same_numbers(self):
        # every `public var name = value` of ScheduleStyle is a constant of the module (cells by X and Y)
        found = re.findall(r"^\s+public var (\w+) = ([\d.]+)$", STYLE.read_text(encoding="utf-8"), re.M)
        self.assertGreaterEqual(len(found), 28)
        for name, value in found:
            key = snake(name)
            if key.endswith(("_X", "_Y")):
                got = getattr(reveal, key[:-2])["XY".index(key[-1])]
            else:
                got = getattr(reveal, key)
            self.assertEqual(got, float(value), name)


class FixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_fixture_was_made_from_the_shipped_spec(self):
        # what the schedule reads: a caption or card change needs no new fixture
        shipped, made = json.loads(SPEC.read_text(encoding="utf-8")), self.fixture["spec"]
        for key in ("crew", "timing", "outlines", "seeds"):
            self.assertEqual(made[key], shipped[key])

    def test_the_module_computes_the_fixtures_numbers_exactly(self):
        got = reveal.replay(self.fixture["inputs"], self.fixture["spec"])
        want = self.fixture["expected"]
        for key in want:
            self.assertEqual(json.loads(json.dumps(got[key])), want[key], key)

    def test_the_fixture_has_every_kind_of_input(self):
        inputs = self.fixture["inputs"]
        self.assertEqual([len(v) > 0 for v in inputs["visits"]], [True] * 6)
        self.assertGreater(len(inputs["traces"]), 0)
        self.assertLess(len(inputs["traces"]), len(inputs["strokes"]))
        # some paint has no seed, so the flow's fallback is exercised
        seeded = {int(s[3]) for s in inputs["seeds"]}
        self.assertLess(len(seeded), inputs["paints"])


class NoiseTests(unittest.TestCase):
    def test_a_lattice_is_row_major_draws_of_the_noise_stream(self):
        lattice = reveal.noise_lattice((18, 12), pets.stream(7, pets.STREAM_NOISE, 11))
        self.assertEqual(lattice.shape, (13, 19))
        self.assertEqual(lattice.ravel()[:3].tolist(), [0.07621336553267122, 0.8016695796850121, 0.6890799999388426])

    def test_pixel_positions_are_numpys_linspace(self):
        for h, cells in ((144, 12), (683, 40), (7, 3)):
            ys = np.linspace(0, cells, h, endpoint=False)
            self.assertEqual((np.arange(h) * (cells / h)).tolist(), ys.tolist())

    def test_a_field_passes_through_the_lattice_at_its_nodes(self):
        rng = pets.SplitMix64(5)
        lattice = reveal.noise_lattice((6, 4), rng)
        field = reveal.value_noise((16, 24), (6, 4), lattice)
        self.assertEqual(field[::4, ::4].tolist(), lattice[:4, :6].tolist())

    def test_smoothstep_eases_inside_a_cell(self):
        field = reveal.value_noise((1, 4), (1, 1), np.array([[0.0, 1.0], [0.0, 1.0]]))
        self.assertEqual(field[0].tolist(), [0, 0.15625, 0.5, 0.84375])

    def test_a_field_stays_inside_its_lattice(self):
        lattice = reveal.noise_lattice((18, 12), pets.SplitMix64(9))
        field = reveal.value_noise((130, 200), (18, 12), lattice)
        self.assertGreaterEqual(field.min(), lattice.min())
        self.assertLessEqual(field.max(), lattice.max())


class ArrivalTests(unittest.TestCase):
    @staticmethod
    def plain(visits, shape, speed=10.0, end=1000.0):
        return reveal.arrival(visits, shape, speed, end, np.zeros(shape))

    def test_the_change_spreads_from_the_earliest_visit_at_its_speed(self):
        field = self.plain([(2, 3, 4), (2.5, 30, 4)], (10, 40))
        self.assertEqual(field[4, 3], 2)
        self.assertEqual(field[8, 6], 2 + 5 / 10)
        self.assertEqual(field[4, 30], 2.5)
        self.assertEqual(field[4, 34], 2.5 + 4 / 10)
        self.assertEqual(field[4, 20], 2.5 + 10 / 10)
        self.assertEqual(field[4, 10], 2 + 7 / 10)

    def test_every_pixel_matches_a_scalar_loop(self):
        visits = [(1.0, 2.5, 3.5), (1.2, 17.0, 5.0), (0.9, 9.0, 11.0)]
        field = self.plain(visits, (13, 21), speed=7.0)
        for y in range(13):
            for x in range(21):
                want = min(t + math.sqrt((x - vx) * (x - vx) + (y - vy) * (y - vy)) / 7.0 for t, vx, vy in visits)
                self.assertEqual(field[y, x], want)

    def test_a_late_step_is_squeezed_toward_its_first_visit(self):
        free = self.plain([(1, 0, 0)], (1, 21))
        self.assertEqual(free[0, 20], 3)
        squeezed = self.plain([(1, 0, 0)], (1, 21), end=2)
        self.assertEqual(squeezed[0, 0], 1)
        self.assertAlmostEqual(squeezed[0, 20], 2, places=12)
        self.assertAlmostEqual(squeezed[0, 10], 1.5, places=12)
        self.assertEqual(self.plain([(1, 0, 0)], (1, 21), end=5).tolist(), free.tolist())

    def test_region_min_takes_the_earliest_pixel_of_each_region(self):
        times = np.array([[5.0, 3, 9, 1], [4, 8, 2, 7]])
        labels = np.array([[0, 0, 1, 1], [0, 2, 2, 1]])
        self.assertEqual(reveal.region_min(times, labels, 4).tolist(), [3, 1, 2, math.inf])

    def test_a_seeded_paint_flows_from_its_seed_and_an_unseeded_one_follows_the_crew(self):
        paints = np.array([[0, 0, 1, 1]])
        crew = np.full((1, 4), 5.0)
        calm, spread = reveal.paint_flow([(4.1, 1.0, 0.0, 0)], paints, 2, crew, paints, 2, 0.0, 2.0)
        self.assertEqual(calm.tolist(), [4.1 + 0.25 + 0 / (4 / 1.3), 5 + 0.3])
        self.assertEqual(spread.tolist(), calm.tolist())
        late, _ = reveal.paint_flow([(4.1, 1.0, 0.0, 0)], paints, 2, np.full((1, 4), 7.0), paints, 2, 0.0, 2.0)
        self.assertAlmostEqual(late[1], 5.8, places=12)
        self.assertTrue(4.2 < late[0] < calm[0])

    def test_the_fixtures_fields_are_done_by_their_steps_ends(self):
        f = json.loads(FIXTURE.read_text(encoding="utf-8"))
        for k, want in enumerate(f["expected"]["arrival"]):
            end = f["spec"]["timing"]["intro"] + (k + 1) * f["spec"]["timing"]["step"]
            self.assertLessEqual(want["max"], end - reveal.STEP_MARGIN + 1e-12)


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

    @classmethod
    def schedule(cls):
        f = json.loads(FIXTURE.read_text(encoding="utf-8"))
        pets.configure(f["spec"])
        i, spec = f["inputs"], f["spec"]
        intro, step = spec["timing"]["intro"], spec["timing"]["step"]
        shape = (i["size"][1], i["size"][0])
        T = [reveal.step_arrival(k, i["visits"][k], shape, intro, step, i["seed"]) for k in (4, 5)]
        traces = [(t["stroke"], t["start"], t["duration"], t["points"]) for t in i["traces"]]
        plan = reveal.stroke_schedule(i["strokes"], traces, T[0], T[1], intro, step, float(spec["outlines"]["grid"]),
                                      i["seed"])
        return f, plan

    def test_the_finished_template_is_the_smooth_lines_and_the_first_the_stairs(self):
        f, plan = self.schedule()
        relax = float(f["spec"]["outlines"]["relax"])
        for (_, pts, value), s in zip(reveal.relaxed_lines(plan, -math.inf, relax), plan):
            self.assertEqual(pts.tolist(), s.jagged.tolist())
            self.assertEqual(value, 1.0)
        for (_, pts, _), s in zip(reveal.relaxed_lines(plan, math.inf, relax), plan):
            self.assertEqual(pts.tolist(), s.smooth.tolist())

    def test_the_ink_steps_lines_only_grow_and_darken(self):
        f, plan = self.schedule()
        spec, i = f["spec"], f["inputs"]
        intro, step, ramp = spec["timing"]["intro"], spec["timing"]["step"], float(spec["outlines"]["inkRamp"])
        seen = {}
        t, stop = intro + 4 * step, intro + 5 * step
        while t < stop:
            now = reveal.inked_lines(plan, t, ramp, i["petHeight"])
            self.assertTrue(all(k in {n for n, _, _ in now} for k in seen))
            for n, pts, value in now:
                self.assertTrue(0 < value <= 1)
                if n in seen:
                    before, v0 = seen[n]
                    self.assertEqual(pts[:len(before)].tolist(), before.tolist())
                    self.assertGreaterEqual(value, v0)
                seen[n] = (pts, value)
            t += 1 / 30
        final = reveal.inked_lines(plan, stop - 1e-9, ramp, i["petHeight"])
        self.assertEqual([n for n, _, _ in final], list(range(len(plan))))
        for n, pts, _ in final:
            self.assertEqual(pts.tolist(), plan[n].jagged.tolist())

    def test_a_walked_line_is_in_full_ink_and_the_rest_darken_from_grey(self):
        f, plan = self.schedule()
        ramp, ph = float(f["spec"]["outlines"]["inkRamp"]), f["inputs"]["petHeight"]
        walked = next(s for s in plan if s.walked)
        calm = next(s for s in plan if not s.walked)
        value = lambda s, t: next((v for n, _, v in reveal.inked_lines(plan, t, ramp, ph) if n == s.index), None)
        self.assertEqual(value(walked, walked.t0 + walked.dur / 2), 1)
        self.assertTrue(reveal.INK_GREY < value(calm, calm.t0 + calm.dur / 2) < 1)
        self.assertEqual(value(calm, calm.t0 + calm.dur + ramp + 0.01), 1)

    def test_nothing_is_drawn_before_the_ink_step_and_the_end_is_smooth(self):
        f, plan = self.schedule()
        spec = f["spec"]
        intro, step = spec["timing"]["intro"], spec["timing"]["step"]
        args = (intro, step, float(spec["outlines"]["inkRamp"]), float(spec["outlines"]["relax"]), f["inputs"]["petHeight"])
        self.assertEqual(reveal.lines_at(plan, intro + 4 * step - 0.001, *args), [])
        end = [pts.tolist() for _, pts, _ in reveal.lines_at(plan, intro + 6 * step + 1, *args)]
        self.assertEqual(end, [s.smooth.tolist() for s in plan])


class NumberTests(unittest.TestCase):
    @staticmethod
    def tiny(numbers, visits, relax=10.0, clear=10.0):
        regions = np.zeros((50, 100), dtype=np.int32)
        return reveal.number_times(numbers, [clear], regions, np.full((50, 100), relax), visits, 0.0, 2.0, 10.0)

    def test_a_number_near_a_working_pet_comes_in_just_after_its_visit(self):
        visits = [(10.9, 20, 20), (10.6, 30, 20), (10.1, 90, 40)]
        self.assertEqual(self.tiny([(25, 20, 4)], visits), [10.6 + 0.3])

    def test_a_number_far_from_every_pet_waits_for_late_in_the_step(self):
        self.assertEqual(self.tiny([(80, 10, 4)], [(10.2, 5, 45)]), [10 + 0.55 * 2])

    def test_a_number_waits_for_the_outlines_to_relax_at_it(self):
        self.assertEqual(self.tiny([(80, 10, 4)], [(10.2, 5, 45)], relax=11.0), [11 + 0.45])

    def test_no_number_is_later_than_the_shows_end(self):
        self.assertEqual(self.tiny([(80, 10, 4)], [(11, 5, 45)], relax=60.0, clear=50.0), [12 - 0.15])

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
