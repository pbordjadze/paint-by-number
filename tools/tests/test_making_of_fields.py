"""The making-of show with no crew (tools/factory/making_of_fields.py): its fields by hand, the show
built from the small show fixture, and the numbers Sources/MakingOf's `FieldShow` is compared with.

    python3 -m unittest discover -s tools/tests -p 'test_making_of_fields.py'
    python3 tools/tests/test_making_of_fields.py --write-goldens     # after changing the field show

Needs numpy and Pillow. --write-goldens writes Tests/MakingOfTests/Fixtures/fields-small.json: pieces
of the field show on inputs both languages make the same way (the geodesic, the pacing, the noise,
the resizing), and the small show fixture (Fixtures/show-small, 216 x 144) built as the show is built,
and again cropped to an odd size (215 x 143): its seeds and every pick chance made, its fields on a
24 x 16 lattice, the fuses and the numbers' moments, and moments of it (seventeen, and three), each with
its frame (the lines by their counts, three of their points and a fingerprint of all of them; the
sparks, stars, numbers, rings and card as they are) and the composite picture on the lattice. The test
here fails when the committed file is not what the Python makes now; FieldShowTests replays the same
file in Swift."""

import json
import math
from pathlib import Path
import re
import shutil
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "factory"))
import making_of_exact as exact
import making_of_fields as fields
import making_of_pets as pets
import making_of_reveal as reveal
import making_of_show as show_module

FIXTURES = ROOT / "Tests" / "MakingOfTests" / "Fixtures"
SNAPSHOTS = FIXTURES / "show-small"
RESOURCES = ROOT / "App" / "PaintByNumber" / "Resources"
SEED = 7
POINTS = (24, 16)


def load_spec():
    return json.loads((RESOURCES / "making-of.json").read_text(encoding="utf-8"))


def small_show():
    return fields.FieldShow(str(SNAPSHOTS), str(SNAPSHOTS / "template.svg"), load_spec(), SEED)


ODD = (215, 143)


def odd_show():
    """The small show cropped to an odd size: the pictures' top left, and the same template, whose lines and
    numbers then run past the edge by a pixel."""
    with tempfile.TemporaryDirectory() as folder:
        for name in ("working-image.ppm", "structure.pgm", "smoothed.ppm", "palette.ppm", "simplified.ppm"):
            Image.open(SNAPSHOTS / name).crop((0, 0) + ODD).save(Path(folder) / name)
        shutil.copy(SNAPSHOTS / "template.svg", folder)
        return fields.FieldShow(folder, str(Path(folder) / "template.svg"), load_spec(), SEED)


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


def moments(show):
    """Seventeen moments that between them show every stage: the photo, the sketch's frost early and late,
    the blooms and their tide lines, the seeds dropping and the dye running, the bits melting, the fuse (the
    lines burning grey and darkening, the sparks) early, half way and late, the outlines relaxing and the
    numbers coming out as stars, the hand-off to the real template, and the end of the hold."""
    s = [show.intro + k * show.step for k in range(7)]
    return [0.12, s[0] + 0.6, s[0] + 1.5, s[1] + 0.8, s[1] + 1.7, s[2] + 0.45, s[2] + 1.6, s[3] + 1.2, s[4] + 0.5,
            s[4] + 1.0, s[4] + 1.6, s[5] + 0.5, s[5] + 0.9, s[5] + 1.3, s[5] + 2.1, s[6] + 0.05, show.duration - 0.1]


