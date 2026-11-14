"""The making-of show's SplitMix64, its random streams, and the easing and the polyline lengths the
shared modules use. The crew show this module planned (its guardians' walks, the jobs it handed out,
the lines it drew by walking) left this repository in two steps: its sprites and its player with the
Marginarium, and its planner once nothing replayed the visits and walked lines it made
(painting-company row 110). The app plays the show with no crew, making_of_fields.py.
"""

import numpy as np


class SplitMix64:
    """PaintCore's SplitMix64 (Sources/PaintCore/Foundation/SplitMix64.swift) in 64-bit wrapping
    arithmetic, with the draws the show needs. Sources/MakingOf has the same ones; keep them equal
    (both test suites pin the first doubles of seed 1)."""

    MASK = (1 << 64) - 1

    def __init__(self, seed):
        self.state = seed & self.MASK

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & self.MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & self.MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & self.MASK
        return z ^ (z >> 31)

    def random(self):
        """A double in [0, 1)."""
        return (self.next() >> 11) * 2.0 ** -53

    def uniform(self, a, b):
        return a + (b - a) * self.random()

    def below(self, n):
        """An integer in [0, n)."""
        return self.next() % n

    def permutation(self, n):
        """0..<n shuffled (Fisher-Yates, from the back)."""
        out = list(range(n))
        for i in range(n - 1, 0, -1):
            j = self.below(i + 1)
            out[i], out[j] = out[j], out[i]
        return out


# The show's random draws, one stream per purpose, so a draw count in one (sample_stops retries)
# can never shift another. Sources/MakingOf/Streams.swift has the same; both suites pin them. The
# show draws from STREAM_SEEDS and from making_of_fields.STREAM_FIELDS on; the others were the crew
# show's, and keep their numbers so no later purpose takes one (the sampling tests still draw from them).
STREAM_HOMES, STREAM_SPOTS, STREAM_NOISE, STREAM_SEEDS, STREAM_STROKES = 1, 2, 3, 4, 5


def stream(seed, purpose, index):
    """The SplitMix64 for one purpose (STREAM_*) and index (a step, a stroke, a noise grid) of
    the show's seed: a generator seeded from the first draw of `seed ^ (purpose << 32 | index)`."""
    assert 0 <= index < 1 << 32
    return SplitMix64(SplitMix64(seed ^ (purpose << 32 | index)).next())


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def cumulative(pts):
    """Distance along a polyline up to each of its points."""
    d = np.diff(pts, axis=0)
    return np.concatenate(([0.0], np.cumsum(np.sqrt(d[:, 0] * d[:, 0] + d[:, 1] * d[:, 1]))))
