"""The making-of crew's inputs against their Swift port: exact arithmetic, the draws, and the whole
small fixture.

    python3 -m unittest discover -s tools/tests -p 'test_making_of_inputs.py'

Needs numpy and Pillow. Tests/MakingOfTests holds the same numbers (ExactMathTests, LabelingTests,
SamplingTests, StopWeightsTests, CrewInputsTests) and reads the same fixture,
`Fixtures/show-small/inputs-small.json`: regenerate it, after changing making_of_exact.py or
making_of_inputs.py, with

    python3 tools/factory/making_of_inputs.py Tests/MakingOfTests/Fixtures/show-small \\
        Tests/MakingOfTests/Fixtures/show-small --out Tests/MakingOfTests/Fixtures/show-small/inputs-small.json
"""

import bisect
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "factory"))
import making_of_exact as exact
import making_of_inputs as inputs
import making_of_pets as pets

SMALL = ROOT / "Tests" / "MakingOfTests" / "Fixtures" / "show-small"
SPEC = json.loads((ROOT / "App" / "PaintByNumber" / "Resources" / "making-of.json").read_text(encoding="utf-8"))


class ExactMathTests(unittest.TestCase):
    def test_halves_round_to_even(self):
        self.assertEqual([exact.half_even(x) for x in (0.5, 1.5, 2.5, 3.5, -0.5, -1.5, 2.4999999999999996, 2.5000000000000004)],
                         [0, 2, 2, 4, 0, -2, 2, 3])
        self.assertEqual(exact.half_even(0.0025 * 1600 * 640 / 1024), 2)    # a 640 px picture's smoothing radius
        self.assertEqual(exact.half_even(0.0025 * 1600 * 1024 / 1024), 4)

    def test_quantizing_rounds_halves_to_even(self):
        cases = [(0.125, 2, 0.12), (0.135, 2, 0.14), (2.675, 2, 2.68), (1.005, 2, 1.0), (109.12, 2, 109.12),
                 (23.04000000000001, 2, 23.04), (0.00005, 4, 0.0), (0.00015, 4, 0.0001), (2.5, 0, 2), (3.5, 0, 4),
                 (-0.125, 2, -0.12), (182.8284271247462, 2, 182.83)]
        for x, places, want in cases:
            self.assertEqual(exact.quantize(x, places), want, (x, places))

    def test_the_plan_files_rounding_leaves_its_own_values_alone(self):
        for v in (0.07, 109.12, 23.04, 5.72, 1152.0, 0.01, 681.99):
            self.assertEqual(exact.quantize(v, 2), v)
            self.assertEqual(round(v, 2), v)

    def test_cube_roots_settle(self):
        cases = [(0.0, 0.0), (1.5e-05, 0.0246621207433047), (0.0003035269835488375, 0.06720461569746485), (0.125, 0.5),
                 (0.5, 0.7937005259840998), (1.0, 1.0), (0.9999999999999999, 1.0)]
        for x, want in cases:
            self.assertEqual(float(exact.cbrt(x)), want, x)

    def test_the_cube_root_is_the_librarys_within_a_few_ulps(self):
        for linear in exact.SRGB_LINEAR:
            for weight in (0.0514459929, 0.6806995451, 1):
                x = weight * linear
                got, true = float(exact.cbrt(x)), float(np.cbrt(x))
                self.assertLessEqual(abs(got - true), 4 * np.spacing(true), x)

    def test_oklab_in_doubles(self):
        cases = [((255, 255, 255), (0.9999999934735462, 8.095285553011422e-11, 3.727390762708893e-08)),
                 ((0, 0, 0), (0.0, 0.0, 0.0)),
                 ((128, 64, 32), (0.4466302815957851, 0.06950253253477043, 0.07057777610311045)),
                 ((255, 0, 0), (0.6279553606145516, 0.22486306106597398, 0.1258462985307351)),
                 ((12, 200, 99), (0.7293647235901226, -0.16992373324084165, 0.09423908632120026)),
                 ((1, 1, 1), (0.06720461525885703, 5.440366906972471e-12, 2.50497864812127e-09))]
        for rgb, want in cases:
            self.assertEqual(tuple(float(v) for v in exact.oklab(np.array(rgb))), want, rgb)

    def test_oklab_agrees_with_the_layers(self):
        import making_of_layers as layers
        rgb = np.array([[12, 200, 99], [128, 64, 32], [255, 255, 255]], dtype=np.uint8)
        np.testing.assert_allclose(exact.oklab(rgb), layers.oklab(rgb.astype(np.float32) / 255), atol=2e-6)

    def test_the_transfer_table_is_the_true_curve(self):
        self.assertEqual(len(exact.SRGB_LINEAR), 256)
        total = 0.0
        for v in exact.SRGB_LINEAR:
            total += v
        self.assertEqual(total, 79.619452444574)
        for i, want in [(1, 0.0003035269835488375), (10, 0.003035269835488375), (100, 0.12743768043564743),
                        (128, 0.21586050011389915), (200, 0.5775804404296505), (255, 1.0)]:
            self.assertEqual(exact.SRGB_LINEAR[i], want)
        for i, v in enumerate(exact.SRGB_LINEAR):       # and the curve's within the library's rounding
            c = i / 255
            self.assertAlmostEqual(v, c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4, delta=1e-15)

    def test_box_sums_count_the_edge_again(self):
        a = np.array([[1, 0, 0, 2, 0], [0, 3, 1, 0, 0], [0, 0, 0, 5, 1], [4, 0, 1, 0, 2]])
        self.assertEqual(exact.box_sum(a, 1).tolist(),
                         [[7, 6, 8, 5, 4], [5, 5, 11, 9, 9], [11, 9, 10, 10, 11], [16, 10, 7, 12, 15]])
        self.assertEqual(exact.box_sum(a, 2).tolist(),
                         [[13, 21, 19, 17, 15], [23, 26, 23, 20, 20], [33, 31, 27, 23, 25], [43, 36, 31, 26, 30]])
        self.assertEqual(exact.box_sum(a, 5).tolist(),
                         [[146, 135, 124, 113, 102], [167, 155, 143, 131, 119], [188, 175, 162, 149, 136],
                          [209, 195, 181, 167, 153]])
        self.assertEqual(exact.box_sum(np.array([[3]]), 2).tolist(), [[75]])

    def test_percentiles_interpolate_between_ranks(self):
        self.assertEqual(exact.percentile([5, 1, 4, 2, 3], 95), 4.8)
        self.assertEqual(exact.percentile([5, 1, 4, 2, 3], 50), 3.0)
        self.assertEqual(exact.percentile([7], 95), 7.0)
        self.assertEqual(exact.percentile(list(range(21)), 95), 19.0)
        self.assertEqual(exact.percentile([0] * 19 + [100], 95), 5.0)
        self.assertEqual(exact.percentile([3, 3, 3], 95), 3.0)
        values = np.random.default_rng(1).integers(0, 5000, 4001)
        self.assertAlmostEqual(exact.percentile(values, 95), float(np.percentile(values, 95)), delta=1e-9)

    def test_weighted_picks_find_the_first_entry_past_the_value(self):
        cdf = exact.cumulative([0, 0, 1, 0, 2, 0])
        self.assertEqual(cdf.tolist(), [0, 0, 1, 1, 3, 3])
        values = [-1, 0, 0.5, 1, 2.9999999999999996, 3, 10]
        self.assertEqual([int(exact.bisect_right(cdf, v)) for v in values], [0, 2, 2, 4, 4, 6, 6])
        self.assertEqual([int(exact.bisect_right(cdf, v)) for v in values], [bisect.bisect_right(cdf.tolist(), v) for v in values])
        self.assertEqual(exact.bisect_right(cdf, np.array(values)).tolist(), [0, 2, 2, 4, 4, 6, 6])

    def test_sums_run_in_order(self):
        self.assertEqual(exact.cumulative([0.1, 0.2, 0.3]).tolist(), [0.1, 0.30000000000000004, 0.6000000000000001])


