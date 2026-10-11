"""Palette gallery checks against the recorded run and temporary schedules.

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/factory -p 'test_palette_gallery.py'
"""
from datetime import date
from html.parser import HTMLParser
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from factory.taste import calibration, pages

spec = importlib.util.spec_from_file_location('palette_gallery', ROOT / 'tools/factory/palette_gallery.py')
gallery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gallery)


class Cards(HTMLParser):
    def __init__(self, page):
        super().__init__()
        self.cards = {}
        self.current = None
        self.feed(page)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'article':
            self.current = attrs['id']
            self.cards[self.current] = ''

    def handle_endtag(self, tag):
        if tag == 'article':
            self.current = None

    def handle_data(self, data):
        if self.current:
            self.cards[self.current] += data


class PaletteGalleryTests(unittest.TestCase):
    def setUp(self):
        output = Path('/root/factory-out/F12')
        output.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix='gallery-test-', dir=output)
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.run = self.folder / 'color-names/run'
        self.run.mkdir(parents=True)
        source = gallery.DEFAULT_RUN
        for filename in ('slots.json', 'decision.json', 'checkpoint.json', 'rules.json'):
            shutil.copyfile(source / filename, self.run / filename)
        for dirname in ('proposals', 'verdicts', 'ballots'):
            shutil.copytree(source / dirname, self.run / dirname)
        self.output = self.folder / 'a gallery.html'
        self.day = date(2026, 10, 11)

    def save(self, path, data):
        path.write_text(json.dumps(data))

    def schedule(self, records):
        path = self.run.parent / 'drops.json'
        self.save(path, records)
        return path

    def build(self, **kwargs):
        gallery.build(self.run, self.output, as_of=self.day, **kwargs)
        return self.output.read_text()

    def test_real_checkpoint_replacements_provenance_and_love(self):
        page = self.build(preview=True)
        self.assertEqual(page, self.build(preview=True))
        cards = Cards(page).cards
        self.assertEqual(len(cards), 36)
        for sid, old, new, maker in ((20, 'Chalk Dust', 'Salt Flat', 'The original vocabulary'),
                                    (21, 'Apple Blossom', 'Blossom Dust', 'The Child at Bedtime'),
                                    (30, 'Paper Lantern', 'Torchlight', 'The Open Source Enthusiast'),
                                    (36, 'Golden Hour', 'Late Sunlight', 'The Writer')):
            self.assertIn(f'Paul vetoed {old}. Replaced by {new}.', cards[f'color-{sid}'])
            self.assertIn(f'Named by {maker}', cards[f'color-{sid}'])
            self.assertIn('Paul has not marked this name as loved', cards[f'color-{sid}'])
            self.assertIn(f'>{new}</h2>', page)
        self.assertIn('Loved by Paul', cards['color-2'])
        self.assertIn('A young willow leaf in spring', cards['color-2'])
        self.assertIn('No proposer reason recorded.', cards['color-1'])
        self.assertIn('Near-duplicate of Lantern Paper', cards['color-30'])
        self.assertIn('Preferred Ripe Guava', cards['color-30'])
        self.assertIn('Warm coral like a fruit lit by one lamp.', cards['color-30'])
        self.assertIn('Paul · veto', cards['color-20'])

    def test_past_and_today_drop_but_future_and_unscheduled_records_are_absent(self):
        self.schedule([{'date': '2026-10-12', 'colors': [3]},
                       {'date': '2026-10-11', 'colors': ['2']},
                       {'date': '2026-10-10', 'colors': [1]}])
        page = self.build()
        self.assertEqual(list(Cards(page).cards), ['color-1', 'color-2'])
        self.assertIn('2 colors revealed · 2026-10-11 UTC', page)
        for hidden in ('Izba Wood', 'Salt Flat', 'color-3', '4C3A2B', 'Dusty Road'):
            self.assertNotIn(hidden, page)
        self.assertNotIn('<script', page)
        self.assertEqual(len(Cards(self.build(preview=True)).cards), 36)
        gallery.build(self.run, self.output, as_of=date(2026, 10, 12))
        self.assertEqual(len(Cards(self.output.read_text()).cards), 3)

    def test_before_first_drop_and_empty_schedule_show_empty_page(self):
        for schedule in ([], [{'date': '2026-10-12', 'colors': list(range(1, 37))}]):
            self.schedule(schedule)
            page = self.build()
            self.assertFalse(Cards(page).cards)
            self.assertIn('The first colors are still waiting', page)
            self.assertNotIn('Beeswax', page)

    def test_missing_schedule_requires_preview(self):
        with self.assertRaisesRegex(ValueError, 'schedule missing'):
            self.build()
        self.assertFalse(self.output.exists())
        self.assertEqual(len(Cards(self.build(preview=True)).cards), 36)

    def test_malformed_schedules_fail_even_in_preview(self):
        for records in ({}, [{'date': '20261011', 'colors': [1]}],
                        [{'date': '2026-02-30', 'colors': [1]}],
                        [{'date': '2026-10-11', 'colors': '1'}],
                        [{'date': '2026-10-11', 'colors': [True]}],
                        [{'date': '2026-10-11', 'colors': [99]}],
                        [{'date': '2026-10-11', 'colors': [1, '1']}],
                        [{'date': '2026-10-11', 'colors': [1]},
                         {'date': '2026-10-12', 'colors': [1]}]):
            with self.subTest(records=records):
                self.schedule(records)
                with self.assertRaises(ValueError):
                    self.build(preview=True)

    def test_proposal_reason_and_all_prose_are_escaped(self):
        malicious = '<script>alert("x")</script> & {{NOTICE}}'
        proposal = gallery.read(self.run / 'proposals/medea.json')
        for candidate in proposal['names']['2']:
            if candidate['name'] == 'Willow Leaf':
                candidate['why'] = malicious
        self.save(self.run / 'proposals/medea.json', proposal)
        picks = gallery.read(self.run / 'checkpoint.json')
        picks['picks'][0]['note'] = malicious
        self.save(self.run / 'checkpoint.json', picks)
        verdict = gallery.read(self.run / 'verdicts/A-painter.json')
        verdict['slots']['1']['why'] = malicious
        self.save(self.run / 'verdicts/A-painter.json', verdict)
        page = self.build(preview=True)
        self.assertNotIn('<script', page)
        self.assertIn('&lt;script&gt;', page)
        self.assertEqual(Cards(page).cards['color-2'].count(malicious), 1)
        self.assertIn(malicious, Cards(page).cards['color-1'])

    def test_veto_without_replacement_and_mismatched_picks_fail(self):
        records = gallery.read(self.run / 'checkpoint.json')
        del records['picks'][19]['replacement']
        self.save(self.run / 'checkpoint.json', records)
        with self.assertRaisesRegex(ValueError, 'needs a checkpoint replacement'):
            self.build(preview=True)
        records['picks'][19]['replacement'] = {'name': 'Made Up', 'source': 'writer'}
        self.save(self.run / 'checkpoint.json', records)
        with self.assertRaisesRegex(ValueError, 'candidate absent'):
            self.build(preview=True)
        records['picks'][0]['name'] = 'Different Name'
        self.save(self.run / 'checkpoint.json', records)
        with self.assertRaisesRegex(ValueError, 'name differs from decision'):
            self.build(preview=True)

    def test_checkpoint_envelope_and_legacy_formats_work_with_page_tools(self):
        records = calibration.picks(self.run / 'checkpoint.json')
        self.assertEqual(len(records), 36)
        path = self.folder / 'picks.json'
        for data in (records, {f'c{p["slot"]}': p for p in records}):
            self.save(path, data)
            self.assertEqual(calibration.picks(path), records)
        pages.generate(self.run, self.folder / 'kit-gallery.html',
                       checkpoint=self.run / 'checkpoint.json', gallery=True)
        self.assertIn('Beeswax', (self.folder / 'kit-gallery.html').read_text())

    def test_partial_checkpoint_does_not_invent_love(self):
        self.save(self.run / 'checkpoint.json', {'by': 'Paul', 'picks': []})
        cards = Cards(self.build(preview=True)).cards
        self.assertIn('Paul has not marked this name as loved', cards['color-1'])
        self.assertIn('Chalk Dust', cards['color-20'])

    def test_cli_and_output_guard(self):
        command = [sys.executable, '-B', str(ROOT / 'tools/factory/palette_gallery.py'),
                   '--run', str(self.run), '--out', str(self.output)]
        failed = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(failed.returncode, 1)
        self.assertIn('schedule missing', failed.stderr)
        completed = subprocess.run(command + ['--preview', '--as-of', '2026-10-11'],
                                   capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(len(Cards(self.output.read_text()).cards), 36)
        with self.assertRaisesRegex(ValueError, 'outside the repository'):
            gallery.build(self.run, ROOT / 'gallery.html', preview=True)
        self.assertFalse((ROOT / 'gallery.html').exists())


if __name__ == '__main__':
    unittest.main()
