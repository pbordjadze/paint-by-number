"""The making-of show's layers and compositor (tools/factory/making_of_layers.py and
making_of_compose.py), and the numbers Sources/MakingOf's tests compare their port with.

    python3 -m unittest discover -s tools/tests -p 'test_making_of_layers.py'
    python3 tools/tests/test_making_of_layers.py --write-goldens     # after changing either module

Needs numpy and Pillow. --write-goldens writes Tests/MakingOfTests/Fixtures/layers-small.json (the
layers of the 216 x 144 snapshots in Fixtures/show-small, on a 31 x 21 lattice) and
compose-small.json (the pictures of the show at fourteen moments, on a 16 x 11 lattice, from
closed-form reveal times and ink that LayersTests and CompositorTests build the same way). The
tests here fail when a committed file is not what the Python makes now."""

import json
from pathlib import Path
import sys
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "factory"))
import making_of_compose as compose
import making_of_layers as layers

FIXTURES = ROOT / "Tests" / "MakingOfTests" / "Fixtures"
SNAPSHOTS = FIXTURES / "show-small"
SPEC = ROOT / "App" / "PaintByNumber" / "Resources" / "making-of.json"
FIELDS = ("sketch", "shading", "paints", "merged", "lift", "clear")
TIMES_ABOUT = ("The moments are 0.3 s, a quarter and 70 % into each step, and 0.9 s after the last step. "
               "Field k of FIELDS is (intro + k step + 0.1 + (step - 0.4) u) with "
               "u = 0.5 + 0.5 sin(2 x/w + 3.1 y/h + 1.7 k), rounded to 1/4096 s (so no libm's sine can "
               "move it) and kept as float32; ink is ((x + 2 y) mod 7) / 6.")


