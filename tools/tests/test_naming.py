"""The naming graph (tools/naming.py) on a small made-up repository.

    python3 -m unittest discover -s tools/tests -p 'test_naming.py'

Needs ripgrep (`rg`) and nothing else.
"""

import io
import json
import os
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import naming

SWIFT = '''\
/// One region of the picture, painted in one paint.
struct Region {
    var regionCount: Int
    let cells: [Int]  // a grid cell, not a region
    func paint() {
        let message = "Every region is painted."
        let rgn = 1
    }
}

/* A block comment about a region
   that runs on. */
extension Region {
    func aCellEdgeDividesARegionAndKeepsItsPaint() {}
}
'''

PYTHON = '''\
"""The regions, in a docstring."""

def regional(x):
    return x  # no hit: regional is another word
'''


def run(root, *argv):
    out = io.StringIO()
    with redirect_stdout(out), redirect_stderr(out):
        code = naming.main(list(argv), root=root)
    return code, out.getvalue()


@unittest.skipUnless(shutil.which("rg"), "needs ripgrep")
class NamingTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.root, "Sources"))
        Path(self.root, "Sources", "Region.swift").write_text(SWIFT)
        Path(self.root, "Sources", "tool.py").write_text(PYTHON)

    def tearDown(self):
        shutil.rmtree(self.root)

    def write(self, payload):
        path = os.path.join(self.root, "senses.json")
        Path(path).write_text(json.dumps(payload))
        return path

    def test_words_fold_case_plurals_and_abbreviations(self):
        self.assertEqual(naming.words_of("DetailAreas"), ["detail", "area"])
        self.assertEqual(naming.words_of("region_ids"), ["region", "id"])
        self.assertEqual(naming.words_of("regionIDsByColor"), ["region", "id", "by", "color"])
        self.assertEqual(naming.words_of("rgn"), ["region"])
        self.assertEqual(naming.words_of("cellSegs"), ["cell", "segment"])
        self.assertEqual(naming.words_of("indices"), ["index"])
        self.assertEqual(naming.words_of("canvases"), ["canvas"])
        self.assertIn("detail_areas", naming.spellings(["detail", "area"]))
        self.assertIn("rgnId", naming.spellings(["region", "id"]))

    def test_a_term_matches_whole_parts_only(self):
        self.assertTrue(naming.contains(naming.parts("RegionSimplifier"), ["region"]))
        self.assertFalse(naming.contains(naming.parts("regional"), ["region"]))
        self.assertFalse(naming.contains(naming.parts("cancelled"), ["cell"]))

    def test_hits_know_declarations_uses_prose_and_strings(self):
        search = naming.Search(self.root, "region", {})
        kinds = {(h.line, h.kind, h.ident) for h in search.hits if h.file.endswith(".swift")}
        self.assertIn((2, "decl", "Region"), kinds)
        self.assertIn((3, "decl", "regionCount"), kinds)
        self.assertIn((1, "comment", None), kinds)
        self.assertIn((4, "comment", None), kinds)
        self.assertIn((6, "string", None), kinds)
        self.assertIn((7, "decl", "rgn"), kinds)
        self.assertIn((11, "comment", None), kinds)
        self.assertIn((13, "use", "Region"), kinds, "an extension declares nothing")
        self.assertIn((14, "comment", None), kinds, "a sentence-long name reads as prose")
        python = {(h.line, h.kind) for h in search.hits if h.file.endswith(".py")}
        self.assertEqual(python, {(1, "comment")}, "the docstring, and not `regional`")
        symbols = {h.line: h.symbol for h in search.hits if h.file.endswith(".swift")}
        self.assertEqual(symbols[3], "Region")
        self.assertEqual(symbols[7], "Region.paint")

    def test_record_report_and_freshness(self):
        senses = {"term": "region", "senses": [
            {"slug": "area", "definition": "One area of the picture, painted in one paint.",
             "identifiers": ["Region", "region*", "rgn"], "prose": True, "strings": True}]}
        code, out = run(self.root, "record", self.write(senses))
        self.assertEqual(code, 0, out)
        graph = naming.Graph(self.root)
        self.assertEqual([s["id"] for s in graph.senses("region")], ["sense:region/area"])
        self.assertTrue(graph.edges(src="sense:region/area", type_="used_in"))
        code, out = run(self.root, "look", "Region")
        self.assertIn("from the graph", out)
        code, out = run(self.root, "report", "one area", "Region", "--also", "patch")
        self.assertIn("| `region/area` | One area of the picture", out)
        self.assertIn("| patch | unused |", out)
        # Twenty new lines are more than the tolerance: the term goes stale.
        Path(self.root, "Sources", "More.swift").write_text("let region = 0\n" * 20)
        code, out = run(self.root, "look", "Region")
        self.assertIn("STALE", out)

    def test_record_rejects_bad_slugs_and_unknown_aliases(self):
        bad = {"term": "region", "senses": [{"slug": "Not A Slug", "definition": "x", "identifiers": []}]}
        self.assertEqual(run(self.root, "record", self.write(bad))[0], 2)
        alias = {"term": "region", "senses": [{"slug": "area", "definition": "x", "identifiers": ["Region"]}],
                 "aliases": [["region/area", "cell/nothing"]]}
        self.assertEqual(run(self.root, "record", self.write(alias))[0], 2)

    def test_decide_writes_the_glossary_and_drift_finds_new_banned_names(self):
        senses = {"term": "region", "senses": [
            {"slug": "area", "definition": "One area of the picture.", "identifiers": ["Region"]}]}
        run(self.root, "record", self.write(senses))
        code, out = run(self.root, "decide", "Region", "--sense", "region/area", "--meaning",
                        "One area of the picture, painted in one paint.", "--banned", "patch,blob",
                        "--reason", "The pipeline's word.")
        self.assertEqual(code, 0, out)
        glossary = Path(self.root, "GLOSSARY.md").read_text()
        self.assertIn("| **Region** | One area of the picture, painted in one paint. | patch, blob |", glossary)
        self.assertEqual(run(self.root, "drift", "--strict")[0], 0)
        Path(self.root, "Sources", "Patch.swift").write_text("struct PatchMap {}\n")
        code, out = run(self.root, "drift", "--strict")
        self.assertEqual(code, 1)
        self.assertIn("`PatchMap` uses banned patch", out)
        code, out = run(self.root, "report", "one area", "Area", "--also", "patch")
        self.assertIn("## Decisions already made", out)

    def test_a_union_merge_keeps_the_later_record(self):
        os.makedirs(os.path.join(self.root, "tools", "naming"))
        old = {"node": "term:x", "type": "term", "name": "x", "data": {"lines": 1}, "at": "2026-10-24T10:00:00Z"}
        new = dict(old, data={"lines": 2}, at="2026-10-24T11:00:00Z")
        Path(self.root, naming.GRAPH).write_text(json.dumps(new) + "\n" + json.dumps(old) + "\n")
        self.assertEqual(naming.Graph(self.root).node("term:x")["data"], {"lines": 2})


if __name__ == "__main__":
    unittest.main()
