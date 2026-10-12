"""Marginarium importer tests; all output goes to temporary directories, never the app."""

from copy import deepcopy
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import marginarium as m
import strings_check

FIXTURE = Path(__file__).parent / "fixtures/marginarium.md"
TOOL = Path(m.__file__)
DOCS_FIXTURE = FIXTURE.with_name("marginarium-docs.json")
DOCS_MARKDOWN = FIXTURE.with_name("marginarium-docs.md")


class MarginariumTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="marginarium-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        m.write_json(self.root / m.CATALOG, {"sourceLanguage": "en", "strings": {}, "version": "1.0"})
        asset = self.root / m.ASSETS / "fixture-circle.imageset"
        m.write_json(asset / "Contents.json", {"images": [{"filename": "circle.png"}]})
        # Validation checks asset membership, not raster decoding; no test artwork ships.
        (asset / "circle.png").write_bytes(b"fixture")

    def imported(self, text=None, entry_id="fixture"):
        source = self.root / "input.md"
        source.write_text(text if text is not None else FIXTURE.read_text(), encoding="utf-8")
        return m.import_chapter(self.root, source, entry_id)

    def canonical(self, entry_id="fixture"):
        return self.root / m.SOURCES / f"{entry_id}.md"

    def reimport(self, entry_id="fixture"):
        return m.import_chapter(self.root, self.canonical(entry_id), entry_id)

    def catalog(self):
        return m.load_json(self.root / m.CATALOG)

    def test_fixture_covers_every_kind_and_inline_spelling(self):
        chapter = self.imported()
        manifest, values = m.validate(self.root)
        self.assertEqual(manifest["chapters"], [chapter])
        self.assertEqual({b["kind"] for b in chapter["blocks"]},
                         {"title", "subtitle", "heading", "paragraph", "quote", "bullet", "image"})
        expected = m.parse(FIXTURE.read_text())
        self.assertEqual([value for _, value in values], [b.text for b in expected])
        self.assertIn("\n\n", next(b.text for b in expected if b.kind == "quote"))
        self.assertEqual([b["depth"] for b in chapter["blocks"] if b["kind"] == "bullet"], [0, 1, 0])
        self.assertEqual(next(b["image"] for b in chapter["blocks"] if b["kind"] == "image"), "fixture-circle")
        for block in chapter["blocks"]:
            entry = self.catalog()["strings"][block["key"]]
            self.assertEqual(entry["extractionState"], "manual")
            self.assertIn("Fixture chapter", entry["comment"])
            self.assertIn(block["kind"], entry["comment"])
        findings = []
        usages = [strings_check.Usage(key, "fixture", 0, default=value, raw=True) for key, value in values]
        strings_check.check_catalog(self.catalog(), usages, findings)
        self.assertEqual(findings, [], [str(f) for f in findings])

    def test_pet_blocks_import_validate_and_keep_keys(self):
        # A test atlas is sufficient for membership validation; ImageIO decoding is tested in App.
        atlas = self.root / m.RESOURCES / "pet-fixture.webp"
        atlas.write_bytes(b"fixture")
        source = "# Title\n\nSubtitle.\n\n![A pet with 100% energy.](pet:fixture)\n\nAfter.\n"
        chapter = self.imported(source)
        pet = chapter["blocks"][2]
        self.assertEqual(pet["kind"], "pet")
        self.assertEqual(pet["pet"], "fixture")
        self.assertNotIn("image", pet)
        entry = self.catalog()["strings"][pet["key"]]
        self.assertEqual(m.english(entry), "A pet with 100% energy.")
        self.assertIn("pet description for VoiceOver", entry["comment"])
        self.assertEqual(self.imported(source), chapter)
        self.assertEqual(self.reimport(), chapter)
        m.validate(self.root)
        manifest = m.load_json(self.root / m.MANIFEST)
        manifest["chapters"][0]["blocks"][2]["pet"] = "wrong-pet"
        m.write_json(self.root / m.MANIFEST, manifest)
        with self.assertRaisesRegex(ValueError, "manifest differs"):
            m.validate(self.root)
        self.reimport()
        atlas.unlink()
        with self.assertRaisesRegex(ValueError, "pet fixture.*bundled"):
            m.validate(self.root)
        with self.assertRaisesRegex(ValueError, "pet fixture.*bundled"):
            self.imported(source)

    def test_both_imageset_pets_require_their_shipped_frames(self):
        for pet, rows in m.PET_IMAGESETS.items():
            source = f"# Title\n\nSubtitle.\n\n![Description](pet:{pet})\n"
            with self.subTest(pet=pet):
                with self.assertRaisesRegex(ValueError, "bundled image set"):
                    self.imported(source)
                for row, count in rows.items():
                    for index in range(count):
                        asset = self.root / m.ASSETS / f"{pet}-{row}-{index}.imageset"
                        m.write_json(asset / "Contents.json", {"images": [{"filename": "cell.png"}]})
                        (asset / "cell.png").write_bytes(b"fixture")
                self.imported(source)
                m.validate(self.root)
                (asset / "cell.png").unlink()
                with self.assertRaisesRegex(ValueError, "missing files"):
                    m.validate(self.root)

    def test_pet_syntax_rejects_missing_remote_inline_and_unsafe_names(self):
        for body in ("![Pet](pet:absent)", "![Pet](pet:)", "![Pet](pet:../pip)",
                     "![Pet](pet:pip.webp)", "![Pet](pet://pip)", "![Pet](pet:Pip)",
                     "![Pet](pet:pip?row=3)", "![](pet:pip)", "![*Pet*](pet:pip)",
                     "Text ![Pet](pet:pip)"):
            with self.subTest(body=body), self.assertRaises(ValueError):
                self.imported("# Title\n\nSubtitle.\n\n" + body)

    def test_reimport_is_byte_identical_with_or_without_markers(self):
        self.imported()
        paths = [self.root / m.MANIFEST, self.root / m.CATALOG, self.canonical()]
        before = [p.read_bytes() for p in paths]
        self.reimport()
        self.assertEqual(before, [p.read_bytes() for p in paths])
        self.imported()
        self.assertEqual(before, [p.read_bytes() for p in paths])

    def test_insertion_deletion_reorder_and_edit_keep_surviving_keys(self):
        original = self.imported("# Title\n\nSubtitle.\n\nFirst.\n\nSecond.\n\nThird.\n")
        path = self.canonical()
        path.write_text(path.read_text().replace("First.", "First.\n\nInserted paragraph."))
        inserted = self.reimport()
        self.assertEqual([b["key"] for b in original["blocks"]],
                         [b["key"] for b in inserted["blocks"] if b != inserted["blocks"][3]])
        removed_key = original["blocks"][3]["key"]
        text = path.read_text().replace(f"<!-- marginarium: {removed_key} -->\nSecond.\n", "")
        text = text.replace("First.", "Edited first.")
        last_key = original["blocks"][-1]["key"]
        last = f"<!-- marginarium: {last_key} -->\nThird."
        text = text.replace(last, "")
        # Move the last paragraph ahead of the first, retaining its marker.
        first_marker = f"<!-- marginarium: {original['blocks'][2]['key']} -->"
        path.write_text(text.replace(first_marker, last + "\n\n" + first_marker))
        changed = self.reimport()
        self.assertEqual({b["key"] for b in changed["blocks"]},
                         {b["key"] for b in inserted["blocks"]} - {removed_key})
        self.assertEqual(changed["blocks"][2]["key"], last_key)
        self.assertNotIn(removed_key, self.catalog()["strings"])
        self.assertEqual(m.english(self.catalog()["strings"][original["blocks"][2]["key"]]), "Edited first.")
        m.validate(self.root)

    def test_identical_paragraphs_keep_their_own_markers(self):
        original = self.imported("# Title\n\nSubtitle.\n\nSame.\n\nSame.\n")
        first, second = [b["key"] for b in original["blocks"][2:]]
        path = self.canonical()
        path.write_text(path.read_text().replace(f"<!-- marginarium: {first} -->\nSame.\n", ""))
        changed = self.reimport()
        self.assertEqual(changed["blocks"][-1]["key"], second)
        self.assertNotIn(first, self.catalog()["strings"])

    def test_ambiguous_unmarked_duplicates_fail_without_writes(self):
        self.imported("# Title\n\nSubtitle.\n\nSame.\n")
        paths = [self.root / m.MANIFEST, self.root / m.CATALOG, self.canonical()]
        before = [path.read_bytes() for path in paths]
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            self.imported("# Title\n\nSubtitle.\n\nSame.\n\nSame.\n")
        self.assertEqual(before, [path.read_bytes() for path in paths])
        # An inserted duplicate is safe when the original keeps its marker.
        path = self.canonical()
        path.write_text(path.read_text() + "\nSame.\n")
        self.reimport()
        before = [path.read_bytes() for path in paths]
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            self.imported("# Title\n\nSubtitle.\n\nSame.\n")
        self.assertEqual(before, [path.read_bytes() for path in paths])

    def test_legacy_catalog_is_preserved_including_multiline_passage(self):
        source = "# Legacy title\n\nLegacy subtitle.\n\n> First.\n>\n> Second.\n"
        blocks = m.parse(source)
        keys = [f"marginarium.fixture.{s}" for s in ("title", "subtitle", "passage")]
        catalog = self.catalog()
        for key, block in zip(keys, blocks):
            catalog["strings"][key] = {"comment": "Existing translator comment", "extractionState": "manual",
                                       "localizations": {"en": {"stringUnit": {"state": "translated", "value": block.text}}}}
        m.write_json(self.root / m.CATALOG, catalog, catalog=True)
        before = (self.root / m.CATALOG).read_bytes()
        marked = "\n\n".join(f"<!-- marginarium: {key} -->\n{part}" for key, part in
                               zip(keys, ("# Legacy title", "Legacy subtitle.", "> First.\n>\n> Second.")))
        self.imported(marked)
        self.assertEqual(before, (self.root / m.CATALOG).read_bytes())
        m.validate(self.root)
        with self.assertRaisesRegex(ValueError, "word for word"):
            self.imported(marked.replace("First.", "Changed."))
        self.assertEqual(before, (self.root / m.CATALOG).read_bytes())

    def test_checks_fail_for_text_structure_keys_images_and_missing_sources(self):
        self.imported()
        paths = [self.root / m.MANIFEST, self.root / m.CATALOG, self.canonical()]
        backups = {path: path.read_bytes() for path in paths}
        manifest = m.load_json(paths[0])
        catalog = self.catalog()
        mutations = []
        changed = deepcopy(catalog)
        changed["strings"][manifest["chapters"][0]["blocks"][0]["key"]]["localizations"]["en"]["stringUnit"]["value"] += "!"
        mutations.append((paths[1], changed))
        for field, value in (("kind", "future"), ("key", "absent"), ("level", 5), ("image", "missing"), ("depth", 3)):
            changed = deepcopy(manifest)
            block = next((b for b in changed["chapters"][0]["blocks"] if field in b), changed["chapters"][0]["blocks"][0])
            block[field] = value
            mutations.append((paths[0], changed))
        changed = deepcopy(manifest)
        changed["chapters"][0]["blocks"].reverse()
        mutations.append((paths[0], changed))
        changed = deepcopy(catalog)
        changed["strings"]["marginarium.fixture.block.stale"] = next(iter(changed["strings"].values()))
        mutations.append((paths[1], changed))
        for path, value in mutations:
            with self.subTest(value=value):
                m.write_json(path, value)
                with self.assertRaises(ValueError):
                    m.validate(self.root)
                path.write_bytes(backups[path])
        self.canonical().write_text(self.canonical().read_text().replace("last paragraph", "changed paragraph"))
        with self.assertRaisesRegex(ValueError, "English differs"):
            m.validate(self.root)
        self.canonical().unlink()
        with self.assertRaises(OSError):
            m.validate(self.root)
        self.canonical().write_bytes(backups[self.canonical()])
        (self.root / m.ASSETS / "fixture-circle.imageset/circle.png").unlink()
        with self.assertRaisesRegex(ValueError, "missing files"):
            m.validate(self.root)

    def test_translation_survives_reimport_and_edits_request_review(self):
        chapter = self.imported()
        key = chapter["blocks"][-1]["key"]
        catalog = self.catalog()
        translation = {"stringUnit": {"state": "translated", "value": "Der letzte Absatz."}}
        catalog["strings"][key]["localizations"]["de"] = translation
        m.write_json(self.root / m.CATALOG, catalog)
        self.reimport()
        self.assertEqual(self.catalog()["strings"][key]["localizations"]["de"], translation)
        path = self.canonical()
        path.write_text(path.read_text().replace("last paragraph", "revised paragraph"))
        self.reimport()
        self.assertEqual(self.catalog()["strings"][key]["localizations"]["de"]["stringUnit"]["state"], "needs_review")

    def test_bad_syntax_and_duplicate_or_foreign_keys_fail(self):
        for body in ("```swift\ncode\n```", "<div>HTML</div>", "1) Ordered", "![No image](https://example.org/a.png)",
                     "![](fixture-circle)", "---", "> ## Nested heading", "Text ![inline](fixture-circle)",
                     "<!-- marginarium: invalid -->\nParagraph.",
                     "<!-- marginarium: marginarium.other.block.x -->\nParagraph.",
                     "<!-- marginarium: marginarium.fixture.block.same -->\nA.\n\n"
                     "<!-- marginarium: marginarium.fixture.block.same -->\nB."):
            with self.subTest(body=body), self.assertRaises(ValueError):
                self.imported("# Title\n\nSubtitle.\n\n" + body)
        for source in ("No heading", "# Title\n\n## No subtitle", "# Title\n\nSubtitle.\n\n<!-- marginarium: dangling -->"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                m.parse(source)

    def test_import_keeps_other_chapters_and_check_cli_exits_nonzero_on_drift(self):
        first = self.imported()
        self.imported("# Second\n\nSubtitle.\n\nBody.\n", entry_id="second")
        self.assertEqual(m.load_json(self.root / m.MANIFEST)["chapters"][0], first)
        command = [sys.executable, "-B", str(TOOL), "--root", str(self.root), "check"]
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.canonical().write_text(self.canonical().read_text().replace("last paragraph", "changed paragraph"))
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("English differs", result.stderr)

    def test_cli_import_and_closed_atx_headings(self):
        result = subprocess.run([sys.executable, "-B", str(TOOL), "--root", str(self.root),
                                 "import", str(FIXTURE), "--id", "fixture"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        m.validate(self.root)
        blocks = m.parse("# Title #\n\nSubtitle.\n\n## Heading ##\n")
        self.assertEqual([b.text for b in blocks], ["Title", "Subtitle.", "Heading"])

    def test_strings_checker_reads_manifest_keys_and_reports_source_drift(self):
        self.imported()
        # A tiny repository isolates the runtime-key integration from the app's other strings.
        (self.root / strings_check.APP_SOURCES / "Reader.swift").write_text("import Foundation\n")
        m.write_json(self.root / strings_check.LIBRARY, [])
        m.write_json(self.root / strings_check.INFOPLIST_CATALOG,
                     {"sourceLanguage": "en", "strings": {}, "version": "1.0"})
        project = self.root / strings_check.PROJECT
        project.parent.mkdir(parents=True)
        project.write_text("")
        plist = self.root / strings_check.INFOPLIST_FILE
        plist.parent.mkdir(parents=True)
        plist.write_bytes(plistlib.dumps({}))
        findings, keys, used = strings_check.run(self.root)
        self.assertEqual(findings, [], [str(f) for f in findings])
        self.assertEqual(keys, used)
        self.canonical().write_text(self.canonical().read_text().replace("last paragraph", "changed paragraph"))
        findings, _, _ = strings_check.run(self.root)
        self.assertTrue(any("English differs" in str(f) for f in findings))

    def test_docs_conversion_preserves_words_markup_and_structure(self):
        source = m.from_docs(m.load_json(DOCS_FIXTURE))
        self.assertEqual(source, DOCS_MARKDOWN.read_text())
        chapter = self.imported(source)
        blocks = m.parse(self.canonical().read_text())
        self.assertEqual([b.text for b in blocks], [b.text for b in m.parse(source)])
        self.assertEqual([b.metadata for b in blocks if b.kind == "tableCell"], [
            {"row": row, "column": column, "header": row == 0}
            for row in range(3) for column in range(2)])
        notes = [b for b in blocks if b.kind == "marginNote"]
        self.assertEqual([b.metadata["speaker"] for b in notes], ["George", "the narrator"])
        self.assertEqual([b.metadata["number"] for b in notes], [1, 2])
        self.assertEqual([b.kind for b in blocks[-3:]], ["paragraph", "ordered", "bullet"])
        self.assertIn("*the Moon*. Then — *George*, who", notes[0].text)
        paths = [self.root / m.CATALOG, self.root / m.MANIFEST, self.canonical()]
        before = [p.read_bytes() for p in paths]
        self.assertEqual(self.reimport(), chapter)
        self.assertEqual([p.read_bytes() for p in paths], before)
        m.validate(self.root)

    def test_docs_cli_and_check_against_original(self):
        converted = self.root / "converted.md"
        command = [sys.executable, "-B", str(TOOL), "--root", str(self.root)]
        result = subprocess.run(command + ["from-docs", str(DOCS_FIXTURE), "--out", str(converted)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(converted.read_text(), DOCS_MARKDOWN.read_text())
        self.imported(converted.read_text())
        check = command + ["check", "--docs", str(DOCS_FIXTURE), "--id", "fixture"]
        self.assertEqual(subprocess.run(check, capture_output=True).returncode, 0)
        # A consistent source/catalog/manifest edit must still fail against the signed-off Doc.
        self.canonical().write_text(self.canonical().read_text().replace("100% quiet", "99% quiet"))
        self.reimport()
        result = subprocess.run(check, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("differs from Docs", result.stderr)

    def test_table_cell_edit_and_move_keep_keys_and_other_cells(self):
        self.imported(DOCS_MARKDOWN.read_text())
        original = m.parse(self.canonical().read_text())
        cells = [b for b in original if b.kind == "tableCell"]
        lines = self.canonical().read_text().splitlines()
        row = next(i for i, line in enumerate(lines) if "*The Moon* |" in line)
        lines[row], lines[row + 1] = lines[row + 1], lines[row]
        self.canonical().write_text("\n".join(lines).replace("100% quiet", "100% still") + "\n")
        self.reimport()
        updated = [b for b in m.parse(self.canonical().read_text()) if b.kind == "tableCell"]
        self.assertEqual([b.key for b in updated], [b.key for b in cells[:2] + cells[4:] + cells[2:4]])
        self.assertIn("100% still", m.english(self.catalog()["strings"][cells[3].key]))
        m.validate(self.root)

    def test_new_metadata_is_checked_and_broken_structure_is_rejected(self):
        self.imported(DOCS_MARKDOWN.read_text())
        path = self.root / m.MANIFEST
        original = m.load_json(path)
        for field, value in (("speaker", "wrong"), ("number", 9), ("row", 9), ("column", 1), ("header", False)):
            changed = deepcopy(original)
            block = next(b for b in changed["chapters"][0]["blocks"] if field in b)
            block[field] = value
            m.write_json(path, changed)
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "manifest differs"):
                m.validate(self.root)
        for body in ("| A | B |\n| a | b |", "| A | B | C |\n| --- | --- | --- |\n| a | b | c |",
                     "| A | B |\n| --- | --- |", "| A | B |\n| --- | --- |\n| a | |",
                     "*In the margin*\n\n1. Unsigned."):
            with self.subTest(body=body), self.assertRaises(ValueError):
                m.parse("# Title\n\nSubtitle.\n\n" + body)

    def test_docs_rejects_unsupported_content_instead_of_dropping_it(self):
        for xml in ("<image/>", "<paragraph><mention name='Keep me'/></paragraph>",
                    "<paragraph><text><strikethrough>Keep me</strikethrough></text></paragraph>",
                    "<table><row><cell><paragraph><text>Not a header</text></paragraph></cell></row></table>"):
            with self.subTest(xml=xml), self.assertRaises(ValueError):
                m.from_docs({"data": {"xml": "<doc><paragraph heading='1'><text>Title</text></paragraph>"
                                          "<paragraph><text>Subtitle.</text></paragraph>" + xml + "</doc>"}})


if __name__ == "__main__":
    unittest.main()
