"""SplitMix64's pinned draws and the show's random streams (tools/factory/making_of_pets.py).

    python3 -m unittest discover -s tools/tests -p 'test_making_of_pets.py'

Needs numpy. Sources/MakingOf's SplitMixTests pin the same draws. The crew planner itself is
exercised through the fixtures it made (test_making_of_inputs.py, test_making_of_reveal.py)."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "factory"))
import making_of_pets as pets


class SplitMixTests(unittest.TestCase):
    def test_published_seed_zero_outputs(self):
        rng = pets.SplitMix64(0)
        self.assertEqual([rng.next() for _ in range(3)],
                         [0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F])

    def test_first_doubles_of_seed_one(self):
        rng = pets.SplitMix64(1)
        self.assertEqual([rng.random() for _ in range(5)],
                         [0.5665615751722809, 0.7457817572627011, 0.9710027535867962, 0.4443592170557721,
                          0.44426470082635805])

    def test_uniform_scales_a_double(self):
        rng = pets.SplitMix64(1)
        self.assertEqual([rng.uniform(0.6, 0.95) for _ in range(3)],
                         [0.7982965513102983, 0.8610236150419454, 0.9398509637553787])

    def test_bounded_draws_and_choice(self):
        rng = pets.SplitMix64(1)
        self.assertEqual([rng.below(10) for _ in range(8)], [5, 9, 0, 5, 1, 8, 5, 3])
        rng = pets.SplitMix64(1)
        self.assertEqual([rng.choice([-1, 1]) for _ in range(8)], [1, 1, -1, 1, 1, -1, 1, 1])

    def test_permutations_shuffle_from_the_back(self):
        self.assertEqual(pets.SplitMix64(1).permutation(8), [4, 3, 2, 7, 5, 6, 0, 1])
        self.assertEqual(pets.SplitMix64(2).permutation(3), [2, 0, 1])
        self.assertEqual(pets.SplitMix64(3).permutation(1), [0])
        self.assertEqual(pets.SplitMix64(3).permutation(0), [])


class StreamTests(unittest.TestCase):
    def test_each_purpose_has_its_own_stream(self):
        pins = [
            (pets.STREAM_HOMES, 0, [0.7824150874829743, 0.024802976027635926, 0.8992068202961797]),
            (pets.STREAM_SPOTS, 5, [0.6750960295029587, 0.04260565902968305, 0.2721234946036929]),
            (pets.STREAM_NOISE, 11, [0.07621336553267122, 0.8016695796850121, 0.6890799999388426]),
            (pets.STREAM_SEEDS, 0, [0.5056482214915431, 0.5501754934418699, 0.13723743402324384]),
            (pets.STREAM_STROKES, 332, [0.9854077396862709, 0.22682682046334635, 0.8518463187733157]),
        ]
        for purpose, index, doubles in pins:
            rng = pets.stream(7, purpose, index)
            self.assertEqual([rng.random() for _ in range(3)], doubles, (purpose, index))


if __name__ == "__main__":
    unittest.main()
