"""F36 offline run, crash/resume, refusals, validators and historical comparison."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from factory.taste import codex_lamp as lamp, lamp_hatch, lamp_compare, loop


class LampTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(dir='/root/factory-out/F36')
        cls.root = Path(cls.temp.name)
        cls.bin = cls.root / 'bin'
        cls.bin.mkdir()
        fake = cls.bin / 'codex'
        shutil.copyfile(loop.REPO / 'tools/factory/fixtures/fake_codex_lamp.py', fake)
        fake.chmod(0o755)
        cls.skill = lamp_hatch.find_skill()
        cls.fixture = cls.root / 'fixture'
        cls.make_fixture(cls.fixture)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    @staticmethod
    def make_fixture(root):
        from PIL import Image, ImageDraw
        (root / 'final').mkdir(parents=True)
        (root / 'qa').mkdir()
        (root / 'previews').mkdir()
        atlas = Image.new('RGBA', (1536, 2288))
        draw = ImageDraw.Draw(atlas)
        for row, count in enumerate((6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8)):
            for col in range(count):
                jump = 30 if row == 4 and col == 2 else 0
                x, y = col * 192, row * 208 - jump
                draw.rectangle((x + 55, y + 70, x + 135, y + 180), fill=(90, 70, 50, 255))
        atlas.save(root / 'final/spritesheet.webp', lossless=True)
        for name in ('chroma-despill-extended', 'review', 'look-continuity'):
            loop.save(root / 'qa' / (name + '.json'), {'ok': True, 'chroma_key': '#FF00FF'})
        labels = ('000', '022.5', '045', '067.5', '090', '112.5', '135', '157.5',
                  '180', '202.5', '225', '247.5', '270', '292.5', '315', '337.5')
        directions = ['up'] + ['up-right'] * 3 + ['right'] + ['down-right'] * 3 + ['down'] + ['down-left'] * 3 + ['left'] + ['up-left'] * 3
        loop.save(root / 'qa/direction-semantics.json', {'directions': [
            dict(label=label, expected=direction, observed='Synthetic fixture landmark.', verdict='pass',
                 reason='Geometry fixture only; not a visual judgement.') for label, direction in zip(labels, directions)]})
        atlas.crop((0, 0, 192, 208)).save(root / 'previews/all-states.gif')

    def setUp(self):
        self.case = Path(tempfile.mkdtemp(dir=self.root))
        self.run = self.case / 'run'
        self.run.mkdir()
        self.log = self.case / 'calls.jsonl'
        self.env = {'PATH': str(self.bin) + os.pathsep + os.environ['PATH'],
                    'FAKE_CODEX_LOG': str(self.log), 'FAKE_ATLAS_FIXTURE': str(self.fixture),
                    'PYTHONDONTWRITEBYTECODE': '1'}
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, self.env).start()
        # Publishing remains real, but a temporary fake repository receives test pixels.
        self.repo = self.case / 'repo'
        self.inputs = lamp.source_snapshot()
        patch.object(lamp, 'source_snapshot', return_value=self.inputs).start()
        patch.object(loop, 'REPO', self.repo).start()

    def driver(self):
        return lamp.Lamp(self.run, 'primary-test', 'comparison-test', 'high', 4, 3, self.skill)

    def calls(self):
        return [json.loads(x) for x in self.log.read_text().splitlines() if json.loads(x)['event'] == 'start']

    def test_whole_run_resume_refusal_failure_redo_and_primary_only(self):
        with patch.dict(os.environ, {'FAKE_REFUSE': 'snow-queen', 'FAKE_FAIL': 'scholar',
                                     'FAKE_REDO': 'moon', 'FAKE_BRIEF_REPAIR': 'moon'}):
            real_repo = Path(__file__).resolve().parents[2]
            command = [sys.executable, '-m', 'factory.taste.codex_lamp', 'run', str(self.run),
                       '--model', 'primary-test', '--compare', 'comparison-test', '--skill-dir', str(self.skill)]
            interrupted = subprocess.run(command, cwd=real_repo, capture_output=True, text=True,
                env={**os.environ, 'FAKE_CRASH': 'style-proposals-0-moon-m0'})
            self.assertEqual(interrupted.returncode, -9, interrupted.stderr)
            completed = {p: p.read_bytes() for p in self.run.glob('records/*/*.json')}
            self.assertTrue(completed)
            driver = self.driver()
            summary = driver.run_plan()
            self.assertTrue(all(p.read_bytes() == data for p, data in completed.items()))
            self.assertEqual(summary['pets']['snow-queen'], 'refused')
            self.assertEqual(summary['pets']['scholar'], 'failed')
            self.assertEqual(summary['pets']['moon'], 'validated')
            calls = self.calls()
            self.assertEqual(len([c for c in calls if 'set-snow-queen' in c['work']]), 1)
            self.assertEqual(len([c for c in calls if '/redo-moon/' in c['work']]), 1)
            images = list((self.repo / 'factory/pets').glob('*/spritesheet.webp'))
            self.assertEqual(len(images), 18)
            self.assertTrue(all(sum(p.stat().st_size for p in image.parent.iterdir()) <= 2_000_000 for image in images))
            self.assertEqual(loop.load(self.run / 'decisions/shortlist-0.json')['selected'], ['style-00', 'style-01'])
            driver.run_plan()
            self.assertEqual(len(self.calls()), len(calls))
            for path in self.run.glob('jobs/*/*.json'):
                job = loop.load(path)
                if job['model'] == 'comparison-test':
                    primary = loop.load(path.with_name(path.name.replace('-m1', '-m0')))
                    self.assertEqual(job['prompt'], primary['prompt'])
                if job['stage'] in ('style-decision', 'image-review', 'redo-review'):
                    self.assertTrue(job['images'])
            for call in calls:
                args = call['args']
                if '-s' in args:
                    self.assertEqual(args[args.index('-s') + 1], 'workspace-write')
                    self.assertIn('sandbox_workspace_write.writable_roots=["/root/factory-out"]', args)
                else:
                    self.assertEqual(args[args.index('--sandbox') + 1], 'read-only')
            events = [json.loads(line) for line in self.log.read_text().splitlines()]
            live = peak = 0
            for event in events:
                if '-s' in event['args']:
                    live += 1 if event['event'] == 'start' else -1
                    peak = max(peak, live)
            self.assertLessEqual(peak, 3)
            self.assertEqual(live, 0)

    def test_actual_mid_round_process_crash_and_resume(self):
        # Separate process is killed by the fake after several durable jobs have completed.
        source = Path(__file__).resolve().parents[2]
        command = [sys.executable, '-m', 'factory.taste.codex_lamp', 'replay', str(self.run),
                   '--pieces', 'renumber', '--models', 'primary-test,comparison-test', '--parallel', '1']
        env = {**os.environ, 'FAKE_CRASH': 'renumber-moon-m0'}
        first = subprocess.run(command, cwd=source, env=env, capture_output=True, text=True)
        self.assertEqual(first.returncode, -9, first.stderr)
        records = {p: p.read_bytes() for p in self.run.glob('replay/records/*/*.json')}
        self.assertGreater(len(records), 4)
        completed = {p.stem for p in records}
        before = self.calls()
        second = subprocess.run(command, cwd=source, env=env, capture_output=True, text=True)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertTrue(all(p.read_bytes() == data for p, data in records.items()))
        new = self.calls()[len(before):]
        self.assertTrue(all(not any('/' + name + '-0/' in c['work'] for name in completed) for c in new))
        self.assertEqual(len(list(self.run.glob('replay/records/*/*.json'))), 38)

    def test_replay_all_pieces_comparison_and_exact_prompts(self):
        real_repo = Path(__file__).resolve().parents[2]
        with patch.object(loop, 'REPO', real_repo):
            result = lamp_compare.replay_run(self.run, ['chapter-6', 'renumber', 'front-door'],
                                             ['primary-test', 'comparison-test'], 'high', 4)
        self.assertEqual(result['replayed_jobs'], 114)
        for path in self.run.glob('replay/jobs/*/*.json'):
            job = loop.load(path)
            self.assertEqual(job['prompt'], (real_repo / 'factory/pieces' / job['stage'] /
                                            'prompts' / (job['guardian'] + '.md')).read_text())
            self.assertIn('read-only replay', job['transport_instructions'])
        lamp_compare.compare_run(self.run)
        data = loop.load(self.run / 'comparison.json')
        self.assertEqual(len(data['replies']), 171)
        self.assertEqual(len(data['comparisons']), 171)
        self.assertEqual({r['model'] for r in data['replies']}, {'primary-test', 'comparison-test', 'Claude (Haiku)'})
        self.assertTrue(any(p['votes'].get('stance') == {'equal': False} for p in data['comparisons']))
        baseline = (self.run / 'comparison.json').read_bytes()
        lamp_compare.compare_run(self.run)
        self.assertEqual((self.run / 'comparison.json').read_bytes(), baseline)

    def test_actual_validators_reject_bad_quality_even_after_structural_success(self):
        work = self.case / 'candidate'
        shutil.copytree(self.fixture, work)
        from PIL import Image
        with Image.open(work / 'final/spritesheet.webp') as atlas:
            idle = atlas.crop((0, 0, 192, 208))
            for col in range(5):
                atlas.paste(idle, (col * 192, 4 * 208))
            atlas.save(work / 'final/spritesheet.webp', lossless=True)
        with self.assertRaisesRegex(ValueError, 'validate_pet_quality.py failed'):
            lamp_hatch.validate(work, self.skill)
        self.assertTrue(loop.load(work / 'gate/atlas.json')['ok'])
        self.assertFalse(loop.load(work / 'gate/quality.json')['ok'])

    def test_invalid_reply_retries_identical_prompt_once(self):
        job = dict(id='invalid-first', round=1, attempt=0, role='guardian', stage='test',
                   guardian='moon', model='primary-test', effort='high', images=[],
                   prompt='Only this seat prompt.', reply_schema=lamp.schema.obj({'why': lamp.S}))
        with patch.dict(os.environ, {'FAKE_BAD_REPLY': 'invalid-first'}):
            record = lamp.execute(self.run, job)
        self.assertEqual(record['attempt'], 1)
        calls = self.calls()
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0]['prompt'], calls[1]['prompt'])
        self.assertTrue((self.run / 'rejections/001/invalid-first-0.json').exists())
        lamp.execute(self.run, job)
        self.assertEqual(len(self.calls()), 2)

    def test_historical_originality_veto_retains_its_recorded_shape(self):
        rule = lamp_compare.historical_schema('chapter-6', 'originality')
        reply = dict(guardian='originality', flags=[], veto={'pet': 'medea', 'why': 'Test risk.'}, making='Test.')
        self.assertEqual(lamp.schema.validate(reply, rule), [])
        self.assertFalse(lamp_compare.agreement(reply, {**reply, 'veto': {'pet': 'moon', 'why': 'Test.'}})
                         ['veto_targets_equal'])

    def test_interrupted_refusal_is_terminal_even_with_partial_reply(self):
        driver = self.driver()
        work = self.run / 'hatches/set-moon/attempt-interrupted'
        work.mkdir(parents=True)
        (work / 'codex.jsonl').write_text(json.dumps({'type': 'error', 'code': 'content_policy_violation'}) + '\n')
        (work / 'reply.json').write_text('{')
        result = lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        self.assertEqual(result['status'], 'refused')
        self.assertFalse(self.log.exists())
        self.assertEqual(lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None), result)

    def test_changed_config_and_symlinks_are_rejected(self):
        self.driver()
        with self.assertRaisesRegex(ValueError, 'frozen input differs'):
            lamp.Lamp(self.run, 'different', None, 'high', 4, 3, self.skill)
        (self.run / 'jobs').symlink_to(self.case / 'elsewhere')
        with self.assertRaises(ValueError):
            lamp.execute(self.run, dict(id='safe', round=1, attempt=0))


if __name__ == '__main__':
    unittest.main()