class LabelingTests(unittest.TestCase):
    def test_areas_are_numbered_by_their_first_run(self):
        labels, count = exact.label_regions(np.array([[1, 1, 2, 2, 1], [1, 3, 3, 2, 1], [4, 3, 3, 1, 1], [4, 4, 1, 1, 5]]))
        self.assertEqual(labels.tolist(), [[0, 0, 1, 1, 2], [0, 3, 3, 1, 2], [4, 3, 3, 2, 2], [4, 4, 2, 2, 5]])
        self.assertEqual(count, 6)

    def test_holes_diagonals_and_late_joins(self):
        self.assertEqual(exact.label_regions(np.array([[7, 7, 7], [7, 8, 7], [7, 7, 7]]))[0].tolist(), [[0, 0, 0], [0, 1, 0], [0, 0, 0]])
        labels, count = exact.label_regions(np.array([[1, 2, 1], [2, 1, 2], [1, 2, 1]]))
        self.assertEqual((labels.tolist(), count), ([[0, 1, 2], [3, 4, 5], [6, 7, 8]], 9))
        labels, count = exact.label_regions(np.array([[5, 5, 5, 6], [6, 5, 6, 6], [6, 6, 6, 5]]))
        self.assertEqual((labels.tolist(), count), ([[0, 0, 0, 1], [1, 0, 1, 1], [1, 1, 1, 2]], 3))

    def test_the_small_pictures_regions(self):
        pictures = inputs.Pictures(str(SMALL))
        labels, count = exact.label_regions(exact.color_keys(pictures.simplified))
        self.assertEqual(count, json.loads((SMALL / "inputs-small.json").read_text())["trace"]["labels"])


