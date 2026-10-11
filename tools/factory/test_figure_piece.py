"""F3 craft, blind ballots and byte replay, using canned replies through the loop CLI.

Run with unittest (or pytest). FIGURE_PIECE_REAL=1 uses render.py for the CLI dry run;
FIGURE_PIECE_DRY_RUN selects a fresh outside-repo directory to retain its artifacts.
Build figures first and set FIGURES_BIN when using an external Swift scratch path.
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from factory.taste import cli, kit, loop, schema
from factory.taste.pieces import figure


def fake_render(spec, scene, out):
    """Small native-pixel stand-ins; thin ink fails exactly as the engine gate does."""
    out.mkdir(parents=True, exist_ok=True)
    loop.save(out / 'spec.json', spec)
    loop.save(out / 'checks.json', [{'name': name, 'value': 0, 'limit': 0,
                                   'pass': name != 'inkWidth' or spec['ink']['width'] > .01}
                                  for name in sorted(figure.CHECKS)])
    (out / 'sheets').mkdir()
    for kind in figure.SHEETS:
        Image.new('RGB', (120, 80), '#abc123').save(out / 'sheets' / f'{kind}.png')
    return 0


class FigurePieceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='figure-piece-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = loop.REPO / 'factory/pieces/figure'
        self.baseline = loop.load(loop.REPO / 'factory/specs/baseline.json')
        self.fields = figure.contract()

    def test_ranges_types_choices_and_unknown_fields_name_the_field(self):
        for key, rule in self.fields.items():
            if rule['kind'] not in ('number', 'integer') or 'range' not in rule:
                continue
            group, field = key.split('.')
            for value in rule['range']:
                self.assertFalse(figure.problems({group: {field: value}}, self.fields), key)
            for value in (rule['range'][0] - 1, rule['range'][1] + 1, True, '1'):
                with self.subTest(field=key, value=value):
                    errors = figure.problems({group: {field: value}}, self.fields)
                    self.assertTrue(errors)
                    self.assertIn(key, errors[0])
        invalid = [('figure.headwear', 'cap'), ('motion.headingSteps', 4),
                   ('motion.fps', 24.5), ('magic.burst', 1.5), ('motion.onTwos', 1),
                   ('ink.color', '#ggg'), ('figure.accent', 'gold'),
                   ('magic.colors', []), ('magic.colors', ['#112233'] * 5),
                   ('magic.colors', ['#112233', 'red']), ('ink.wobble', float('nan')),
                   ('ink.width', 10 ** 1000), ('motion.step', float('inf')),
                   ('figure.typo', .1)]
        for key, value in invalid:
            group, field = key.split('.')
            errors = figure.problems({group: {field: value}}, self.fields)
            self.assertTrue(errors, key)
            self.assertIn(key, errors[0])
        self.assertIn('oops', figure.problems({'oops': {}}, self.fields)[0])
        self.assertTrue(figure.problems({'figure': 1}, self.fields))
        self.assertTrue(figure.problems({'version': 2}, self.fields))
        self.assertFalse(figure.problems({'figure': {'accent': None}}, self.fields))
        for color in ('#abc', '#abcd', '#aabbcc', '#aabbccdd'):
            self.assertFalse(figure.problems({'ink': {'color': color}}, self.fields))
        spec = figure.apply(self.baseline, {'figure': {'headSize': .18},
                            'magic': {'colors': ['#112233']}}, self.fields)
        self.assertEqual(spec['figure']['headSize'], .18)
        self.assertEqual(spec['figure']['torso'], self.baseline['figure']['torso'])
        self.assertEqual(spec['magic']['colors'], ['#112233'])
        self.assertEqual(self.baseline['figure']['headSize'], .16)

    def test_checks_fail_closed_and_include_the_incumbent(self):
        run_path = self.root / 'run'
        record = kit.new(self.source, run_path)
        for checks in ([], [{'name': 'inkWidth', 'pass': True}],
                       [{'name': name, 'pass': name != 'ikClamps'} for name in figure.CHECKS],
                       [{'name': name, 'pass': True} for name in figure.CHECKS]):
            def render(spec, scene, out):
                out.mkdir(parents=True, exist_ok=True)
                loop.save(out / 'checks.json', checks)
                return 0
            with patch.object(figure, 'render', side_effect=render):
                failures, _, artifacts = figure.craft({'patch': {}}, record,
                                           run_path / 'inputs/hero.json', self.root / 'render')
            self.assertTrue(failures)
            self.assertFalse(artifacts['images'])
        runner = kit.Run(run_path, self.root / 'out')
        for job in runner.jobs(1):
            loop.save(run_path / 'replies/001' / f"{job['id']}.json",
                      {'slots': {'1': [{'patch': {}, 'why': 'CANNED unchanged.'}]}})
        with patch.object(figure, 'craft', return_value=(['checks.json: ikClamps failed'], 'bad', {})):
            with self.assertRaisesRegex(ValueError, 'no figure candidate passed'):
                runner.collect(1)
        rejected = loop.load(runner.folder(1) / 'rejected.json')
        self.assertTrue(any(c['source'] == 'incumbent' for c in rejected))
        self.assertFalse((runner.folder(1) / 'slate.json').exists())
        self.assertFalse(list((run_path / 'jobs/001').glob('juror-*.json')))

    def test_new_freezes_inputs_and_invalid_patches_do_not_render(self):
        run_path = self.root / 'run'
        record = kit.new(self.source, run_path)
        scene = loop.load(run_path / 'inputs/hero.json')
        self.assertEqual((run_path / 'inputs' / scene['background']).read_bytes(),
                         (loop.REPO / 'factory/scenes/hero-painted.png').read_bytes())
        self.assertEqual(record['figure']['baseline'], self.baseline)
        self.assertEqual(record['figure']['fields'], self.fields)
        with patch.dict(figure.RANGES['motion'], step=(0, 1)):
            runner = kit.Run(run_path, self.root / 'out')
            with patch.object(figure, 'render') as render:
                failures, _, images = figure.craft({'patch': {'motion': {'step': .5}}},
                                     runner.record, run_path / 'inputs/hero.json', self.root / 'render')
            render.assert_not_called()
            self.assertIn('motion.step', failures[0])
            self.assertFalse(images)

    def test_canned_cli_dry_run_blind_sheets_and_byte_identical_replay(self):
        root = Path(os.environ.get('FIGURE_PIECE_DRY_RUN', self.root))
        run_path, out = root / 'run', root / 'review'
        args = ['--run', str(run_path), '--out', str(out)]

        def command(*words, expected=0):
            with contextlib.redirect_stdout(io.StringIO()) as captured:
                self.assertEqual(cli.main(args + list(words)), expected)
            return json.loads(captured.getvalue())

        command('new', 'figure')
        command('draw', '1')
        jobs = command('jobs', '1')
        patches = [{'figure': {'headAspect': .9}}, {'figure': {'headAspect': .95}},
                   {'ink': {'taper': .6}}, {'figure': {'headwearSize': 1.1}}]
        for i, job in enumerate(jobs):
            self.assertIn('Your charter', job['prompt'])
            self.assertIn('one to 3', job['prompt'])
            values = [{'patch': patches[i], 'why': f'CANNED proposer reason {i}.'}]
            if i == 0:
                values += [{'patch': {'motion': {'step': .5}}, 'why': 'CANNED invalid range.'},
                           {'patch': {'ink': {'width': .01}}, 'why': 'CANNED failing engine check.'}]
            reply = {'slots': {'1': values}}
            self.assertFalse(schema.validate(reply, job['reply_schema']))
            too_many = {'slots': {'1': values[:1] * 4}}
            self.assertTrue(schema.validate(too_many, job['reply_schema']))
            loop.save(run_path / 'replies/001' / f"{job['id']}.json", reply)
        renderer = contextlib.nullcontext() if os.environ.get('FIGURE_PIECE_REAL') == '1' else \
                   patch.object(figure, 'render', side_effect=fake_render)
        with renderer:
            command('collect', '1')
        runner = kit.Run(run_path, out)
        rejected = loop.load(runner.folder(1) / 'rejected.json')
        self.assertEqual(len(rejected), 2)
        self.assertTrue(any('motion.step' in ' '.join(c['fails']) for c in rejected))
        self.assertTrue(any('inkWidth' in ' '.join(c['fails']) for c in rejected))
        slate = loop.load(runner.folder(1) / 'slate.json')[0]
        self.assertEqual(len(slate['candidates']), 5)
        jury_jobs = command('jobs', '1')
        orders = set()
        for job in jury_jobs:
            ballot = loop.load(runner.folder(1) / 'ballots' / f"{job['guardian']}.json")['1']
            orders.add(tuple(ballot.values()))
            self.assertIn('Your charter', job['prompt'])
            self.assertIn('guards against', job['prompt'])
            self.assertNotIn('CANNED proposer reason', job['prompt'])
            self.assertNotIn('Parameters:', job['prompt'])
            self.assertNotIn('spec-', job['prompt'])
            self.assertEqual(len(job['images']), 4 * len(ballot))
            candidates = {c['name']: c for c in slate['candidates']}
            for letter, name in ballot.items():
                for kind, original in zip(figure.SHEETS, candidates[name]['images']):
                    path = out / '001/jury' / job['guardian'] / '1' / f'{letter}-{kind}.png'
                    self.assertIn(str(path), job['images'])
                    self.assertNotIn(name, str(path))
                    with Image.open(original) as source, Image.open(path) as blind:
                        self.assertEqual(blind.size, (source.width, source.height + 48))
                        self.assertEqual(blind.crop((0, 48, blind.width, blind.height)).tobytes(),
                                         source.convert('RGB').tobytes())
                        self.assertFalse(blind.info)
            props = job['reply_schema']['properties']['slots']['properties']['1']['properties']
            verdict = {'candidates': {letter: {'lives': 'CANNED readable worker.', 'veto': None}
                                      for letter in ballot}}
            if 'ranking' in props:
                verdict.update(ranking=list(ballot), note='CANNED plumbing check, no taste judgment.')
            loop.save(run_path / 'replies/001' / f"{job['id']}.json", {'slots': {'1': verdict}})
        self.assertGreater(len(orders), 1)
        command('collect', '1')
        command('decide', '1')
        replay = root / 'replay'
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(['--run', str(run_path), '--out', str(replay), 'replay']), 0)
        for relative in ('rounds/001/decision.json', 'ledger.json', 'champion.json'):
            self.assertEqual((run_path / relative).read_bytes(), (replay / relative).read_bytes())
        # Carry the winning patch forward, still relative to the frozen original baseline.
        slot = runner.slots(2)[0]
        winner = loop.load(run_path / 'champion.json')['results'][0]['winner']
        candidate = next(c for c in slate['candidates'] if c['name'] == winner)
        self.assertEqual(slot['incumbent_candidate']['patch'], candidate['patch'])


if __name__ == '__main__':
    unittest.main()
