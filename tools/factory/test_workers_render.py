"""Version 2 review choices; the real workers render verifies SVG backgrounds and actor trails."""
import unittest

import render


class WorkerReviewTests(unittest.TestCase):
    def test_work_moments_cover_start_middle_finish_and_tail(self):
        manifest = {"fps": 24, "frameCount": 150, "duration": 6.25,
                    "actions": [{"actor": "a", "kind": "ink", "start": 0, "end": 4},
                                {"actor": "b", "kind": "sweep", "start": 0, "end": 5}]}
        self.assertEqual(render.key_frames(manifest, {}),
                         [("start-ink", 0), ("mid-ink", 48), ("end-ink", 96), ("settled", 149)])
        manifest["actions"][0]["kind"] = "sweep"
        self.assertEqual(render.key_frames(manifest, {})[1], ("mid-sweep", 48))


if __name__ == "__main__":
    unittest.main()