def summarize(frame):
    """A frame as JSON: the lines by their stroke, point count, value and three of their points, with
    one fingerprint of all their points; the rest as it is."""
    lines = frame["ink"]
    flat = np.concatenate([line["points"].ravel() for line in lines]) if lines else np.zeros(0)
    ends = lambda pts: [float(v) for i in (0, len(pts) // 2, len(pts) - 1) for v in pts[i]]
    ink = {"lines": [{"stroke": line["stroke"], "points": len(line["points"]), "value": line["value"],
                      "ends": ends(line["points"])} for line in lines],
           "fingerprint": reveal.fingerprint(flat)}
    out = {k: frame[k] for k in ("time", "step", "picture", "numbers", "seed_rings", "sprites", "card", "sparks", "stars")}
    out["ink"] = ink
    return camel(out)


def synthetic():
    """The geodesic, the pacing, the noise and the resizing on inputs made from SplitMix64's seed 123 in
    this order, which FieldShowTests makes the same way. The results are bit for bit the same (a fingerprint
    of every value), but for the noise through `exp`."""
    rng = pets.SplitMix64(123)
    plane = lambda h, w: np.array([0.5 + 3 * rng.random() for _ in range(h * w)]).reshape(h, w)
    cost = plane(29, 37)
    start = np.full((29, 37), np.inf)
    start[4, 7], start[20, 30] = 0.0, 1.5
    column, row = plane(5, 1), plane(1, 6)
    seeds = [(0.0, 3.4, 5.9), (2.5, 36.0, 28.0), (1.0, 50.7, -3.2)]      # the last is outside the plane
    out = {"geodesic": {
        "seeds": reveal.fingerprint(fields.geodesic(cost, seeds, sweeps=3)),
        "start": reveal.fingerprint(fields.geodesic(cost, start=start, sweeps=2)),
        "column": reveal.fingerprint(fields.geodesic(column, [(0.0, 0, 3)], sweeps=2)),
        "row": reveal.fingerprint(fields.geodesic(row, [(0.0, 4, 0)], sweeps=1))}}

    times = np.array([rng.random() * 50 for _ in range(6000)])
    times[::97] = times[1::97]                                        # equal times share a rank
    times[::331] = np.inf
    over = np.array([rng.random() < 0.7 for _ in range(6000)])
    few = np.array([0.0, 1.0, 2.0, 3.0, 4.0, 100.0, np.inf])
    out["paced"] = {
        "all": reveal.fingerprint(fields.paced(times, 3.0, 5.5)),
        "over": reveal.fingerprint(fields.paced(times, 3.0, 5.5, over=over)),
        "few": reveal.fingerprint(fields.paced(few, 0.0, 1.0, over=np.array([True] * 5 + [False] * 2)))}

    noise = fields.Noise(SEED)
    warped = noise.warped((23, 31), 5.0)
    out["noise"] = {
        "lattices": reveal.fingerprint(np.concatenate([g.ravel() for g in noise.grids])),
        "warped": reveal.fingerprint(warped),
        "grain": reveal.fingerprint(noise.fbm(*(np.mgrid[0:23, 0:31][::-1].astype(np.float64) / 6.0), 4, 5)),
        "mean": float(warped.mean()), "deviation": float(warped.std()),
        "rough": [float(v) for v in noise.rough((23, 31), 5.0, 0.4).ravel()]}

    big = np.array([rng.random() for _ in range(23 * 31)]).reshape(23, 31)
    small = fields.shrink(big)
    out["resize"] = {"shrink": reveal.fingerprint(small), "grow": reveal.fingerprint(fields.grow(small, (31, 23)))}
    out["percentile"] = exact.percentile(np.array([rng.below(256) for _ in range(5000)]), 98)
    return out


def part(show, at):
    """What the golden keeps of a built show: its size, seeds and picks, its fields on the lattice, its
    fuses and the numbers' moments, and its frames at the moments `at` with the pictures on the lattice."""
    W, H = show.size
    xs, ys = lattice(W, POINTS[0]), lattice(H, POINTS[1])
    sample = lambda plane: [float(plane[y, x]) for y in ys for x in xs]
    picks = show.picks
    frames = []
    for t in at:
        frame = show.frame(t)
        entry = summarize(frame)
        picture = show.composite(frame)
        entry["rgb"] = [round(float(picture[y, x, c]), 8) for y in ys for x in xs for c in range(3)]
        frames.append(entry)
    return {
        "size": [W, H], "lineWidth": show.line_width, "duration": show.duration, "xs": xs, "ys": ys,
        "seeds": [list(seed) for seed in show.seeds],
        "picks": {"sketch": [list(v) for v in picks["sketch"]], "shading": [list(v) for v in picks["shading"]],
                  "fuse": [list(v) for v in picks["fuses"][0]], "relax": [list(v) for v in picks["fuses"][1]],
                  "melting": picks["melting"]},
        "times": {name: sample(plane) for name, plane in show.times.items()},
        "spread": [float(v) for v in show.spread],
        "strokes": [{"points": len(st.jagged), "start": st.t0, "duration": st.dur, "fuse": [float(v) for v in at],
                     "relax": [float(v) for v in st.relax]} for st, at in zip(show.strokes, show.fuses)],
        "numberTimes": show.number_times,
        "frames": frames,
    }


def fields_golden():
    small, odd = small_show(), odd_show()
    s = [small.intro + k * small.step for k in range(7)]
    return {
        "about": "Tests/MakingOfTests/Fixtures/show-small built by making_of_fields.FieldShow (seed 7, the shipped spec), "
                 "whole and cropped to 215 x 143, pieces of it on inputs of SplitMix64's seed 123, and moments of the "
                 "show: each frame, and the composite picture on a lattice, row-major over xs by ys, three values a "
                 "pixel. Written by tools/tests/test_making_of_fields.py --write-goldens.",
        "seed": SEED,
        "streams": [[rng.random() for _ in range(3)]
                    for rng in (pets.stream(SEED, fields.STREAM_FIELDS + k, 0) for k in range(7))],
        "synthetic": synthetic(),
        "small": part(small, moments(small)),
        "odd": part(odd, [s[1] + 0.8, s[4] + 1.0, s[5] + 1.3]),
    }


def write_json(path, doc):
    """One line per top-level part, as frames-small.json is."""
    with open(path, "w", encoding="utf-8") as f:
        f.write("{\n" + ",\n".join(f'"{k}":' + json.dumps(v, separators=(",", ":")) for k, v in doc.items()) + "\n}\n")


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


class GoldenTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.stored = json.loads((FIXTURES / "fields-small.json").read_text(encoding="utf-8"))
        cls.made = json.loads(json.dumps(fields_golden()))

    def test_the_golden_is_current(self):
        # the fields are float64 sums through exp, log and pow, the picture float32 layers: the tolerances
        # here are the Python's across numpy versions and platforms, FieldShowTests has Swift's own
        made, stored = self.made, self.stored
        self.assertEqual(made.keys(), stored.keys())
        for key in ("seed", "streams"):
            self.assertEqual(made[key], stored[key], key)
        for key in ("geodesic", "paced", "resize", "percentile"):
            self.assertEqual(made["synthetic"][key], stored["synthetic"][key], key)
        same(self, made["synthetic"]["noise"], stored["synthetic"]["noise"], 1e-12, "noise")
        for name in ("small", "odd"):
            a, b = made[name], stored[name]
            self.assertEqual(a.keys(), b.keys())
            for key in ("size", "xs", "ys", "seeds"):
                self.assertEqual(a[key], b[key], f"{name}.{key}")
            for key in ("lineWidth", "duration", "spread", "strokes", "numberTimes"):
                same(self, a[key], b[key], 1e-9, f"{name}.{key}")
            same(self, a["times"], b["times"], 4e-6, f"{name}.times")        # float32: two steps of one at 16 s
            for key in ("sketch", "shading", "fuse", "relax"):                 # the times of the picks come through log
                same(self, a["picks"][key], b["picks"][key], 1e-9, f"{name}.picks.{key}")
            self.assertEqual(a["picks"]["melting"], b["picks"]["melting"])
            self.assertEqual(len(a["frames"]), len(b["frames"]))
            for x, y in zip(a["frames"], b["frames"]):
                at = f"{name} at t = {y['time']}"
                for key in y:
                    same(self, x[key], y[key], 2e-6 if key == "rgb" else 1e-9, f"{key} {at}")

    def test_the_moments_show_every_stage_and_every_mark(self):
        frames = self.stored["small"]["frames"]
        self.assertEqual(sorted({f["picture"]["stage"] for f in frames}), [-1, 0, 1, 2, 3, 4, 5, 6])
        self.assertTrue(any(f["card"] for f in frames) and any(f["card"] is None for f in frames))
        self.assertTrue(any(f["seedRings"] for f in frames))
        self.assertTrue(any(f["sparks"] for f in frames) and any(f["stars"] for f in frames))
        self.assertTrue(any(0 < f["picture"]["handoff"] < 1 for f in frames))
        self.assertTrue(any(f["ink"]["lines"] and any(l["value"] < 1 for l in f["ink"]["lines"]) for f in frames))
        self.assertTrue(any(f["numbers"] and 0 < sum(f["numbers"]) < len(f["numbers"]) for f in frames))
        self.assertTrue(all(f["sprites"] == [] for f in frames))


if __name__ == "__main__":
    if "--write-goldens" in sys.argv:
        write_json(FIXTURES / "fields-small.json", fields_golden())
    else:
        unittest.main()