def lattice(size, points):
    """`points` pixel columns (or rows) spread over 0...size - 1, rounded half up."""
    return [(i * (size - 1) + (points - 1) // 2) // (points - 1) for i in range(points)]


def exact(name, mode):
    """A snapshot as 0...1 float64, so that 8-bit values are k / 255 exactly, as the port reads them."""
    return np.asarray(Image.open(SNAPSHOTS / name).convert(mode), dtype=np.float64) / 255


def synthetic_times(shape, intro, step):
    """Six reveal fields shaped like the real ones: step k's sweeps the picture between 0.1 s
    after the step starts and 0.3 s before it ends, in a smooth pattern of position."""
    h, w = shape
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    reveal = lambda k: intro + k * step + 0.1 + (step - 0.4) * (0.5 + 0.5 * np.sin(2.0 * xs / w + 3.1 * ys / h + 1.7 * k))
    return {name: (np.round(reveal(k) * 4096) / 4096).astype(np.float32) for k, name in enumerate(FIELDS)}


def synthetic_ink(shape):
    h, w = shape
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    return (((xs + 2 * ys) % 7) / 6.0).astype(np.float32)


def moments(intro, step):
    return [0.3] + [round(intro + k * step + f * step, 6) for k in range(6) for f in (0.25, 0.7)] + [
        round(intro + 6 * step + 0.9, 6)]


def layers_golden():
    photo, smoothed = exact("working-image.ppm", "RGB"), exact("smoothed.ppm", "RGB")
    palette, simplified = exact("palette.ppm", "RGB"), exact("simplified.ppm", "RGB")
    d = layers.derive(photo, exact("structure.pgm", "L"), smoothed, palette, simplified)
    h, w = photo.shape[:2]
    xs, ys = lattice(w, 31), lattice(h, 21)
    at = lambda plane: [round(float(plane[y, x]), 8) for y in ys for x in xs]
    detextured = [round(float(d["detextured"][y, x, c]), 8) for y in ys for x in xs for c in range(3)]
    tone = d["tone"]
    return {
        "about": "Tests/MakingOfTests/Fixtures/show-small through making_of_layers.derive (float64); written by "
                 "tools/tests/test_making_of_layers.py --write-goldens. Values are row-major over xs by ys.",
        "size": [w, h], "xs": xs, "ys": ys, "style": layers.style_dict(),
        "tone": {"darkest": tone.lo, "span": tone.span, "gamma": tone.gamma},
        "lattice": {"coherence": at(d["coherence"]), "survivors": at(d["survivors"]), "texture": at(d["texture"]),
                    "detextured": detextured, "smoothedLightness": at(layers.lightness(smoothed)),
                    "paletteGrey": at(tone(palette)[..., 0]), "simplifiedGrey": at(d["toned"][..., 0])},
        "statistics": {
            "coherenceMean": float(d["coherence"].mean()), "variationMean": float(d["variation"].mean()),
            "variation90": float(np.percentile(d["variation"], 90)),
            "survivorsMean": float(d["survivors"].mean()), "survivorsMax": float(d["survivors"].max()),
            "textureMean": float(d["texture"].mean()),
            "detexturedMean": [float(d["detextured"][..., c].mean()) for c in range(3)],
            "simplifiedGreyMean": float(d["toned"].mean()),
        },
    }


def compose_golden():
    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    intro, step = spec["timing"]["intro"], spec["timing"]["step"]
    stages = layers.Stages.read(SNAPSHOTS)          # float32, as the clip tool runs it
    h, w = stages.structure.shape
    times, ink = synthetic_times((h, w), intro, step), synthetic_ink((h, w))
    comp = compose.Compositor(stages.layers(), stages, times, intro, step)
    xs, ys = lattice(w, 31)[::2], lattice(h, 21)[::2]
    shots = []
    for t in moments(intro, step):
        pic = comp.picture(t, ink)
        shots.append({"t": t, "stage": compose.stage_of(t, intro, step),
                      "rgb": [round(float(pic[y, x, c]), 8) for y in ys for x in xs for c in range(3)]})
    return {
        "about": "Tests/MakingOfTests/Fixtures/show-small composited by making_of_compose.Compositor (float32, as the "
                 "clip tool runs it); written by tools/tests/test_making_of_layers.py --write-goldens. " + TIMES_ABOUT,
        "size": [w, h], "intro": intro, "step": step, "xs": xs, "ys": ys,
        "times": {name: [round(float(times[name][y, x]), 9) for y in ys for x in xs] for name in FIELDS},
        "ink": [round(float(ink[y, x]), 7) for y in ys for x in xs],
        "pictures": shots,
    }


def write_json(path, doc):
    """One line per top-level part."""
    with open(path, "w", encoding="utf-8") as f:
        f.write("{\n" + ",\n".join(f'"{k}":' + json.dumps(v, separators=(",", ":")) for k, v in doc.items()) + "\n}\n")


def reference_tone_curve(rgb, low, high, mean):
    """The curve as making_of_layers computed it before it took paint counts: forty powers of every
    pixel, in float32."""
    L = layers.lightness(rgb)
    lo, hi = np.percentile(L, (1, 99))
    span = max(float(hi - lo), 1e-6)
    t = np.clip((L - lo) / span, 0, 1)
    want = (mean - low) / (high - low)
    a, b = 0.05, 20.0
    for _ in range(40):
        g = (a * b) ** 0.5
        a, b = (g, b) if (t ** g).mean() > want else (a, g)
    g = (a * b) ** 0.5
    return lambda img: (low + (high - low) * np.clip((layers.lightness(img) - lo) / span, 0, 1) ** g)[..., None]


def close(test, got, expected, tolerance, what):
    got, expected = np.asarray(got, dtype=np.float64), np.asarray(expected, dtype=np.float64)
    test.assertEqual(got.shape, expected.shape, what)
    error = float(np.abs(got - expected).max())
    test.assertLessEqual(error, tolerance, f"{what}: {error:.3g} apart")


class ToneCurveTests(unittest.TestCase):
    def test_counted_percentile_is_numpys(self):
        rng = np.random.default_rng(5)
        for n in (1, 2, 5, 40):
            values = np.sort(rng.random(n))
            counts = rng.integers(1, 3000, n)
            for q in (0, 1, 33, 50, 90, 99, 99.5, 100):
                self.assertAlmostEqual(layers.counted_percentile(values, counts, q),
                                       float(np.percentile(np.repeat(values, counts), q)), delta=1e-15)

    def test_curve_equals_the_per_pixel_one(self):
        simplified = exact("simplified.ppm", "RGB")
        tones = layers.DEFAULT_TONES
        curve = layers.ToneCurve(simplified, tones["low"], tones["high"], tones["mean"])
        old = reference_tone_curve(simplified.astype(np.float32), tones["low"], tones["high"], tones["mean"])
        # measured at the fixture and at 1024 x 682: at most 4e-8, the old curve's float32
        close(self, curve(simplified), old(simplified.astype(np.float32)), 1e-6, "greys")

    def test_curve_averages_the_wanted_mean(self):
        simplified = exact("simplified.ppm", "RGB")
        tones = layers.DEFAULT_TONES
        greys = layers.ToneCurve(simplified, tones["low"], tones["high"], tones["mean"])(simplified)
        self.assertAlmostEqual(float(greys.mean()), tones["mean"], delta=1e-9)
        self.assertGreaterEqual(float(greys.min()), tones["low"] - 1e-12)
        self.assertLessEqual(float(greys.max()), tones["high"] + 1e-12)

    def test_flat_picture_gets_the_darkest_grey(self):
        flat = np.full((6, 9, 3), 0.4)
        greys = layers.ToneCurve(flat, 0.62, 0.92, 0.85)(flat)
        self.assertTrue(np.isfinite(greys).all())
        self.assertAlmostEqual(float(greys.min()), 0.62, places=12)

    def test_paints_are_counted_by_lightness(self):
        picture = np.zeros((2, 3, 3))
        picture[:, 0] = 1
        picture[0, 1] = (0.5, 0.5, 0.5)
        colors, counts = layers.paint_counts(picture)
        self.assertEqual(counts.tolist(), [3, 1, 2])
        self.assertEqual(colors[0].tolist(), [0, 0, 0])


class DeriveTests(unittest.TestCase):
    @staticmethod
    def stages(photo, structure):
        flat = np.full(photo.shape, 0.5)
        return layers.derive(photo, structure, flat, flat, flat)

    def test_a_flat_picture_has_nothing_to_find(self):
        photo = np.full((24, 40, 3), 0.5)
        d = self.stages(photo, np.zeros((24, 40)))
        for name in ("coherence", "variation", "survivors", "texture"):
            self.assertEqual(float(np.abs(d[name]).max()), 0.0, name)
        self.assertTrue(np.array_equal(d["detextured"], photo))

    def test_a_contour_is_coherent_and_a_fine_texture_is_not(self):
        h, w = 64, 128
        step = np.zeros((h, w, 3))
        step[:, w // 2:] = 1
        checker = np.zeros((h, w, 3))
        checker[(np.indices((h, w)).sum(axis=0) % 2) == 0] = 1
        edge = self.stages(step, np.zeros((h, w)))["coherence"]
        fine = self.stages(checker, np.zeros((h, w)))["coherence"]
        self.assertGreater(float(edge[h // 2, w // 2]), 0.95)
        self.assertLess(float(fine[h // 2, w // 2]), 0.2)

    def test_texture_is_smeared_toward_a_blur_and_the_contour_stays(self):
        h, w = 64, 128
        photo = np.zeros((h, w, 3))
        photo[:, w // 2:] = 1
        photo[(np.indices((h, w)).sum(axis=0) % 2) == 0] += 0.2          # texture on both sides
        photo = np.clip(photo, 0, 1)
        d = self.stages(photo, np.ones((h, w)))
        self.assertGreater(float(d["texture"][h // 2, w // 4]), 0.5)
        self.assertLess(float(d["texture"][h // 2, w // 2]), float(d["texture"][h // 2, w // 4]))
        smear = np.abs(d["detextured"] - photo)
        self.assertGreater(float(smear[h // 2, w // 4].max()), 0.05)

    def test_float32_and_float64_pictures_agree(self):
        photo, structure = exact("working-image.ppm", "RGB"), exact("structure.pgm", "L")
        flat = exact("simplified.ppm", "RGB")
        a = layers.derive(photo, structure, flat, flat, flat)
        b = layers.derive(photo.astype(np.float32), structure.astype(np.float32), flat, flat, flat)
        for name in ("coherence", "survivors", "texture", "detextured"):
            close(self, a[name], b[name], 2e-5, name)

    def test_the_windows_radius_is_the_pipelines(self):
        # round(0.0025 * 1600 * width / 1024), ties to even, as it was written before the style
        for width in range(1, 4097):
            self.assertEqual(max(1, round(layers.STYLE.rtv_window * width / 1024)),
                             max(1, round(0.0025 * 1600 * width / 1024)), width)
        self.assertEqual(max(1, round(layers.STYLE.rtv_window * 640 / 1024)), 2)


class CompositorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = json.loads(SPEC.read_text(encoding="utf-8"))
        cls.intro, cls.step = spec["timing"]["intro"], spec["timing"]["step"]
        cls.stages = layers.Stages.read(SNAPSHOTS)
        shape = cls.stages.structure.shape
        cls.times = synthetic_times(shape, cls.intro, cls.step)
        cls.ink = synthetic_ink(shape)
        cls.layers = cls.stages.layers()
        cls.comp = compose.Compositor(cls.layers, cls.stages, cls.times, cls.intro, cls.step)

    def start(self, k):
        return self.intro + k * self.step

    def test_stages(self):
        self.assertEqual([compose.stage_of(t, self.intro, self.step) for t in (0, 0.59, 0.6, 3.09, 3.1, 15.59, 15.6, 99)],
                         [-1, -1, 0, 0, 1, 5, 6, 6])

    def test_each_step_ends_in_the_next_layer(self):
        for k in range(4):
            end = self.start(k + 1)
            for t in (end - 1e-9, end):
                # the synthetic fields finish 0.3 s before the step ends, past every ramp and dip
                close(self, self.comp.picture(t), self.layers[k + 1], 1e-5, f"step {k + 1} at {t}")

    def test_the_last_steps_end_in_paper(self):
        paper = np.broadcast_to(layers.PAPER, self.layers[0].shape)
        for t in (self.start(6) - 1e-9, self.start(6), self.start(6) + 3):
            close(self, self.comp.picture(t), paper, 1e-6, f"paper at {t}")

    def test_the_ink_step_starts_where_the_merged_step_ended(self):
        close(self, self.comp.picture(self.start(4)), self.layers[4], 1e-6, "ink step start")
        close(self, self.comp.picture(self.start(5) - 1e-9), self.stages.lifted * self.comp.paper, 1e-6, "lifted")

    def test_lines_only_show_where_the_step_draws_them(self):
        for k in range(4):                  # the steps without lines
            t = self.start(k) + 1.0
            self.assertTrue(np.array_equal(self.comp.picture(t, self.ink), self.comp.picture(t)))
        for k in (4, 5, 6):
            t = self.start(k) + 1.0
            with_ink, without = self.comp.picture(t, self.ink), self.comp.picture(t)
            self.assertTrue((with_ink <= without + 1e-7).all())
            self.assertLess(float(with_ink.mean()), float(without.mean()))
            self.assertTrue(np.array_equal(self.comp.picture(t, np.zeros_like(self.ink)), without))

    def test_full_ink_is_the_ink_color(self):
        t = self.start(6) + 1
        full = self.comp.picture(t, np.ones_like(self.ink))
        close(self, full, np.broadcast_to(layers.PAPER * layers.INK, full.shape), 1e-6, "ink on paper")

    def test_settling_only_darkens(self):
        for k in (2, 3):
            t = self.start(k) + 1.2
            field = [self.times["sketch"], self.times["shading"], self.times["paints"], self.times["merged"]][k]
            m = compose.smoothstep((t - field) / (layers.STYLE.soft_early if k < 2 else layers.STYLE.soft_late))[..., None]
            plain = self.layers[k] + (self.layers[k + 1] - self.layers[k]) * m
            self.assertTrue((self.comp.picture(t) <= plain + 1e-6).all())
            self.assertLess(float(self.comp.picture(t).sum()), float(plain.sum()))


class GoldenTests(unittest.TestCase):
    def test_goldens_were_made_with_the_shipped_spec(self):
        spec = json.loads(SPEC.read_text(encoding="utf-8"))
        self.assertEqual(spec["tones"], layers.DEFAULT_TONES)
        self.assertEqual(spec["sketch"], layers.DEFAULT_SKETCH)

    def test_layers_golden_is_current(self):
        made = json.loads(json.dumps(layers_golden()))
        stored = json.loads((FIXTURES / "layers-small.json").read_text(encoding="utf-8"))
        self.assertEqual(made.keys(), stored.keys())
        for key in ("size", "xs", "ys", "style"):
            self.assertEqual(made[key], stored[key], key)
        for key in made["tone"]:
            self.assertAlmostEqual(made["tone"][key], stored["tone"][key], delta=1e-7, msg=key)
        for key in made["lattice"]:
            close(self, made["lattice"][key], stored["lattice"][key], 2e-7, key)
        for key, value in made["statistics"].items():
            close(self, value, stored["statistics"][key], 2e-7, key)

    def test_compose_golden_is_current(self):
        made = json.loads(json.dumps(compose_golden()))
        stored = json.loads((FIXTURES / "compose-small.json").read_text(encoding="utf-8"))
        self.assertEqual(made.keys(), stored.keys())
        for key in ("size", "intro", "step", "xs", "ys"):
            self.assertEqual(made[key], stored[key], key)
        for name in FIELDS:
            close(self, made["times"][name], stored["times"][name], 1e-9, name)
        close(self, made["ink"], stored["ink"], 1e-6, "ink")
        self.assertEqual([p["t"] for p in made["pictures"]], [p["t"] for p in stored["pictures"]])
        for a, b in zip(made["pictures"], stored["pictures"]):
            self.assertEqual(a["stage"], b["stage"])
            close(self, a["rgb"], b["rgb"], 2e-6, f"picture at {a['t']}")

    def test_the_moments_cover_every_stage(self):
        stored = json.loads((FIXTURES / "compose-small.json").read_text(encoding="utf-8"))
        self.assertEqual(sorted({p["stage"] for p in stored["pictures"]}), [-1, 0, 1, 2, 3, 4, 5, 6])


if __name__ == "__main__":
    if "--write-goldens" in sys.argv:
        write_json(FIXTURES / "layers-small.json", layers_golden())
        write_json(FIXTURES / "compose-small.json", compose_golden())
    else:
        unittest.main()