class LineMaskTests(unittest.TestCase):
    def test_pixels_within_reach_of_a_line_are_inked(self):
        strokes = [np.array([(1.0, 1.5), (12.0, 1.5), (12.0, 7.25)]), np.array([(3.0, 5.0), (3.5, 5.2)]),
                   np.array([(6.0, 6.0), (6.0, 6.0)])]
        mask = exact.line_mask(14, 9, strokes, 1.5 / 2 + inputs.LINE_REACH)
        self.assertEqual([''.join('#' if v else '.' for v in row) for row in mask],
                         [".###########..", "#############.", ".############.", "...........##.", "..##.......##.",
                          "..#####....##.", ".....##....##.", "...........##.", ".............."])
        self.assertEqual(int(mask.sum()), 55)

    def test_lines_outside_the_plane_are_clipped(self):
        mask = exact.line_mask(6, 4, [np.array([(-20.0, 1.5), (40.0, 1.5)]), np.array([(50.0, 50.0), (60.0, 60.0)])], 0.5 + 0.33)
        self.assertEqual([''.join('#' if v else '.' for v in row) for row in mask], ["......", "######", "......", "......"])


class SamplingTests(unittest.TestCase):
    @staticmethod
    def patterned(w, h):
        return np.array([float((x * 7 + y * 3) % 5) for y in range(h) for x in range(w)])

    def test_spots_are_drawn_by_weight(self):
        rng = pets.stream(7, pets.STREAM_SPOTS, 3)
        self.assertEqual(inputs.sample_stops(self.patterned(12, 8), 12, 4, rng, 3.0), [(9, 0), (6, 7), (3, 4), (11, 7)])
        self.assertEqual(rng.random(), 0.5976137899796332)
        rng = pets.stream(8, pets.STREAM_SPOTS, 3)
        self.assertEqual(inputs.sample_stops(self.patterned(12, 8), 12, 4, rng, 3.0), [(1, 4), (6, 7), (4, 0), (9, 2)])

    def test_a_plane_without_weight_is_drawn_from_uniformly(self):
        rng = pets.stream(7, pets.STREAM_SPOTS, 1)
        self.assertEqual(inputs.sample_stops(np.zeros(24), 6, 3, rng, 2.0), [(1, 2), (1, 0), (3, 3)])
        self.assertEqual(rng.random(), 0.13580693283067147)

    def test_fewer_spots_than_asked_are_what_there_is(self):
        weights = np.zeros(30)
        weights[3], weights[27] = 1e-300, 5.0
        rng = pets.stream(7, pets.STREAM_SPOTS, 0)
        self.assertEqual(inputs.sample_stops(weights, 6, 2, rng, 2.0), [(3, 4)])
        self.assertEqual(rng.random(), 0.3435327290593786)
        rng = pets.stream(7, pets.STREAM_HOMES, 0)
        every = inputs.sample_stops(np.ones(25), 5, 30, rng, 1.0)
        self.assertEqual((len(every), len(set(every))), (25, 25))
        self.assertEqual(every[:6], [(4, 4), (1, 3), (4, 2), (0, 4), (0, 3), (1, 2)])
        self.assertEqual(rng.random(), 0.47896738244214165)

    def test_no_spots_asked_draws_nothing(self):
        rng = pets.stream(7, pets.STREAM_HOMES, 0)
        self.assertEqual(inputs.sample_stops(np.ones(25), 5, 0, rng, 2.0), [])
        self.assertEqual(rng.random(), 0.7824150874829743)


