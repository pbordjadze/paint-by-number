"""Taste-loop acceptance tests: pytest tools/factory/test_taste.py.

Also runnable without third-party dependencies:
python3 -m unittest discover -s tools/factory -p test_taste.py
"""
import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from factory.taste import loop, transcripts
from factory.taste.pieces import color_names, panel_name


class TasteTests(unittest.TestCase):
    def setUp(self):
        # All temporary files, including rendered test artifacts, stay outside the repo.
        self.temp = tempfile.TemporaryDirectory(prefix="taste-test-")
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.gs = [
            {"id": "originality", "name": "Originality", "active": True, "vetoOnly": True,
             "charter_text": "- **guards against**: franchise look-alikes; harmful caricature."},
            *[{"id": f"g{i}", "name": f"Guardian {i}", "active": True, "baseWeight": 1,
               "charter_text": "- **guards against**: clutter; cold robots.\n- **Georgian thread**: supra."}
              for i in range(10)]]
        self.rules = {"version": 2, "guardians": self.gs, "originalityFreeVeto": False, "calibration": {}}

    def quiet(self, function, *args):
        with contextlib.redirect_stdout(io.StringIO()):
            return function(*args)

    def test_panel_run_replays_all_files_and_ledger_bytes(self):
        src = loop.REPO / "factory/pieces/panel-name"
        dest = self.folder / "panel"
        shutil.copytree(src, dest)
        (dest / "ledger.json").unlink()
        (dest / "champion.json").unlink()
        # Decisions must be rebuilt, not mistaken for freshly reproduced output.
        for n in range(1, 4):
            (dest / f"rounds/{n:03}/decision.json").unlink()
        with patch.object(panel_name, "RUN", str(dest)), patch.object(loop, "guardians", side_effect=AssertionError("live panel used")):
            for n in range(1, 4):
                self.quiet(panel_name.draw, n)
                self.quiet(panel_name.collect, n)
                self.quiet(panel_name.decide, n)
                round_dir = Path(f"rounds/{n:03}")
                for path in [round_dir / "draw.json", round_dir / "slate.json", round_dir / "decision.json",
                             *[p.relative_to(src) for p in (src / round_dir / "ballots").glob("*.json")]]:
                    self.assertEqual((dest / path).read_bytes(), (src / path).read_bytes(), str(path))
            self.assertEqual((dest / "ledger.json").read_bytes(), (src / "ledger.json").read_bytes())
            self.assertEqual((dest / "champion.json").read_bytes(), (src / "champion.json").read_bytes())
            before = (dest / "ledger.json").read_bytes()
            self.quiet(panel_name.decide, 3)
            self.assertEqual(before, (dest / "ledger.json").read_bytes())

    def test_color_run_replays_slots_ballots_decision_and_ledger_bytes(self):
        src = loop.REPO / "factory/pieces/color-names/run"
        dest = self.folder / "colors"
        shutil.copytree(src, dest)
        for name in ("slots.json", "decision.json", "ledger.json", "caps.json", "rejected.json"):
            (dest / name).unlink()
        with patch.object(color_names, "RUN", str(dest)), patch.object(color_names, "current_vocabulary", side_effect=AssertionError("live table used")):
            for function in (color_names.setup, color_names.collect, color_names.judges, color_names.decide):
                self.quiet(function)
            for path in [Path(n) for n in ("slots.json", "decision.json", "ledger.json", "caps.json", "rejected.json")] + [
                    p.relative_to(src) for folder in ("ballots", "juries") for p in (src / folder).glob("*.json")]:
                self.assertEqual((dest / path).read_bytes(), (src / path).read_bytes(), str(path))
            before = (dest / "ledger.json").read_bytes()
            self.quiet(color_names.decide)
            self.assertEqual(before, (dest / "ledger.json").read_bytes())

    def test_draw_is_seeded_disjoint_and_includes_originality(self):
        led = {"rounds": []}
        a = loop.draw(self.gs, led, "seed")
        self.assertEqual(a, loop.draw(self.gs, led, "seed"))
        self.assertEqual(len(a["jury"]), 6)
        self.assertEqual(len(a["proposers"]), 4)
        self.assertIn("originality", a["jury"])
        self.assertFalse(set(a["jury"]) & set(a["proposers"]))
        self.assertNotEqual(a, loop.draw(self.gs, led, "different"))

    def test_draw_prioritizes_unrepresented_then_those_who_sat_out(self):
        led = {"rounds": [{"represented": ["g0"]}]}
        d = loop.draw(self.gs, led, "seed", jury_size=3, proposers=0, recent=[f"g{i}" for i in range(1, 9)])
        self.assertEqual(d["jury"][1], "g9")
        self.assertNotIn("g0", d["jury"])

    def test_draw_excludes_inactive_and_rejects_too_small_a_panel(self):
        self.gs[-1]["active"] = False
        self.assertNotIn("g9", loop.draw(self.gs, {"rounds": []}, "x")["jury"])
        with self.assertRaises(ValueError):
            loop.draw(self.gs[:3], {"rounds": []}, "x")

    def test_alias_retains_representation_boost(self):
        g = {"id": "robber-girl", "aliases": ["nina"], "baseWeight": 2}
        gs = loop.seats({"guardians": [g]})
        led = {"rounds": [{"represented": ["nina"]}]}
        self.assertEqual(loop.weight(g, led, gs=gs), 2)
        self.assertEqual(gs["nina"]["id"], "robber-girl")

    def test_current_panel_renames_seat_and_retains_alias(self):
        gs = loop.seats({"guardians": loop.guardians()})
        self.assertEqual(gs["nina"]["id"], "robber-girl")
        self.assertEqual(gs["robber-girl"]["name"], "The Robber Girl")

    def test_draw_resolves_legacy_aliases_in_the_ledger(self):
        self.gs[1].update(id="robber-girl", aliases=["nina"])
        led = {"rounds": [{"represented": ["nina"]}]}
        d = loop.draw(self.gs, led, "aliases", jury_size=11, proposers=0)
        self.assertEqual(d["weights"]["robber-girl"], 1)
        self.assertEqual(d["weights"]["g1"], 1.5)

    def test_ballots_are_per_juror_seeded_permutations(self):
        names = ["One", "Two", "Three", "Four", "Five"]
        a = loop.ballot(names, "juror-a")
        self.assertEqual(a, loop.ballot(names, "juror-a"))
        self.assertCountEqual(a.values(), names)
        self.assertNotEqual(a, loop.ballot(names, "juror-b"))

    def tally(self, verdict, *, version=2, gid="g0"):
        record = {**self.rules, "version": version}
        return loop.score(["One", "Two", "Three"], [gid], {gid: {"A": "One", "B": "Two", "C": "Three"}},
                          {gid: verdict}, record)

    def test_borda_multiplies_base_boost_and_calibration(self):
        self.gs[1]["baseWeight"] = 2
        self.rules["calibration"] = {"g0": 0.5}
        led = {"rounds": [{"represented": []}, {"represented": []}, {"represented": []}]}
        result = loop.score(["One", "Two", "Three"], ["g0"], {"g0": {"A": "One", "B": "Two", "C": "Three"}},
                            {"g0": {"ranking": ["C", "A", "B"]}}, self.rules, ledger=led)
        self.assertEqual(result["score"], {"One": 2.0, "Two": 0.0, "Three": 4.0})
        self.assertEqual(result["firsts"]["Three"], 1)

    def test_frozen_draw_weights_are_used_once(self):
        result = loop.score(["One", "Two"], ["g0"], {"g0": {"A": "One", "B": "Two"}},
                            {"g0": {"ranking": ["A", "B"]}}, self.rules, weights={"g0": 3})
        self.assertEqual(result["score"]["One"], 3)

    def test_originality_never_scores_even_with_a_ranking(self):
        result = self.tally({"ranking": ["A", "B", "C"]}, gid="originality")
        self.assertFalse(any(result["score"].values()))
        self.assertFalse(any(result["firsts"].values()))

    def test_incomplete_ranking_is_reported_and_filled_deterministically(self):
        result = self.tally({"ranking": ["C", "C", "Z"]})
        self.assertEqual(result["score"], {"One": 1.0, "Two": 0.0, "Three": 2.0})
        self.assertEqual(len(result["problems"]), 1)

    def test_missing_verdict_is_reported(self):
        result = self.tally(None)
        self.assertEqual(result["problems"], ["g0: no verdict"])

    def test_v1_accepts_reason_but_v2_requires_guards_quote(self):
        verdict = {"candidates": {"A": {"veto": "not my taste"}}}
        self.assertTrue(self.tally(verdict, version=1)["vetoes"]["One"])
        self.assertFalse(self.tally(verdict)["vetoes"]["One"])
        self.assertTrue(self.tally(verdict)["ignored"])
        verdict["candidates"]["A"]["veto"] = '"Cold robots."'
        self.assertTrue(self.tally(verdict)["vetoes"]["One"])

    def test_georgian_thread_is_not_a_veto_quote(self):
        result = self.tally({"candidates": {"A": {"veto": "supra"}}})
        self.assertFalse(result["vetoes"]["One"])

    def test_new_originality_must_also_quote_its_guard(self):
        result = self.tally({"candidates": {"A": {"veto": "bad"}}}, gid="originality")
        self.assertFalse(result["vetoes"]["One"])
        result = self.tally({"candidates": {"A": {"veto": "harmful caricature"}}}, gid="originality")
        self.assertTrue(result["vetoes"]["One"])

    def test_broad_favorite_and_most_loved_can_differ(self):
        result = loop.favorites([{"name": "Broad", "score": 20, "firsts": 1, "vetoes": []},
                                 {"name": "Loved", "score": 18, "firsts": 3, "vetoes": []},
                                 {"name": "Blocked", "score": 99, "firsts": 9, "vetoes": ["no"]}])
        self.assertEqual(result, {"broad_favorite": "Broad", "most_loved": "Loved"})

    def result(self, slot, owner, choices):
        # choices: (name, source, score, vetoes)
        standings = [dict(zip(("name", "source", "score", "vetoes"), c)) for c in choices]
        return {"slot": slot, "owner": owner, "winner": standings[0]["name"],
                "winner_source": standings[0]["source"], "standings": standings, "guaranteed": False}

    def select(self, results, *, base=None, caps=None, guarantee=False):
        return loop.select(results, base or {}, {r["slot"]: r["slot"] for r in results},
                           caps or panel_name.PanelCaps({"sharedBar": False}),
                           owners=list(dict.fromkeys(r["owner"] for r in results)), guarantee=guarantee)

    def test_uniqueness_keeps_duplicate_where_it_scored_higher(self):
        a = self.result(1, "g0", [("Shared", "writer", 10, []), ("First", "incumbent", 5, [])])
        b = self.result(2, "g1", [("Shared", "writer", 20, []), ("Second", "incumbent", 5, [])])
        self.select([a, b])
        self.assertEqual((a["winner"], b["winner"]), ("First", "Shared"))

    def test_name_cannot_duplicate_an_unedited_anchor(self):
        a = self.result(1, "g0", [("Taken", "writer", 10, []), ("First", "incumbent", 5, [])])
        self.select([a], base={99: "Taken"})
        self.assertEqual(a["winner"], "First")

    def test_caps_hook_replaces_lowest_scoring_new_name(self):
        caps = color_names.NameCaps({"sharedBar": False})
        a = self.result(1, "g0", [("Quiet Garden", "writer", 10, []), ("First", "incumbent", 5, [])])
        base = {i + 10: f"Quiet {word}" for i, word in enumerate(("Window", "Room", "Harbor", "Gate"))}
        self.select([a], base=base, caps=caps)
        self.assertEqual(a["winner"], "First")

    def test_style_guide_counts_leads_and_trails_only_for_two_words(self):
        caps = color_names.NameCaps({"sharedBar": False})
        self.assertEqual(caps({i: f"Quiet {i}" for i in range(5)}), [("lead", "Quiet")])
        self.assertEqual(caps({i: f"{i} Room" for i in range(7)}), [("trail", "Room")])
        self.assertFalse(caps({i: "Quiet" for i in range(9)}))

    def test_guarantee_runs_after_caps_and_uniqueness(self):
        caps = color_names.NameCaps({"sharedBar": False})
        a = self.result(1, "g0", [("First", "writer", 20, []), ("Quiet Garden", "g0", 18, []),
                                   ("Own", "g0", 16, [])])
        b = self.result(2, "g1", [("Second", "g1", 20, [])])
        base = {i + 10: f"Quiet {word}" for i, word in enumerate(("Window", "Room", "Harbor", "Gate"))}
        self.select([a, b], base=base, caps=caps, guarantee=True)
        self.assertEqual(a["winner"], "Own")
        self.assertTrue(a["guaranteed"])

    def test_guarantee_is_optional_and_never_overrides_a_veto(self):
        a = self.result(1, "g0", [("First", "writer", 20, []), ("Own", "g0", 18, ["no"])])
        self.select([a])
        self.assertEqual(a["winner"], "First")
        with self.assertRaisesRegex(ValueError, "guaranteed"):
            self.select([a], guarantee=True)

    def test_guarantee_chooses_owners_smallest_score_gap(self):
        a = self.result(1, "g0", [("First", "writer", 20, []), ("Own", "g0", 10, [])])
        b = self.result(2, "g0", [("Second", "writer", 20, []), ("Other", "g0", 18, [])])
        self.select([a, b], guarantee=True)
        self.assertEqual((a["winner"], b["winner"]), ("First", "Other"))

    def test_interacting_caps_can_require_two_changes_at_once(self):
        caps = color_names.NameCaps({"sharedBar": False})
        a = self.result(1, "g0", [("Quiet Garden", "writer", 20, []), ("First", "incumbent", 10, [])])
        b = self.result(2, "g1", [("Inside Room", "writer", 20, []), ("Second", "incumbent", 10, [])])
        base = {i + 10: f"Quiet {word}" for i, word in enumerate(("Window", "Harbor", "Gate", "Hearth"))}
        base.update({i + 20: f"{word} Room" for i, word in enumerate(("Apple", "Attic", "Old", "High", "Low", "Bright"))})
        self.select([a, b], base=base, caps=caps)
        self.assertEqual((a["winner"], b["winner"]), ("First", "Second"))

    def test_guarantee_can_move_another_owners_winner_without_losing_representation(self):
        a = self.result(1, "g0", [("First", "writer", 20, []), ("Shared", "g0", 18, [])])
        b = self.result(2, "g1", [("Shared", "g1", 20, []), ("Other", "g1", 18, [])])
        self.select([a, b], guarantee=True)
        self.assertEqual((a["winner"], b["winner"]), ("Shared", "Other"))

    def test_unsatisfied_uniqueness_or_vetoes_are_errors(self):
        a = self.result(1, "g0", [("Taken", "writer", 20, [])])
        with self.assertRaisesRegex(ValueError, "duplicates"):
            self.select([a], base={99: "Taken"})
        a["standings"][0]["vetoes"] = ["no"]
        with self.assertRaisesRegex(ValueError, "unvetoed"):
            self.select([a])

    def test_georgian_caps_use_whole_names_and_whole_terms(self):
        glossary = loop.load(loop.REPO / "factory/taste/glossary.json")
        table = {i: f"Ordinary {i}" for i in range(100)}
        table[0], table[1] = "Tbilisi Stone", "Under Narikala"
        table[2], table[3], table[4] = "Supra Table", "Qvevri Clay", "Tonir Hearth"
        self.assertFalse(loop.georgian_caps(table, glossary))
        table[5] = "Vani Hoard"
        self.assertIn(("places", "Georgian places"), loop.georgian_caps(table, glossary))
        table[6] = "Iavnana"
        self.assertIn(("words", "Georgian words"), loop.georgian_caps(table, glossary))
        self.assertFalse(loop.georgian_caps({i: "Stone" for i in range(100)}, glossary))

    def test_new_panel_selection_filters_georgian_name(self):
        caps = panel_name.PanelCaps({"sharedBar": True, "glossary": loop.load(loop.REPO / "factory/taste/glossary.json")})
        a = self.result(1, "g0", [("Supra", "g0", 20, []), ("Lamp", "g0", 10, [])])
        self.select([a], caps=caps)
        self.assertEqual(a["winner"], "Lamp")

    def test_rule_snapshot_ignores_changed_panel_and_rejects_unknown_version(self):
        first = loop.rules(self.folder, "panel-name")
        with patch.object(loop, "guardians", side_effect=AssertionError("live panel used")):
            self.assertEqual(first, loop.rules(self.folder, "panel-name"))
        with self.assertRaises(ValueError):
            loop.rules(self.folder, "color-names")
        first["version"] = 99
        loop.save(self.folder / "rules.json", first)
        with self.assertRaises(ValueError):
            loop.rules(self.folder, "panel-name")

    def test_second_jury_is_separate_and_blind(self):
        d = loop.second_jury(self.folder, ["First", "Second", "Third"], self.gs, {"rounds": []})
        self.assertEqual(len(d["jury"]), 6)
        for gid in d["jury"]:
            self.assertCountEqual(loop.load(self.folder / "finalists/ballots" / f"{gid}.json").values(),
                                  ["First", "Second", "Third"])
        self.assertFalse((self.folder / "decision.json").exists())

    def test_proposer_history_records_reception_and_alias(self):
        dec = {"round": 1, "winner": "Lamp", "standings": [
            {"name": "Lamp", "origin": "nina", "source": "carried", "score": 12, "firsts": 2, "vetoed": []}]}
        loop.save(self.folder / "rounds/001/decision.json", dec)
        gs = loop.seats({"guardians": [{"id": "robber-girl", "aliases": ["nina"]}]})
        text = loop.history(self.folder, "robber-girl", gs)
        self.assertIn("Lamp — 12 points, 2 first places; won", text)

    def test_originality_prompts_include_glossary_and_proposers_see_history(self):
        src = loop.REPO / "factory/pieces/panel-name"
        dest = self.folder / "panel"
        shutil.copytree(src, dest)
        with patch.object(panel_name, "RUN", str(dest)):
            self.quiet(panel_name.proposals, 3)
            self.quiet(panel_name.collect, 3)
        jury_prompt = (dest / "rounds/003/prompts/judge-originality.txt").read_text()
        self.assertIn("qvevri", jury_prompt)
        self.assertIn("supra", jury_prompt)
        self.assertIn("felt, not named", jury_prompt)
        prompt = (dest / "rounds/003/prompts/propose-painter.txt").read_text()
        self.assertIn("Your past names", prompt)
        self.assertIn("Courtyard Lanterns", prompt)

    def test_fresh_legacy_piece_prompts_use_current_charters_and_optional_caps(self):
        panel = self.folder / 'new-panel'
        with patch.object(panel_name, 'RUN', str(panel)):
            self.quiet(panel_name.draw, 1)
            self.quiet(panel_name.proposals, 1)
        colors = self.folder / 'new-colors'
        with patch.object(color_names, 'RUN', str(colors)):
            self.quiet(color_names.setup)
            self.quiet(color_names.prompts)
        for folder in (panel, colors):
            self.assertFalse(loop.load(folder / 'rules.json')['sharedBar'])
            prompts = list(folder.rglob('*.txt'))
            self.assertTrue(prompts)
            for path in prompts:
                self.assertNotIn('Georgian thread', path.read_text())
                self.assertNotIn('one name in fifty', path.read_text())

    def test_piece_craft_and_rendering(self):
        self.assertFalse(panel_name.craft("A Lamp", {})[0])
        self.assertIn("duplicate", panel_name.craft("The Lamp", {"lamp": True})[0])
        slot = {"slot": 12, "incumbent": "Harbor Fog", "describe": "dark grayish blue"}
        self.assertFalse(color_names.craft("Harbor Fog", slot, {"harbor fog"}))
        self.assertIn("no color words", color_names.craft("Blue Fog", slot, set()))
        self.assertIn("a forbidden word", color_names.craft("Grave Blood", slot, set()))
        self.assertIn("12 · Harbor Fog", color_names.in_context("Harbor Fog", slot))


class TranscriptTests(unittest.TestCase):
    def test_reads_last_handback_not_intermediate_assistant_text(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "agent.output"
            def handback(text):
                return {"message": {"role": "assistant", "content": [{"type": "tool_use", "name": "SubagentHandback", "input": {"message": text}}]}}
            lines = [handback('{"old": true}'), handback('```json\n{"names": {"1": "Lamp"}}\n```'),
                     {"message": {"role": "assistant", "content": [{"type": "text", "text": "done"}]}}]
            path.write_text("\n".join(json.dumps(line) for line in lines))
            self.assertEqual(transcripts.extract(path), {"names": {"1": "Lamp"}})

    def test_invalid_or_missing_handback_preserves_raw_reply(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "agent.output"
            path.write_text(json.dumps({"message": {"role": "assistant", "content": [{"type": "tool_use",
                            "name": "SubagentHandback", "input": {"message": "done"}}]}}))
            self.assertEqual(transcripts.extract(path)["raw"], "done")
            path.write_text("{}\n")
            self.assertIn("error", transcripts.extract(path))


if __name__ == "__main__":
    unittest.main()
