"""The making-of crew show's frames (tools/factory/making_of_show.py and what it is made of) and the
guardians' metrics. The app plays the show with no crew (making_of_fields.py); this one is the clip
tool's, and its Swift port was retired on October 23, 2026.

    python3 -m unittest discover -s tools/tests -p 'test_making_of_show.py'
    python3 tools/tests/test_making_of_show.py --write-goldens     # after changing the show

Needs numpy and Pillow. --write-goldens writes tools/tests/fixtures/frames-small.json: the small show
fixture (Tests/MakingOfTests/Fixtures/show-small, 216 x 144) built as the show is built, and fourteen moments of it,
each with its frame (the lines by their counts and a fingerprint of their points, the numbers, rings,
guardians and card as they are) and the composite picture on a 24 x 16 lattice. The test here fails when
the committed file is not what the Python makes now."""

import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "factory"))
import making_of_pets as pets
import making_of_reveal as reveal
import making_of_show as show_module

FIXTURES = ROOT / "Tests" / "MakingOfTests" / "Fixtures"
SNAPSHOTS = FIXTURES / "show-small"
RESOURCES = ROOT / "App" / "PaintByNumber" / "Resources"
SPEC = RESOURCES / "making-of.json"
GOLDENS = ROOT / "tools" / "tests" / "fixtures"
METRICS = GOLDENS / "pet-metrics.json"
SEED = 7
POINTS = (24, 16)


def load_spec():
    return json.loads(SPEC.read_text(encoding="utf-8"))


def load_metrics():
    doc = json.loads(METRICS.read_text(encoding="utf-8"))
    return {pid: (m["top"], m["foot"], m["cx"]) for pid, m in doc["pets"].items()}


def small_show():
    return show_module.Show(str(SNAPSHOTS), str(SNAPSHOTS / "template.svg"), load_spec(), SEED, metrics=load_metrics())


def moments(spec):
    """Fourteen moments that between them show every stage: the photo with the guardians popping in, each step early and late
    (the cards fading, the seed rings popping and going, the lines drawn and relaxing, the numbers
    coming in), the hand-off, the guardians leaving and the fade at the end."""
    intro, step = spec["timing"]["intro"], spec["timing"]["step"]
    start = lambda k: intro + k * step
    end = intro + 6 * step
    return [0.12, start(0) + 0.6, start(1) + 0.1, start(1) + 1.4, start(2) + 0.45, start(2) + 1.9, start(3) + 1.3,
            start(4) + 0.5, start(4) + 1.6, start(5) + 0.4, start(5) + 1.9, end + 0.05, end + 1.4,
            end + spec["timing"]["outro"] - 0.12]


