"""The screenshot upload's guard against a stale slides branch (ci/store_screenshots_upload.py:
plan, refused_replacements; painting-company row 318), against a fake App Store Connect.

    python3 tools/tests/test_store_screenshots_guard.py   (needs `cryptography`, as the script does)
"""

import hashlib
import sys
import tempfile

import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ci"))
import store_screenshots_upload as upload  # noqa: E402


class FakeClient:
    def __init__(self, sets):
        self.sets = sets  # {set id: [md5, …]}

    def call(self, method, path, body=None, query=None):
        set_id = path.split("/")[2]
        return {"data": [{"attributes": {"sourceFileChecksum": md5,
                                         "assetDeliveryState": {"state": "COMPLETE"}}}
                         for md5 in self.sets[set_id]]}


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.files = []
        for n in (1, 2):
            path = self.dir / f"{n}.png"
            path.write_bytes(f"slide {n}".encode())
            self.files.append(path)
        self.md5s = [hashlib.md5(p.read_bytes()).hexdigest() for p in self.files]

    def test_plans_each_set(self):
        client = FakeClient({"same": self.md5s, "other": ["a", "b", "c"]})
        sets = {"APP_IPHONE_61": {"id": "same"}, "APP_IPAD_PRO_3GEN_129": {"id": "other"}}
        found = {"APP_IPHONE_61": self.files, "APP_IPAD_PRO_3GEN_129": self.files,
                 "APP_IPHONE_67": self.files, "PRODUCT_PAGE_HEADER_ASSET": self.files[:1]}
        plans, counts = upload.plan(client, sets, found)
        self.assertEqual(plans, {"APP_IPHONE_61": "unchanged", "APP_IPAD_PRO_3GEN_129": "differs",
                                 "APP_IPHONE_67": "new"})
        self.assertEqual(counts, {"APP_IPHONE_61": 2, "APP_IPAD_PRO_3GEN_129": 3})

    def test_a_different_set_is_held_unless_named(self):
        plans = {"APP_IPHONE_61": "differs", "APP_IPAD_PRO_3GEN_129": "differs",
                 "IMESSAGE_APP_IPHONE_67": "new", "APP_IPHONE_67": "unchanged"}
        self.assertEqual(upload.refused_replacements(plans, set()),
                         ["APP_IPAD_PRO_3GEN_129", "APP_IPHONE_61"])
        self.assertEqual(upload.refused_replacements(plans, {"APP_IPHONE_61"}), ["APP_IPAD_PRO_3GEN_129"])
        self.assertEqual(upload.refused_replacements(plans, {"all"}), [])


if __name__ == "__main__":
    unittest.main()