class SeedingTests(unittest.TestCase):
    LAB = np.array([[0.1, 0.0, 0.0], [0.9, 0.1, 0.0], [0.5, -0.3, 0.2], [0.52, -0.31, 0.2], [0.2, 0.4, -0.1],
                    [0.95, 0.12, 0.01], [0.11, 0.01, 0.0], [0.3, 0.3, 0.3]])

    def test_seeds_spread_over_the_colors(self):
        rng = pets.stream(7, pets.STREAM_SEEDS, 0)
        self.assertEqual(inputs.kmeanspp(self.LAB, 4, rng), [3, 5, 0, 7])
        self.assertEqual(rng.random(), 0.24725284440123863)

    def test_rows_that_are_already_seeds_twins_are_drawn_uniformly(self):
        rng = pets.stream(7, pets.STREAM_SEEDS, 0)
        self.assertEqual(inputs.kmeanspp(np.tile([[0.4, 0.1, 0.2]], (5, 1)), 3, rng), [3, 2, 1])
        self.assertEqual(rng.random(), 0.9660511963580937)

    def test_no_more_seeds_than_rows(self):
        rng = pets.stream(7, pets.STREAM_SEEDS, 0)
        self.assertEqual(inputs.kmeanspp(self.LAB[:3], 6, rng), [2, 1, 0])
        self.assertEqual(rng.random(), 0.9660511963580937)
        rng = pets.stream(7, pets.STREAM_SEEDS, 0)
        self.assertEqual(inputs.kmeanspp(self.LAB[:0], 6, rng), [])
        self.assertEqual(rng.random(), 0.5056482214915431)

    def test_bands_split_the_picture_between_its_margins(self):
        self.assertEqual(inputs.bands(1024, 0.12, 3), [122, 382, 641, 901])
        self.assertEqual(inputs.bands(216, 0.12, 1), [25, 190])


class TemplateTests(unittest.TestCase):
    def test_lines_and_numbers_as_the_svg_prints_them(self):
        t = inputs.Template(str(SMALL / "template.svg"), 216)
        self.assertEqual((len(t.strokes), len(t.numbers), t.line_width, t.scale), (39, 46, 1.5, 1.0))
        self.assertEqual(t.strokes[0][:2].tolist(), [[181.0, 61.0], [172.61, 58.01]])
        self.assertEqual(t.numbers[0], (15.04, 15.04, 3.85))

    def test_a_smaller_picture_scales_them(self):
        t = inputs.Template(str(SMALL / "template.svg"), 100)
        self.assertEqual(t.scale, 100 / 216)
        self.assertEqual(t.strokes[0][1].tolist(), [172.61 * (100 / 216), 58.01 * (100 / 216)])
        self.assertEqual(t.line_width, 1.5 * (100 / 216))


class SmallShowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pets.configure(SPEC)
        cls.expected = json.loads((SMALL / "inputs-small.json").read_text(encoding="utf-8"))
        cls.pictures = inputs.Pictures(str(SMALL))
        cls.template = inputs.Template(str(SMALL / "template.svg"), cls.pictures.size[0])
        cls.built = inputs.build(cls.pictures, cls.template, SPEC, 7, SPEC["crew"]["pets"])

    def test_the_fixture_is_what_the_code_makes(self):
        b = self.built
        self.assertEqual(json.loads(json.dumps(b.inputs)), self.expected["inputs"])
        self.assertEqual(json.loads(json.dumps([list(s) for s in b.seeds])), self.expected["seeds"])
        self.assertEqual([int(k) for k in b.paint_keys], self.expected["paints"])
        self.assertEqual(json.loads(json.dumps(b.trace)), self.expected["trace"])

    def test_the_command_line_writes_the_fixture(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "inputs.json"
            subprocess.run([sys.executable, str(ROOT / "tools" / "factory" / "making_of_inputs.py"), str(SMALL), str(SMALL),
                            "--out", str(out)], check=True)
            self.assertEqual(out.read_text(encoding="utf-8"), (SMALL / "inputs-small.json").read_text(encoding="utf-8"))

    def test_inputs_are_at_the_precision_the_plan_file_keeps(self):
        self.assertEqual(pets.quantized(self.built.inputs), self.built.inputs)

    def test_the_planner_takes_them(self):
        planned = pets.plan(self.built.inputs)
        self.assertEqual(len(planned.pets), 3)
        self.assertEqual(len(planned.visits), 6)

    def test_seeds_land_in_time_order_on_the_grid(self):
        seeds = self.built.seeds
        self.assertEqual(len(seeds), len(self.built.paint_keys))
        self.assertEqual(seeds[0][0], 0.6 + 2 * 2.5 + 0.12)
        self.assertEqual([s[0] for s in seeds], sorted(s[0] for s in seeds))
        for _, x, y, paint in seeds:
            self.assertEqual((int(x) - 10) % 6, 0)
            self.assertEqual((int(y) - 21) % 6, 0)
            self.assertTrue(0 <= paint < len(self.built.paint_keys))

    def test_the_same_seed_gives_the_same_inputs_and_another_gives_others(self):
        again = inputs.build(self.pictures, self.template, SPEC, 7, SPEC["crew"]["pets"])
        self.assertEqual(again.inputs, self.built.inputs)
        other = inputs.build(self.pictures, self.template, SPEC, 8, SPEC["crew"]["pets"])
        self.assertEqual(other.inputs["strokes"], self.built.inputs["strokes"])
        self.assertNotEqual(other.inputs["candidates"][0], self.built.inputs["candidates"][0])

    def test_a_steps_spots_come_from_its_own_stream(self):
        W, H = self.pictures.size
        room = np.zeros((H, W))
        room[40:136, 25:191] = 1.0
        rng = pets.stream(7, pets.STREAM_SPOTS, 1)
        spots = inputs.sample_stops(room.ravel(), W, 12, rng, 0.1 * W)
        self.assertEqual(self.built.inputs["candidates"][1], [[float(x), float(y)] for x, y in spots])


class FallbackTests(unittest.TestCase):
    """Pictures no photo makes. Tests/MakingOfTests' CrewInputsFallbackTests expect the same numbers."""

    class Flat:
        def __init__(self, w, h):
            self.size = (w, h)
            self.working = self.smoothed = self.palette = self.simplified = np.full((h, w, 3), [120, 130, 140], dtype=np.uint8)
            self.structure = np.zeros((h, w), dtype=np.uint8)

    @classmethod
    def setUpClass(cls):
        pets.configure(SPEC)

    def build(self, w, h, ids):
        return inputs.build(self.Flat(w, h), inputs.Template(str(SMALL / "template.svg"), w), SPEC, 7, ids)

    def test_a_picture_with_little_room_is_drawn_from_everywhere(self):
        b = self.build(20, 14, SPEC["crew"]["pets"])
        self.assertEqual(b.inputs["candidates"], [
            [[3, 5], [10, 3], [16, 3], [9, 5], [15, 4], [4, 3], [5, 5], [11, 4], [13, 3], [2, 4], [8, 3], [17, 5], [13, 5], [17, 3], [7, 5]],
            [[12, 4], [4, 3], [4, 5], [14, 5], [6, 5], [16, 4], [6, 3], [10, 4], [8, 4], [14, 3], [2, 3], [2, 5]],
            [[13, 5]],
            [[6, 3], [15, 5], [11, 4], [17, 5], [17, 3], [4, 3], [13, 4], [15, 3], [2, 4], [8, 4], [4, 5], [6, 5]],
            [],
            [[3, 4], [5, 3], [17, 5], [10, 5]]])
        self.assertEqual(b.seeds, [(5.72, 13.0, 5.0, 0)])

    def test_a_picture_smaller_than_the_crew_shares_its_homes(self):
        b = self.build(2, 2, [f"pet-{i}" for i in range(20)])
        homes = [[0, 0], [0, 1], [1, 0], [1, 1], [1, 1], [0, 0], [1, 0], [0, 1], [1, 1], [1, 0], [0, 1], [0, 0]]
        self.assertEqual(b.inputs["candidates"][0][:12], homes)
        self.assertEqual([len(c) for c in b.inputs["candidates"]], [16, 4, 0, 4, 0, 4])
        self.assertEqual([p["start"] for p in b.inputs["pets"]], [homes[i % 12] for i in range(20)])
        self.assertEqual(b.seeds, [])


if __name__ == "__main__":
    unittest.main()