def lattice(size, points):
    """`points` pixel columns (or rows) spread over 0...size - 1, rounded half up."""
    return [(i * (size - 1) + (points - 1) // 2) // (points - 1) for i in range(points)]


def camel(value):
    """A frame's snake_case keys as the JSON spells them (and the Swift structs)."""
    if isinstance(value, dict):
        return {re.sub(r"_(\w)", lambda m: m.group(1).upper(), k): camel(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [camel(v) for v in value]
    if isinstance(value, np.generic):
        return value.item()
    return value


def summarize(frame):
    """A frame as JSON: the lines by their stroke, point count and value with one fingerprint of all
    their points, the rest as it is."""
    lines = frame["ink"]
    flat = np.concatenate([line["points"].ravel() for line in lines]) if lines else np.zeros(0)
    ink = {"lines": [{"stroke": line["stroke"], "points": len(line["points"]), "value": line["value"]} for line in lines],
           "fingerprint": reveal.fingerprint(flat)}
    out = {k: frame[k] for k in ("time", "step", "picture", "numbers", "seed_rings", "sprites", "card")}
    out["ink"] = ink
    return camel(out)


def frames_golden():
    spec = load_spec()
    show = small_show()
    W, H = show.size
    xs, ys = lattice(W, POINTS[0]), lattice(H, POINTS[1])
    frames = []
    for t in moments(spec):
        frame = show.frame(t)
        picture = show.composite(frame)
        entry = summarize(frame)
        entry["coverageFingerprint"] = (
            reveal.fingerprint(show_module.ink_coverage(frame["ink"], W, H, show.line_width).astype(np.float64).ravel())
            if frame["ink"] else None)
        entry["rgb"] = [round(float(picture[y, x, c]), 8) for y in ys for x in xs for c in range(3)]
        frames.append(entry)
    return {
        "about": "Tests/MakingOfTests/Fixtures/show-small built by making_of_show.Show (seed 7, the shipped spec and the "
                 "pinned pet-metrics.json), at fourteen moments: each frame, and the composite picture on a lattice, "
                 "row-major over xs by ys, three values a pixel. Written by tools/tests/test_making_of_show.py "
                 "--write-goldens.",
        "size": [W, H], "seed": SEED, "lineWidth": show.line_width, "duration": show.duration, "xs": xs, "ys": ys,
        "frames": frames,
    }


def write_json(path, doc):
    """One line per top-level part, as plan-parrots.json is."""
    with open(path, "w", encoding="utf-8") as f:
        f.write("{\n" + ",\n".join(f'"{k}":' + json.dumps(v, separators=(",", ":")) for k, v in doc.items()) + "\n}\n")


def close(test, got, expected, tolerance, what):
    got, expected = np.asarray(got, dtype=np.float64), np.asarray(expected, dtype=np.float64)
    test.assertEqual(got.shape, expected.shape, what)
    error = float(np.abs(got - expected).max()) if got.size else 0.0
    test.assertLessEqual(error, tolerance, f"{what}: {error:.3g} apart")


def same(test, got, expected, tolerance, what):
    """`got` and `expected` (JSON values) are equal, numbers within `tolerance`."""
    if isinstance(expected, dict):
        test.assertEqual(got.keys(), expected.keys(), what)
        for k in expected:
            same(test, got[k], expected[k], tolerance, f"{what}.{k}")
    elif isinstance(expected, list):
        test.assertEqual(len(got), len(expected), what)
        for i, (a, b) in enumerate(zip(got, expected)):
            same(test, a, b, tolerance, f"{what}[{i}]")
    elif isinstance(expected, float) or isinstance(got, float):
        test.assertAlmostEqual(got, expected, delta=tolerance, msg=what)
    else:
        test.assertEqual(got, expected, what)


class FramesGoldenTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.stored = json.loads((GOLDENS / "frames-small.json").read_text(encoding="utf-8"))
        cls.made = json.loads(json.dumps(frames_golden()))

    def test_the_golden_is_current(self):
        # scalars come from the planner's sines and springs, the picture from float32 layers: the
        # tolerances are the Python's across numpy versions and platforms
        made, stored = self.made, self.stored
        self.assertEqual(made.keys(), stored.keys())
        for key in ("size", "seed", "xs", "ys", "lineWidth", "duration"):
            self.assertEqual(made[key], stored[key], key)
        for a, b in zip(made["frames"], stored["frames"]):
            at = f"t = {b['time']}"
            for key in b:
                if key == "rgb":
                    close(self, a[key], b[key], 2e-6, f"picture at {at}")
                else:
                    same(self, a[key], b[key], 1e-9, f"{key} at {at}")
        self.assertEqual(len(made["frames"]), len(stored["frames"]))

    def test_the_moments_show_every_stage_and_every_overlay(self):
        frames = self.stored["frames"]
        self.assertEqual(sorted({f["picture"]["stage"] for f in frames}), [-1, 0, 1, 2, 3, 4, 5, 6])
        self.assertTrue(any(f["card"] for f in frames) and any(f["card"] is None for f in frames))
        self.assertTrue(any(0 < f["card"]["opacity"] < load_spec()["cards"]["opacity"] for f in frames if f["card"]))
        self.assertTrue(any(f["seedRings"] for f in frames))
        self.assertTrue(any(f["ink"]["lines"] and any(l["value"] < 1 for l in f["ink"]["lines"]) for f in frames))
        self.assertTrue(any(f["numbers"] and 0 < sum(f["numbers"]) < len(f["numbers"]) for f in frames))
        self.assertTrue(any(0 < f["picture"]["handoff"] < 1 for f in frames))
        self.assertTrue(any(len(f["sprites"]) == 3 for f in frames) and any(len(f["sprites"]) < 3 for f in frames))
        self.assertTrue(any(s["alpha"] < 1 for f in frames for s in f["sprites"]))


class ShowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.show = small_show()

    def test_a_frame_is_a_function_of_the_time(self):
        show = self.show
        times = [0.2, 3.3, 6.1, 9.0, 11.1, 14.0, 15.7, 17.5, 18.9]
        first = {t: json.dumps(summarize(show.frame(t))) for t in times}
        for t in reversed(times):
            self.assertEqual(json.dumps(summarize(show.frame(t))), first[t])

    def test_building_twice_makes_the_same_show(self):
        again = small_show()
        for t in (4.0, 12.0, 15.0):
            a, b = self.show.frame(t), again.frame(t)
            self.assertEqual(json.dumps(summarize(a)), json.dumps(summarize(b)))
            self.assertTrue(np.array_equal(self.show.composite(a), again.composite(b)))

    def test_composites_stay_in_range_and_end_in_paper(self):
        show = self.show
        for t in (0.3, 8.0, 12.0, 14.5, 17.0):
            picture = show.composite(show.frame(t))
            self.assertEqual(picture.shape, (144, 216, 3))
            self.assertTrue(float(picture.min()) >= 0 and float(picture.max()) <= 1.0000001)
        last = show.composite(show.frame(show.duration - 0.2))
        paper = np.array(show.compositor.style.paper) / 255
        self.assertTrue((last <= paper + 1e-6).all())                          # lines only darken it
        self.assertGreater(float((np.abs(last - paper).max(axis=2) < 1e-6).mean()), 0.5)   # and most is bare paper

    def test_a_guardian_without_metrics_is_an_error(self):
        with self.assertRaises(KeyError):
            show_module.Show(str(SNAPSHOTS), str(SNAPSHOTS / "template.svg"), load_spec(), SEED, metrics={})

    def test_cards_never_overlap_and_the_steps_come_in_order(self):
        show = self.show
        previous = -1
        for i in range(0, int(show.duration * 20)):
            frame = show.frame(i / 20)
            stage = frame["picture"]["stage"]
            self.assertGreaterEqual(stage, previous)
            previous = stage
            if frame["card"]:
                self.assertEqual(frame["card"]["step"], stage)
            self.assertEqual(frame["step"], stage if 0 <= stage < 6 else None)


class InkCoverageTests(unittest.TestCase):
    @staticmethod
    def line(points, value=1.0):
        return {"points": np.array(points, dtype=np.float64), "value": value}

    def test_a_horizontal_line_covers_the_pixels_it_runs_through(self):
        # two pixels wide along y = 5: rows 4 and 5 are full ink, rows 3 and 6 are not touched
        cov = show_module.ink_coverage([self.line([(2.0, 5.0), (8.0, 5.0)])], 12, 10, 2.0)
        self.assertEqual(cov[4, 4], 1.0)
        self.assertEqual(cov[5, 4], 1.0)
        self.assertEqual(cov[3, 4], 0.0)
        self.assertEqual(cov[6, 4], 0.0)
        # round ends: a pixel a whole width past the end is clear, the one right at it is covered
        self.assertEqual(cov[4, 9], 0.0)
        self.assertGreater(cov[4, 8], 0.5)

    def test_the_edge_is_soft_over_one_pixel(self):
        # a line 1.5 wide: full ink half a pixel inside its edge (0.25 from its middle), none half a
        # pixel outside (1.25), a pixel's worth of grey between
        cov = show_module.ink_coverage([self.line([(0.0, 5.0), (10.0, 5.0)])], 12, 10, 1.5)
        self.assertEqual((float(cov[4, 5]), float(cov[5, 5]), float(cov[3, 5])), (0.75, 0.75, 0.0))
        cov = show_module.ink_coverage([self.line([(0.0, 5.25), (10.0, 5.25)])], 12, 10, 1.5)
        self.assertEqual((float(cov[5, 5]), float(cov[4, 5]), float(cov[6, 5])), (1.0, 0.5, 0.0))

    def test_a_value_scales_the_ink_and_the_darker_line_wins(self):
        faint = self.line([(0.0, 5.0), (10.0, 5.0)], 0.4)
        bold = self.line([(5.0, 0.0), (5.0, 9.0)], 1.0)
        cov = show_module.ink_coverage([faint, bold], 12, 10, 2.0)
        self.assertAlmostEqual(float(cov[4, 2]), 0.4, places=6)
        self.assertEqual(cov[4, 4], 1.0)             # where they cross
        self.assertEqual(show_module.ink_coverage([bold, faint], 12, 10, 2.0)[4, 4], 1.0)

    def test_lines_off_the_picture_are_clipped(self):
        cov = show_module.ink_coverage([self.line([(-20.0, -5.0), (30.0, -3.0)]), self.line([(40.0, 2.0), (50.0, 3.0)])], 12, 10, 2.0)
        self.assertEqual(float(cov.max()), 0.0)

    def test_a_dot_is_round(self):
        cov = show_module.ink_coverage([self.line([(5.5, 5.5), (5.5, 5.5)])], 12, 10, 4.0)
        self.assertEqual((float(cov[5, 5]), float(cov[5, 7]), float(cov[5, 8])), (1.0, 0.5, 0.0))
        self.assertEqual(float(cov[7, 7]), 0.0)         # the corner of the square it isn't
        self.assertEqual(float(cov[0, 0]), 0.0)


class SpriteDrawTests(unittest.TestCase):
    METRICS = (40, 180, 95.0)
    STATE = (100.0, 200.0, 0.0, "right", 3, 1.0, 1.0, -4.0, 1.0)

    @classmethod
    def setUpClass(cls):
        pets.configure(load_spec())

    def draw(self, state=STATE, since=1.0, fade=1.0, height=70.0):
        return pets.sprite_draw("a", state, since, fade, height, 400.0, self.METRICS)

    def test_the_rotation_is_clockwise_where_the_tilt_is_pillows(self):
        # facing right leans forward at -4 (Pillow turns counter-clockwise); a clockwise view wants +4
        self.assertEqual(self.draw()["rotation"], 4.0)
        self.assertEqual(self.draw((100.0, 200.0, 0.0, "left", 3, 1.0, 1.0, 4.0, 1.0))["rotation"], -4.0)

    def test_the_cell_is_scaled_so_its_body_is_the_height(self):
        d = self.draw()
        depth = 0.9 + 0.16 * 0.5
        self.assertAlmostEqual(d["scale_x"], 70.0 * depth / 140, places=12)
        self.assertEqual(d["scale_x"], d["scale_y"])

    def test_squash_scales_each_axis_alone_and_lift_raises_the_sprite_not_the_shadow(self):
        d = self.draw((100.0, 200.0, 6.0, "idle", 2, 1.1, 0.9, 0.0, 1.0))
        self.assertAlmostEqual(d["scale_x"] / d["scale_y"], 1.1 / 0.9, places=12)
        self.assertEqual((d["x"], d["y"]), (100.0, 194.0))
        self.assertEqual((d["shadow"]["x"], d["shadow"]["y"]), (100.0, 200.0))
        ground = self.draw()
        self.assertLess(d["shadow"]["half_width"], ground["shadow"]["half_width"])
        self.assertLess(d["shadow"]["alpha"], ground["shadow"]["alpha"])

    def test_a_frame_wraps_to_its_row(self):
        for row, count in (("idle", 6), ("right", 8), ("wave", 4), ("busy", 6), ("review", 6)):
            self.assertEqual(self.draw((1.0, 1.0, 0.0, row, 13, 1.0, 1.0, 0.0, 1.0))["frame"], 13 % count)
        self.assertEqual(self.draw((1.0, 1.0, 0.0, "wave", -1, 1.0, 1.0, 0.0, 1.0))["frame"], 3)

    def test_it_fades_in_pops_and_is_not_drawn_when_it_cannot_be_seen(self):
        self.assertIsNone(self.draw(since=-0.1))
        self.assertIsNone(self.draw(since=0.0))                  # alpha 0
        self.assertIsNone(self.draw(fade=0.0))
        self.assertIsNone(self.draw((1.0, 1.0, 0.0, "idle", 0, 1.0, 1.0, 0.0, 0.0)))
        half = self.draw(since=0.09)
        self.assertAlmostEqual(half["alpha"], 0.5, places=12)
        popped = self.draw(since=0.1)
        self.assertGreater(popped["scale_x"], self.draw(since=2.0)["scale_x"])       # swelling as it appears
        self.assertEqual(self.draw(since=2.0)["alpha"], 1.0)

    def test_the_crew_fades_with_the_show(self):
        self.assertAlmostEqual(self.draw(fade=0.25)["alpha"], 0.25, places=12)


class TimelineTests(unittest.TestCase):
    INTRO, STEP = 0.6, 2.5

    def card(self, k, t):
        return reveal.card_fade(k, t, self.INTRO, self.STEP)

    def test_a_card_lives_inside_its_step(self):
        for k in range(6):
            start = self.INTRO + k * self.STEP
            self.assertEqual(self.card(k, start), 0.0)
            self.assertAlmostEqual(self.card(k, start + self.STEP), 0.0, places=12)
            self.assertEqual(self.card(k, start + self.STEP / 2), 1.0)
            self.assertEqual(self.card(k, start - 0.01), 0.0)
            self.assertEqual(self.card(k, start + self.STEP + 0.01), 0.0)
            self.assertTrue(0 < self.card(k, start + 0.05) < 1 and 0 < self.card(k, start + self.STEP - 0.05) < 1)

    def test_a_brisker_show_fades_faster(self):
        # the fade is CARD_FADE over the square root of the pace: 0.15 / sqrt(1.5 / step)
        for step in (0.75, 1.5, 3.0):
            fade = 0.15 / math.sqrt(1.5 / step)
            self.assertAlmostEqual(reveal.card_fade(0, 0.6 + fade, 0.6, step), 1.0, places=12)
            self.assertLess(reveal.card_fade(0, 0.6 + fade * 0.99, 0.6, step), 1.0)

    def test_the_crew_fades_out_over_the_last_of_the_show(self):
        self.assertEqual(reveal.crew_fade(18.0, 19.0), 1.0)
        self.assertEqual(reveal.crew_fade(18.7, 19.0), 1.0)
        self.assertAlmostEqual(reveal.crew_fade(18.85, 19.0), 0.5, places=12)
        self.assertEqual(reveal.crew_fade(19.0, 19.0), 0.0)
        self.assertEqual(reveal.crew_fade(25.0, 19.0), 0.0)

    def test_the_handoff_runs_as_the_steps_end(self):
        end = self.INTRO + 6 * self.STEP
        self.assertEqual(reveal.handoff(end - 1, self.INTRO, self.STEP), 0.0)
        self.assertEqual(reveal.handoff(end, self.INTRO, self.STEP), 0.0)
        self.assertAlmostEqual(reveal.handoff(end + 0.075, self.INTRO, self.STEP), 0.5, places=12)
        self.assertEqual(reveal.handoff(end + 0.15, self.INTRO, self.STEP), 1.0)

    def test_a_ring_pops_in_swells_and_goes_when_its_paint_has_spread(self):
        seed = (6.0, 50.0, 40.0, 3)
        ring = lambda t, spread=7.0: reveal.seed_ring(seed, spread, t, self.INTRO, self.STEP, 8.5, 0.3)
        self.assertIsNone(ring(5.99))
        self.assertIsNone(ring(6.0))                            # not yet opaque at all
        self.assertAlmostEqual(ring(6.022)["alpha"], 0.3, places=12)        # a tenth of the pop, three times as fast
        mid = ring(6.11)
        self.assertEqual((mid["x"], mid["y"]), (50.0, 40.0))
        self.assertEqual(mid["alpha"], 1.0)
        self.assertAlmostEqual(mid["radius"], 8.5 * (1 + 0.35 * 0.5), places=12)      # half way, swollen the most
        self.assertEqual(ring(6.5)["radius"], 8.5)              # settled
        self.assertEqual(ring(6.5)["alpha"], 1.0)
        # its paint spread at 7.0: gone 0.1 + 0.3 s after
        self.assertEqual(ring(7.1)["alpha"], 1.0)
        self.assertLess(ring(7.25)["alpha"], 1.0)
        self.assertIsNone(ring(7.4))
        # every ring is gone before the paints step ends, whichever its paint did
        end = self.INTRO + 3 * self.STEP
        self.assertIsNone(ring(end, spread=99.0))
        self.assertLess(ring(end - 0.2, spread=99.0)["alpha"], 1.0)


class ClipToolTests(unittest.TestCase):
    """making_of_clip.py is a thin driver over the shared modules; what runs without ffmpeg, fonts
    or node is its plan file, which is also what reads the spec's credits."""

    def test_the_plan_file_is_the_shared_modules_inputs_and_plan(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "plan.json"
            subprocess.run([sys.executable, str(ROOT / "tools" / "factory" / "making_of_clip.py"), str(SNAPSHOTS),
                            str(SNAPSHOTS), "/dev/null", "--seed", str(SEED), "--plan-json", str(out)], check=True)
            doc = json.loads(out.read_text(encoding="utf-8"))
        small = json.loads((SNAPSHOTS / "inputs-small.json").read_text(encoding="utf-8"))
        self.assertEqual(doc["inputs"], small["inputs"])
        spec = load_spec()
        self.assertEqual(doc["spec"], spec)
        pets.configure(spec)
        self.assertEqual(doc["plan"], json.loads(json.dumps(pets.plan_data(pets.plan(small["inputs"])))))
        self.assertEqual([p["id"] for p in doc["plan"]["pets"]], spec["crew"]["pets"])
        end = spec["timing"]["intro"] + 6 * spec["timing"]["step"] + spec["timing"]["outro"]
        self.assertEqual(len(doc["states"]["pets"][0]), round(end * doc["states"]["fps"]) + 1)

    def test_a_method_without_a_credit_stops_it(self):
        spec = load_spec()
        spec["steps"][0]["methods"] = ["Informative Drawings"]          # the model's entry has no credit line of that shape
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "making-of.json"
            path.write_text(json.dumps(spec), encoding="utf-8")
            done = subprocess.run([sys.executable, str(ROOT / "tools" / "factory" / "making_of_clip.py"), str(SNAPSHOTS),
                                   str(SNAPSHOTS), "/dev/null", "--spec", str(path), "--plan-json", str(Path(tmp) / "p.json")],
                                  capture_output=True, text=True)
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("Informative Drawings", done.stderr)


class MetricsTests(unittest.TestCase):
    def test_the_bundled_metrics_are_what_the_sheets_give(self):
        made = json.loads(json.dumps(pets.metrics_table(str(RESOURCES))))
        stored = json.loads(METRICS.read_text(encoding="utf-8"))
        self.assertEqual(made, stored)

    def test_every_guardian_of_the_crew_has_metrics(self):
        crew = load_spec()["crew"]["pets"]
        self.assertTrue(set(crew) <= set(load_metrics()))
        for pid, (top, foot, cx) in load_metrics().items():
            self.assertTrue(0 <= top < foot < pets.CELL[1] and 0 <= cx < pets.CELL[0], pid)


if __name__ == "__main__":
    if "--write-goldens" in sys.argv:
        write_json(GOLDENS / "frames-small.json", frames_golden())
    else:
        unittest.main()
