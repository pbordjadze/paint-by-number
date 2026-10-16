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
from factory.taste import codex_lamp as lamp, lamp_hatch, lamp_compare, lamp_inputs, lamp_restart, lamp_rules, lamp_resume, loop
from factory.taste import lamp_images, lamp_maker
from tools.factory.fixtures.strict_schema import check_strict


class LampTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(dir=os.environ.get('FACTORY_TEST_OUT', '/root/factory-out'))
        cls.root = Path(cls.temp.name)
        cls.bin = cls.root / 'bin'
        cls.bin.mkdir()
        fake = cls.bin / 'codex'
        shutil.copyfile(loop.REPO / 'tools/factory/fixtures/fake_codex_lamp.py', fake)
        shutil.copyfile(loop.REPO / 'tools/factory/fixtures/strict_schema.py', cls.bin / 'strict_schema.py')
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
                                     'FAKE_REDO': 'moon', 'FAKE_BRIEF_REPAIR': 'moon',
                                     'FAKE_REJECT_FIRST_STYLES': '1', 'FAKE_STYLE_FLAGS': '1'}):
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
            self.assertEqual(len(images), 20)
            self.assertTrue(all(sum(p.stat().st_size for p in image.parent.iterdir()) <= 2_000_000 for image in images))
            self.assertEqual(loop.load(self.run / 'decisions/shortlist-0.json')['selected'], [])
            self.assertEqual(loop.load(self.run / 'decisions/shortlist-1.json')['selected'], ['style-00', 'style-01'])
            decision = loop.load(self.run / 'decisions/style.json')
            self.assertEqual(decision['selected'], ['style-00'])
            self.assertEqual(decision['excluded'], [])
            notes = lamp_rules.drawing_notes(self.run)
            self.assertEqual({f['target'] for f in notes['flags']}, {'style-00'})
            self.assertEqual({f['seat'] for f in notes['flags']}, {'originality', 'painter'})
            self.assertEqual(loop.load(self.run / 'decisions/briefs.json')['repaired'], ['moon'])
            for call in calls:
                if '/hatches/' not in call['work']:
                    continue
                request = loop.load(Path(call['work']).parent / 'request.json')
                if request['key'].startswith('pilot-'):
                    self.assertNotIn('readability_notes', request)
                else:
                    self.assertEqual(request['readability_notes'], notes)
                    self.assertIn(lamp_rules.READABILITY, call['prompt'])
                    for flag in notes['flags']:
                        self.assertIn(flag['why'], call['prompt'])
                    package = Path(call['work']) / 'package/provenance.json'
                    if package.exists():
                        self.assertEqual(loop.load(package)['readability_notes'], notes)
            reference_pet = loop.load(self.run / 'decisions/reference.json')['selected'][0].removeprefix('pilot-style-00-')
            self.assertEqual(loop.load(self.repo / 'factory/pets' / reference_pet / 'provenance.json')['readability_notes'], notes)
            driver.run_plan()
            self.assertEqual(len(self.calls()), len(calls) + 1)  # Scholar's one fresh gate attempt.
            driver.run_plan()
            self.assertEqual(len(self.calls()), len(calls) + 1)
            stages = set()
            for path in self.run.glob('jobs/*/*.json'):
                job = loop.load(path)
                stages.add(job['stage'])
                if job['model'] == 'comparison-test':
                    primary = loop.load(path.with_name(path.name.replace('-m1', '-m0')))
                    self.assertEqual(job['prompt'], primary['prompt'])
                if job['stage'] in ('style-decision', 'image-review', 'redo-review'):
                    self.assertTrue(job['images'])
            self.assertEqual(stages, {'style-proposals-0', 'style-proposals-1', 'shortlist-0', 'shortlist-1',
                                     'style-decision', 'briefs', 'set-review', 'brief-repair', 'image-review', 'redo-review'})
            for call in calls:
                args = call['args']
                check_strict(loop.load(Path(args[args.index('--output-schema') + 1])))
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

    def legacy_failure(self, result):
        """Model the old driver's durable zero-image report, retaining all raw evidence."""
        result.pop('worker_policy')
        base = self.run / 'hatches' / result['key']
        loop.save(base / 'result.json', result)
        (base / 'active-attempt.json').unlink()
        return {p: p.read_bytes() for p in Path(result['work']).rglob('*') if p.is_file()}

    def test_style_policy_keeps_vetoes_and_other_steps_and_legacy_bytes(self):
        driver = self.driver()
        votes = {'painter': {'ranking': ['B', 'A'], 'vetoes': [],
                             'flags': [{'target': 'B', 'why': 'Work resembles idle.'}]},
                 'originality': {'ranking': [], 'vetoes': [],
                                 'flags': [{'target': 'B', 'why': 'Clarify the pose.'}]}}
        self.assertEqual(driver.tally('style', ['A', 'B'], votes, 1), ['B'])
        self.assertEqual(driver.tally('shortlist-0', ['A', 'B'], votes, 1), ['A'])
        votes['originality']['vetoes'] = [{'target': 'B', 'quote': 'Charter line.', 'why': 'Violation.'}]
        self.assertEqual(driver.tally('style', ['A', 'B'], votes, 1), ['A'])
        votes['painter']['vetoes'] = [{'target': 'A', 'quote': 'Charter line.', 'why': 'Violation.'}]
        self.assertEqual(driver.tally('style', ['A', 'B'], votes, 1), [])
        votes['painter']['vetoes'] = votes['originality']['vetoes'] = []
        # A run without a rules file predates this policy. Loading it cannot opt it in.
        (self.run / 'rules.json').unlink()
        expected = lamp_rules.tally(['A', 'B'], votes, 1)
        loop.save(self.run / 'decisions/style.json', expected)
        before = (self.run / 'decisions/style.json').read_bytes()
        self.assertEqual(self.driver().tally('style', ['A', 'B'], votes, 1), ['A'])
        self.assertEqual((self.run / 'decisions/style.json').read_bytes(), before)
        self.assertEqual(loop.load(self.run / 'rules.json'), lamp_rules.rules(1))

    def test_retally_blocked_style_cli_and_dry_resume_preserve_all_calls_and_evidence(self):
        # A frozen legacy run blocks on flags even with the updated executable.
        loop.save(self.run / 'rules.json', lamp_rules.rules(1))
        with patch.dict(os.environ, {'FAKE_STYLE_FLAGS': '1'}):
            with self.assertRaisesRegex(ValueError, 'image jury rejected every pilot style'):
                self.driver().run_plan()
        loop.write_atomic(self.run / 'replay/unchanged.txt', 'Recorded historical evidence.')
        lamp_compare.compare_run(self.run)
        before = {p: p.read_bytes() for p in self.run.rglob('*') if p.is_file()}
        calls = len(self.calls())
        real_repo = Path(__file__).resolve().parents[2]
        command = [sys.executable, '-m', 'factory.taste.codex_lamp', 'retally-style', str(self.run),
                   '--reason', 'State-readability flags are drawing notes, not charter vetoes.']
        result = subprocess.run(command, cwd=real_repo, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = json.loads(result.stdout)
        self.assertEqual(event['selected'], ['style-00'])
        self.assertEqual(event['revision']['step'], 3)
        self.assertEqual(event['revision']['reason'], command[-1])
        self.assertEqual((self.run / event['revision']['previous_decision']).read_bytes(),
                         before[self.run / 'decisions/style.json'])
        driver = self.driver()
        dry = driver.run_plan(dry_resume=True)
        self.assertEqual((dry['next_step'], dry['selected']), (4, ['style-00']))
        self.assertEqual(len(dry['readability_notes']['flags']), 2)
        self.assertEqual(len(self.calls()), calls)
        self.assertFalse((self.run / 'jobs/006').exists())
        lamp_compare.compare_run(self.run)
        for path, content in before.items():
            if path not in (self.run / 'provenance.json', self.run / 'decisions/style.json'):
                self.assertEqual(path.read_bytes(), content, str(path))
        # Retry after the rule commit but before the derived decision write.
        after = (self.run / 'decisions/style.json').read_bytes()
        (self.run / 'decisions/style.json').write_bytes(before[self.run / 'decisions/style.json'])
        result = subprocess.run(command, cwd=real_repo, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.run / 'decisions/style.json').read_bytes(), after)
        provenance = (self.run / 'provenance.json').read_bytes()
        lamp_rules.retally_style(self.run, 'Repeated migration is a no-op.')
        self.assertEqual((self.run / 'provenance.json').read_bytes(), provenance)
        self.assertEqual(len(self.calls()), calls)
        # The ordinary next run reaches step 4 with the exact same notes and ballots.
        original_round = driver.round
        def stop_at_briefs(number, stage, seats, task, context, rule, **kwargs):
            if number == 6:
                self.assertTrue(all(c['readability_notes'] == dry['readability_notes'] for c in context.values()))
                raise RuntimeError('reached step 4 with notes')
            return original_round(number, stage, seats, task, context, rule, **kwargs)
        with patch.object(driver, 'round', side_effect=stop_at_briefs):
            with self.assertRaisesRegex(RuntimeError, 'reached step 4 with notes'):
                driver.run_plan()
        self.assertEqual(len(self.calls()), calls)
        lamp_inputs.bind_step(self.run, '4')
        with self.assertRaisesRegex(ValueError, 'later step'):
            lamp_rules.retally_style(self.run, 'Too late.')

    def test_retally_refuses_completed_style_and_dry_resume_never_dispatches_missing_work(self):
        driver = self.driver()
        with self.assertRaisesRegex(ValueError, 'dry resume needs a completed job'):
            driver.run_plan(dry_resume=True)
        self.assertFalse(self.log.exists())
        with self.assertRaisesRegex(ValueError, 'recorded style decision'):
            lamp_rules.retally_style(self.run, 'No decision yet.')
        loop.save(self.run / 'rules.json', lamp_rules.rules(1))
        loop.save(self.run / 'decisions/style.json', {'selected': ['style-00']})
        with self.assertRaisesRegex(ValueError, 'blocked legacy'):
            lamp_rules.retally_style(self.run, 'Do not change a completed decision.')
        driver.dry_resume = True
        with self.assertRaisesRegex(ValueError, 'dry resume needs a completed hatch'):
            lamp_hatch.hatch(driver, 'pilot-missing', 'moon', {}, {}, None, None)
        self.assertFalse(self.log.exists())

    def test_resume_all_pilot_blockers_keeps_text_replay_comparison_and_reference(self):
        driver = self.driver()
        original_prompt = driver.prompt
        def legacy_prompt(*args):
            return original_prompt(*args).replace(lamp.UNATTENDED, '').replace(lamp.CONTRACT, '')
        with patch.object(driver, 'prompt', side_effect=legacy_prompt), patch.dict(os.environ,
                {'FAKE_PILOT_BLOCKER': 'all', 'FAKE_CONFLICTING_STYLES': '1'}):
            with self.assertRaisesRegex(ValueError, 'neither style'):
                driver.run_plan()
        evidence = {}
        for path in self.run.glob('hatches/pilot-*/result.json'):
            result = loop.load(path)
            self.assertEqual(result['image_generations'], 0)
            evidence.update(self.legacy_failure(result))
        self.assertEqual(len(list(self.run.glob('hatches/pilot-*'))), 4)
        real_repo = Path(__file__).resolve().parents[2]
        with patch.object(loop, 'REPO', real_repo):
            lamp_compare.replay_run(self.run, ['renumber'], ['primary-test', 'comparison-test'], 'high', 4)
        lamp_compare.compare_run(self.run)
        for folder in ('jobs', 'records', 'replies', 'replay'):
            evidence.update({p: p.read_bytes() for p in (self.run / folder).rglob('*') if p.is_file()})
        for name in ('comparison.json', 'comparison.md'):
            evidence[self.run / name] = (self.run / name).read_bytes()
        before = len(self.calls())
        with patch.dict(os.environ, {'FAKE_REDO': 'moon'}):
            summary = self.driver().run_plan()
            calls = self.calls()
            self.assertEqual(set(summary['pets'].values()), {'validated'})
            self.assertTrue(all(p.read_bytes() == data for p, data in evidence.items()))
            new_calls = calls[before:]
            self.assertFalse(any('style-proposals-' in c['work'] or 'shortlist-' in c['work']
                                 or '/replay/' in c['work'] for c in new_calls))
            pilot_calls = [c for c in new_calls if '/hatches/pilot-' in c['work']]
            self.assertEqual(len(pilot_calls), 4)
            for call in pilot_calls:
                self.assertNotIn('--image', call['args'])
                self.assertIn('reference=null is intentional', call['prompt'])
            for path in self.run.glob('hatches/pilot-*/result.json'):
                _, result = lamp_resume.latest_result(path.parent)
                self.assertEqual(result['status'], 'validated')
                self.assertEqual(loop.load(Path(result['resumed_from']))['image_generations'], 0)
                self.assertNotEqual(str(Path(result['resumed_from']).parent), result['work'])
                self.assertEqual(len(list(path.parent.glob('attempt-*'))), 2)
                provenance = loop.load(Path(result['package']) / 'provenance.json')
                self.assertEqual({o['source'] for o in provenance['contract_overrides']},
                                 {'style.framing', 'style.palette', 'style.rows.idle'})
                self.assertTrue(provenance['decisions'])
                request = loop.load(path.parent / 'request.json')
                self.assertEqual(provenance['style'], request['style'])
                for override in provenance['contract_overrides']:
                    original = request
                    for field in override['source'].split('.'):
                        original = original[field]
                    self.assertEqual(override['original'], original)
            selected = loop.load(self.run / 'decisions/reference.json')['selected']
            self.assertEqual(selected, ['pilot-style-00-bulat-okudzhava'])
            _, pilot = lamp_resume.latest_result(self.run / 'hatches' / selected[0])
            set_calls = [c for c in new_calls if '/hatches/set-' in c['work'] or '/hatches/redo-' in c['work']]
            self.assertEqual(len(set_calls), 23)
            for call in set_calls:
                self.assertEqual(call['args'][call['args'].index('--image') + 1], pilot['contact'])
                provenance = loop.load(Path(call['work']) / 'package/provenance.json')
                self.assertEqual(provenance['reference'], pilot['contact'])
                self.assertEqual(provenance['reference_sha256'], lamp.digest(Path(pilot['contact']).read_bytes()))
            self.driver().run_plan()
            self.assertEqual(len(self.calls()), len(calls))

    def test_new_proposals_include_exact_contract_and_unattended_decisions(self):
        self.assertNotIn('glossary', self.inputs)
        driver = self.driver()
        with patch.object(driver, 'hatch_many', side_effect=RuntimeError('reached pilots')):
            with self.assertRaisesRegex(RuntimeError, 'reached pilots'):
                driver.run_plan()
        for call in self.calls():
            self.assertIn(lamp.UNATTENDED, call['prompt'])
            self.assertIn(lamp.CONTRACT, call['prompt'])
            self.assertIn(lamp.MOTION_POLICY, call['prompt'])
            if 'style-proposals-' in call['work']:
                self.assertIn('Do not invent frame counts, rows or alternate paint looks.', call['prompt'])

    def test_refresh_cli_keeps_started_steps_and_historical_replay_bytes(self):
        self.inputs['glossary'] = {'words': {'supra': 'old glossary'}}
        for guardian in self.inputs['guardians']:
            guardian['charter_text'] += '\n- **Georgian thread**: old frozen field.'
            if guardian['id'] == 'emily-dickinson':
                guardian.update(name='Emily Dickinson', charter='Emily Dickinson')
                guardian.pop('description', None)
        driver = self.driver()
        rule = lamp.schema.obj({'why': lamp.S})
        driver.round(1, 'before', ['moon'], 'Same task.', {}, rule)
        # Exercise migration of records made before input identities were recorded.
        job_path = self.run / 'jobs/001/before-moon-m0.json'
        record_path = self.run / 'records/001/before-moon-m0.json'
        job, record = loop.load(job_path), loop.load(record_path)
        job.pop('inputs_sha256')
        record.pop('inputs_sha256')
        record['job_sha256'] = lamp.digest(job)
        loop.save(job_path, job)
        loop.save(record_path, record)
        (self.run / 'provenance.json').unlink()
        real_repo = Path(__file__).resolve().parents[2]
        with patch.object(loop, 'REPO', real_repo):
            lamp_compare.replay_run(self.run, ['renumber'], ['primary-test'], 'high', 4)
        evidence = {p: p.read_bytes() for folder in ('jobs', 'records', 'replies', 'replay')
                    for p in (self.run / folder).rglob('*') if p.is_file()}
        evidence[self.run / 'inputs.json'] = (self.run / 'inputs.json').read_bytes()
        command = [sys.executable, '-m', 'factory.taste.codex_lamp', 'refresh-inputs', str(self.run),
                   '--reason', 'Use the revised guardian charters for remaining steps.']
        result = subprocess.run(command, cwd=real_repo, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['status'], 'refreshed')
        provenance = loop.load(self.run / 'provenance.json')
        self.assertEqual(provenance['refreshes'][0]['preserved_steps'], {'1': provenance['initial']})
        current = lamp_inputs.current(self.run)
        self.assertNotIn('glossary', current)
        emily = next(g for g in current['guardians'] if g['id'] == 'emily-dickinson')
        self.assertEqual(emily['name'], 'Emily')
        self.assertEqual(emily['charter'], 'Emily')
        self.assertEqual(emily['description'], 'After the poet Emily Dickinson.')
        before = (self.run / 'provenance.json').read_bytes()
        result = subprocess.run(command, cwd=real_repo, capture_output=True, text=True)
        self.assertEqual(json.loads(result.stdout)['status'], 'unchanged')
        self.assertEqual((self.run / 'provenance.json').read_bytes(), before)
        driver = self.driver()
        driver.round(1, 'before', ['moon', 'painter'], 'Same task.', {}, rule, compare=True)
        driver.round(2, 'still-step-one', ['moon'], 'Same task.', {}, rule)
        driver.round(5, 'after', ['moon', 'emily-dickinson', 'originality'], 'Same task.', {}, rule, compare=True)
        self.assertTrue(all(p.read_bytes() == data for p, data in evidence.items()))
        for path in self.run.glob('jobs/*/*.json'):
            job = loop.load(path)
            self.assertEqual('Georgian thread' in job['prompt'], job['round'] < 5)
            if job['round'] == 5:
                self.assertNotIn('glossary', job['prompt'].lower())
                self.assertIn('Emily; ', job['prompt'])
                if job['guardian'] == 'emily-dickinson':
                    self.assertIn('You are Emily.', job['prompt'])
        with patch.object(loop, 'guardians', side_effect=AssertionError('live charters used')):
            calls = len(self.calls())
            self.driver().round(5, 'after', ['moon'], 'Same task.', {}, rule, compare=True)
            self.assertEqual(len(self.calls()), calls)
        lamp_compare.compare_run(self.run)
        report = loop.load(self.run / 'comparison.json')
        self.assertEqual({r['inputs_sha256'] for r in report['replies'] if r['source'] == 'pets'},
                         {provenance['initial'], provenance['current']})
        self.assertEqual(len([r for r in report['seats'] if r['guardian'] == 'moon'
                              and r['model'] == 'primary-test']), 3)  # two revisions plus historical replay
        # Even identical prompts cannot pair across explicitly different inputs.
        record_path = self.run / 'records/005/after-moon-m1.json'
        record = loop.load(record_path)
        record['inputs_sha256'] = provenance['initial']
        loop.save(record_path, record)
        lamp_compare.compare_run(self.run)
        self.assertFalse(any(p['stage'] == 'after' and p['guardian'] == 'moon'
                             for p in loop.load(self.run / 'comparison.json')['comparisons']))

    def test_refresh_preserves_started_step_veto_validation_and_other_inputs(self):
        driver = self.driver()
        old_sha, old = lamp_inputs.for_step(self.run, 7)
        lamp_inputs.for_step(self.run, 9)
        guardians = json.loads(json.dumps(self.inputs['guardians']))
        for guardian in guardians:
            guardian['charter_text'] = '- **guards against**: changed guard.'
        with patch.object(loop, 'guardians', return_value=guardians):
            lamp_inputs.refresh(self.run, 'Revised charters.')
        driver = self.driver()
        new = lamp_inputs.current(self.run)
        self.assertEqual({k: v for k, v in old.items() if k != 'guardians'},
                         {k: v for k, v in new.items() if k != 'guardians'})
        self.assertEqual(lamp_inputs.for_step(self.run, 8), (old_sha, old))
        old_guard = loop.charter_line(next(g for g in old['guardians'] if g['id'] == 'moon')['charter_text'], 'guards against')
        reply = {'vetoes': [{'target': 'A', 'quote': old_guard, 'why': 'Evidence.'}]}
        driver.check('moon', reply, 'set-review', {}, old)
        with self.assertRaisesRegex(ValueError, 'guards-against'):
            driver.check('moon', reply, 'set-review', {}, new)
        driver.image_review(10, 'redo-review',
                            {'moon': {'contact': str(self.fixture / 'final/spritesheet.webp')}}, {}, {})
        for call in self.calls():
            context = json.JSONDecoder().raw_decode(call['prompt'].split('Context:\n', 1)[1])[0]
            self.assertEqual(context['owner_charters'], {g['id']: g for g in old['guardians']})

    def test_restart_partial_style_decision_after_refresh_cli(self):
        for guardian in self.inputs['guardians']:
            guardian['charter_text'] += '\n- **Georgian thread**: old frozen field.'
        driver = self.driver()
        execute = lamp.execute
        def legacy_execute(run, job, validate=None):
            if job['round'] == 5:
                job.pop('inputs_sha256')
            return execute(run, job, validate)
        with patch.object(lamp, 'execute', side_effect=legacy_execute), patch.dict(os.environ,
                {'FAKE_STYLE_TRANSPORT_ERROR': '1'}):
            with self.assertRaisesRegex(RuntimeError, '5 job'):
                driver.run_plan()
        self.assertEqual(len(list(self.run.glob('jobs/005/*.json'))), 6)
        self.assertEqual(len(list(self.run.glob('replies/005/*.json'))), 1)
        # These old votes would reject every style if accidentally consumed on resume.
        for path in self.run.glob('records/005/*.json'):
            record = loop.load(path)
            record['reply']['flags'] = [{'target': sid, 'why': 'Old charter objection.'}
                                        for sid in record['reply']['ranking']]
            loop.save(path, record)
        loop.write_atomic(self.run / 'replay/inputs/untouched.txt', 'Historical replay evidence.')
        lamp_compare.compare_run(self.run)
        evidence = {p.relative_to(self.run).as_posix(): p.read_bytes()
                    for p in self.run.rglob('*') if p.is_file() and p.name != 'provenance.json'}
        calls = len(self.calls())
        real_repo = Path(__file__).resolve().parents[2]
        command = [sys.executable, '-m', 'factory.taste.codex_lamp', 'refresh-inputs', str(self.run),
                   '--reason', 'Refreshed charters; step 3 started on the old ones.']
        refreshed = subprocess.run(command, cwd=real_repo, capture_output=True, text=True)
        self.assertEqual(refreshed.returncode, 0, refreshed.stderr)
        before = loop.load(self.run / 'provenance.json')
        result = subprocess.run(command + ['--restart-step', '3'], cwd=real_repo, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = json.loads(result.stdout)
        self.assertEqual(event['status'], 'restarted')
        self.assertEqual(event['before'], event['after'])  # refresh was already applied
        self.assertEqual(event['old_steps'], {'3': before['initial']})
        self.assertEqual(len(self.calls()), calls)
        for relative, content in evidence.items():
            moved = any(relative == p or relative.startswith(p + '/') for p in event['artifacts'])
            target = self.run / event['archive'] / relative if moved else self.run / relative
            self.assertEqual(target.read_bytes(), content, relative)
            if moved and not relative.startswith('comparison.'):
                self.assertFalse((self.run / relative).exists(), relative)
        provenance = loop.load(self.run / 'provenance.json')
        self.assertEqual(set(provenance['steps']), {'1', '2'})
        self.assertEqual(len(provenance['restarts'][0]['replies']), 1)
        report = loop.load(self.run / 'comparison.json')
        old = [r for r in report['replies'] if r['stage'] == 'style-decision']
        self.assertEqual(len(old), 1)
        self.assertTrue(all(r['status'] == 'superseded' and r['inputs_sha256'] == before['initial'] for r in old))
        self.assertIn('Superseded — excluded', (self.run / 'comparison.md').read_text())
        driver = self.driver()
        round = driver.round
        def stop_at_briefs(number, *args, **kwargs):
            if number == 6:
                raise RuntimeError('reached fresh briefs')
            return round(number, *args, **kwargs)
        with patch.object(driver, 'round', side_effect=stop_at_briefs):
            with self.assertRaisesRegex(RuntimeError, 'reached fresh briefs'):
                driver.run_plan()
        new_calls = self.calls()[calls:]
        self.assertEqual(len(new_calls), 6)
        self.assertTrue(all('style-decision-' in c['work'] for c in new_calls))
        for path in self.run.glob('jobs/005/*.json'):
            job = loop.load(path)
            self.assertEqual(job['inputs_sha256'], before['current'])
            self.assertNotIn('**Georgian thread**', job['prompt'])
        self.assertTrue(loop.load(self.run / 'decisions/style.json')['selected'])

    def test_restart_same_revision_excludes_pairs_and_uncollected_replies(self):
        driver = self.driver()
        rule = lamp.schema.obj({'why': lamp.S})
        driver.round(5, 'choice', ['moon'], 'Old task.', {}, rule, compare=True)
        (self.run / 'records/005/choice-moon-m1.json').unlink()  # interrupted collection
        with patch.object(loop, 'guardians', return_value=self.inputs['guardians']):
            lamp_inputs.refresh(self.run, 'Restart the same inputs.', 3)
        self.driver().round(5, 'choice', ['moon'], 'New task.', {}, rule, compare=True)
        lamp_compare.compare_run(self.run)
        report = loop.load(self.run / 'comparison.json')
        self.assertEqual(len(report['replies']), 4)
        self.assertEqual(len(report['comparisons']), 1)
        old = [r for r in report['replies'] if r['status'] == 'superseded']
        self.assertEqual({r['previous_status'] for r in old}, {'valid', 'uncollected'})
        self.assertEqual(sum(r['jobs'] for r in report['seats']), 2)
        self.assertEqual(sum(r['superseded'] for r in report['seats']), 2)
        self.assertTrue(all(r['superseded_reason'] == 'Restart the same inputs.' for r in old))

    def test_restart_boundaries_preserve_all_evidence_and_recover_interrupted_moves(self):
        for number in range(1, 8):
            with self.subTest(step=number):
                self.run = self.case / f'run-{number}'
                self.run.mkdir()
                self.driver()
                for round in range(1, 11):
                    job = dict(id=f'job-{round}', round=round, attempt=0)
                    loop.save(self.run / 'jobs' / f'{round:03}' / f'job-{round}.json', job)
                    loop.save(self.run / 'dispatch' / f'job-{round}-scratch' / f'{round:03}' / 'work.json', job)
                    for kind in ('costs', 'retries', 'rejections'):
                        loop.save(self.run / kind / f'{round:03}' / f'job-{round}.json', job)
                for kind in ('pilot', 'set', 'redo', 'maker'):
                    loop.save(self.run / 'hatches' / f'{kind}-moon' / 'request.json', {'kind': kind})
                loop.save(self.run / 'decisions/image-resumes/000001.json', {'later': True})
                loop.save(self.run / 'decisions/maker-image-resumes/000001.json', {'later': True})
                for name in lamp_restart.DECISION_STEPS:
                    loop.save(self.run / 'decisions' / (name + '.json'), {'selected': ['old']})
                loop.save(self.run / 'summary.json', {'status': 'complete'})
                loop.save(self.run / 'replay/jobs/001/keep.json', {'historical': True})
                evidence = {p.relative_to(self.run).as_posix(): p.read_bytes()
                            for p in self.run.rglob('*') if p.is_file()}
                old = lamp_inputs.provenance(self.run)
                rename = Path.rename
                moved = []
                def interrupt(source, target):
                    if len(moved) == 2:
                        raise OSError('interrupted archive')
                    moved.append(source)
                    return rename(source, target)
                with patch.object(loop, 'guardians', return_value=self.inputs['guardians']), \
                        patch.object(Path, 'rename', interrupt):
                    with self.assertRaisesRegex(OSError, 'interrupted archive'):
                        lamp_inputs.refresh(self.run, 'Restart after interruption.', number)
                self.assertIn('pending_restart', loop.load(self.run / 'provenance.json'))
                recovered = lamp_inputs.provenance(self.run)
                self.assertNotIn('pending_restart', recovered)
                event = recovered['restarts'][0]
                self.assertEqual(recovered['steps'], {k: v for k, v in old['steps'].items() if int(k) < number})
                for relative, content in evidence.items():
                    archived = any(relative == p or relative.startswith(p + '/') for p in event['artifacts'])
                    target = self.run / event['archive'] / relative if archived else self.run / relative
                    self.assertEqual(target.read_bytes(), content, relative)
                for round in range(1, 11):
                    # Step 1 owns rounds 1–4; step 2 has only pilots, and 6 only set hatches.
                    owner = 1 if round <= 4 else 3 if round == 5 else 4 if round == 6 else 5 if round <= 8 else 7
                    self.assertEqual((self.run / 'jobs' / f'{round:03}').exists(), owner < number)
                for kind, owner in (('pilot', 2), ('set', 6), ('redo', 7), ('maker', 7)):
                    self.assertEqual((self.run / 'hatches' / f'{kind}-moon').exists(), owner < number)
                for name, owner in (('shortlist-0', 1), ('shortlist-1', 1), ('style', 3),
                                    ('reference', 3), ('briefs', 5), ('images', 7),
                                    ('makers-call', 7), ('maker-images', 7)):
                    self.assertEqual((self.run / 'decisions' / (name + '.json')).exists(), owner < number)
                self.assertFalse((self.run / 'decisions/image-resumes').exists())
                self.assertFalse((self.run / 'decisions/maker-image-resumes').exists())
                self.assertFalse((self.run / 'summary.json').exists())
                self.assertEqual(lamp_inputs.provenance(self.run), recovered)

    def test_refresh_and_restart_together_keep_retries_and_repeated_archives(self):
        driver = self.driver()
        rule = lamp.schema.obj({'why': lamp.S})
        driver.round(1, 'earlier', ['moon'], 'Preserved task.', {}, rule)
        with patch.dict(os.environ, {'FAKE_BAD_REPLY': 'choice-moon'}):
            driver.round(5, 'choice', ['moon'], 'Old task.', {}, rule, compare=True)
        # A malformed final answer from an interrupted repair must also survive reporting.
        (self.run / 'replies/005/choice-moon-m0.retry.json').write_text('unfinished JSON {')
        (self.run / 'records/005/choice-moon-m0.json').unlink()
        guardians = json.loads(json.dumps(self.inputs['guardians']))
        guardians[0]['charter_text'] += '\nRevised charter.'
        with patch.object(loop, 'guardians', return_value=guardians):
            event = lamp_inputs.refresh(self.run, 'Refresh and restart together.', 3)
            provenance = loop.load(self.run / 'provenance.json')
            self.assertNotEqual(event['before'], event['after'])
            self.assertEqual(provenance['refreshes'][-1]['preserved_steps'], {'1': provenance['initial']})
            first_archive = self.run / event['archive']
            self.assertTrue(list(first_archive.glob('retries/005/*.json')))
            self.assertTrue(list(first_archive.glob('rejections/005/*.json')))
            original = {p: p.read_bytes() for p in first_archive.rglob('*') if p.is_file()}
            report = loop.load(self.run / 'comparison.json')
            old = [r for r in report['replies'] if r['status'] == 'superseded']
            self.assertEqual(len(old), 4)
            self.assertTrue(any(r.get('raw_reply') == 'unfinished JSON {' for r in old))
            self.driver().round(5, 'choice', ['moon'], 'Fresh task.', {}, rule)
            again = lamp_inputs.refresh(self.run, 'Restart again.', 3)
            self.assertNotEqual(again['archive'], event['archive'])
            self.assertEqual({p: p.read_bytes() for p in original}, original)
            report = loop.load(self.run / 'comparison.json')
            self.assertEqual(sum(r['status'] == 'superseded' for r in report['replies']), 5)

    def test_restart_rejects_invalid_step_or_reason_without_changing_inputs(self):
        self.driver()
        before = {p: p.read_bytes() for p in self.run.rglob('*') if p.is_file()}
        for number in (0, 8, -1, True, '3'):
            with self.assertRaisesRegex(ValueError, 'between 1 and 7'):
                lamp_inputs.refresh(self.run, 'Reason.', number)
        with self.assertRaisesRegex(ValueError, 'nonempty'):
            lamp_inputs.refresh(self.run, ' ', 3)
        self.assertEqual({p: p.read_bytes() for p in self.run.rglob('*') if p.is_file()}, before)

    def test_refresh_cannot_change_a_locked_run(self):
        self.driver()
        before = {p.relative_to(self.run): p.read_bytes() for p in self.run.rglob('*') if p.is_file()}
        command = [sys.executable, '-m', 'factory.taste.codex_lamp', 'refresh-inputs', str(self.run)]
        with lamp.locked(self.run):
            result = subprocess.run(command, cwd=Path(__file__).resolve().parents[2],
                                    capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('another driver is using', result.stderr)
        self.assertTrue(all((self.run / p).read_bytes() == data for p, data in before.items()))
        self.assertFalse((self.run / 'provenance.json').exists())

    def test_motion_guidance_failure_retries_once_with_active_attempt_and_keeps_evidence(self):
        driver = self.driver()
        key = 'pilot-motion'
        with patch.dict(os.environ, {'FAKE_MOTION_FAILURE': '1'}):
            old = lamp_hatch.hatch(driver, key, 'medea', {}, {}, None, None)
        self.assertEqual(old['status'], 'failed')
        old['worker_policy'] = 2
        self.assertFalse(lamp_hatch.retryable_pilot({**old, 'reason': old['reason'] + ' Clipping also failed.'}))
        loop.save(self.run / 'hatches' / key / 'result.json', old)
        evidence = {p: p.read_bytes() for p in Path(old['work']).rglob('*') if p.is_file()}
        with patch.object(lamp_hatch, 'validate', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                lamp_hatch.hatch(driver, key, 'medea', {}, {}, None, None)
        before = len(self.calls())
        result = lamp_hatch.hatch(driver, key, 'medea', {}, {}, None, None)
        self.assertEqual(result['status'], 'validated')
        self.assertNotEqual(result['work'], old['work'])
        self.assertEqual(loop.load(Path(result['resumed_from'])), old)
        self.assertTrue(all(p.read_bytes() == data for p, data in evidence.items()))
        provenance = loop.load(Path(result['package']) / 'provenance.json')
        self.assertEqual(provenance['motion_guidance_difference'], old['reason'])
        self.assertEqual(provenance['motion_policy'], lamp_hatch.MOTION_POLICY)
        lamp_hatch.hatch(driver, key, 'medea', {}, {}, None, None)
        self.assertEqual(len(self.calls()), before)
        for status in ('failed', 'refused'):
            self.assertFalse(lamp_hatch.retryable_pilot({**old, 'status': status, 'worker_policy': 3}))

    def test_motion_numbers_do_not_gate_but_actual_skill_failures_do(self):
        driver = self.driver()
        # The real validators accept the fixture's 30px jump despite the style's 10–14px.
        style = {'rows': {'jumping': 'Rise 10–14 pixels.'}}
        with patch.dict(os.environ, {'FAKE_MOTION_FAILURE': 'with-atlas'}):
            result = lamp_hatch.hatch(driver, 'pilot-guidance', 'medea', style, {}, None, None)
        self.assertEqual(result['status'], 'validated')
        self.assertIn('Only the skill\'s validators gate a pet', self.calls()[-1]['prompt'])
        self.assertIn('31 pixels', loop.load(Path(result['package']) / 'provenance.json')['motion_guidance_difference'])
        with patch.dict(os.environ, {'FAKE_MOTION_FAILURE': 'with-atlas', 'FAKE_FAIL': 'medea'}):
            result = lamp_hatch.hatch(driver, 'set-bad-atlas', 'medea', style, {}, None, None)
        self.assertEqual(result['status'], 'failed')
        self.assertIn('validate_atlas.py failed', result['reason'])

    def test_resume_unfinished_model_pair_uses_the_original_prompt(self):
        driver = self.driver()
        rule = lamp.schema.obj({'why': lamp.S})
        driver.round(1, 'test', ['moon'], 'Old frozen task.', {}, rule)
        record = (self.run / 'records/001/test-moon-m0.json').read_bytes()
        driver.round(1, 'test', ['moon'], 'New unattended task.', {}, rule, compare=True)
        calls = self.calls()
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0]['prompt'], calls[1]['prompt'])
        self.assertEqual((self.run / 'records/001/test-moon-m0.json').read_bytes(), record)

    def test_pilot_migration_is_bounded_and_survives_interrupted_completion(self):
        driver = self.driver()
        for blocker in ('reference', 'frames', 'looks', 'clarification'):
            key = 'pilot-' + blocker
            with self.subTest(blocker=blocker), patch.dict(os.environ, {'FAKE_PILOT_BLOCKER': blocker}):
                old = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
                evidence = self.legacy_failure(old)
                failed = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
                before = len(self.calls())
                self.assertEqual(lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None), failed)
                self.assertEqual(len(self.calls()), before)
                self.assertTrue(all(p.read_bytes() == data for p, data in evidence.items()))
        key = 'pilot-interrupted'
        with patch.dict(os.environ, {'FAKE_PILOT_BLOCKER': 'reference'}):
            old = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        self.legacy_failure(old)
        with patch.object(lamp_hatch, 'validate', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        before = len(self.calls())
        result = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        self.assertEqual(result['status'], 'validated')
        self.assertEqual(len(self.calls()), before)
        self.assertEqual(len(list((self.run / 'hatches' / key).glob('attempt-*'))), 2)

    def test_migration_never_retries_refusals_generated_or_unrelated_failures(self):
        driver = self.driver()
        for case in ('provider-event', 'refused-reply', 'refused-repair', 'refused-result',
                     'generated', 'unrelated', 'set-pet'):
            with self.subTest(case=case):
                key = 'set-moon' if case == 'set-pet' else 'pilot-' + case
                base = self.run / 'hatches' / key
                work = base / 'attempt-old'
                work.mkdir(parents=True)
                record = dict(key=key, pet='moon', model=driver.model, effort=driver.effort,
                              status='failed', reason='Required family reference is null.',
                              image_generations=0, repairs=[], work=str(work))
                if case == 'generated':
                    record['image_generations'] = 1
                elif case == 'unrelated':
                    record['reason'] = 'Image tool is unavailable.'
                elif case == 'refused-result':
                    record['status'] = 'refused'
                elif case.startswith('refused-'):
                    name = 'reply.retry.json' if case == 'refused-repair' else 'reply.json'
                    loop.save(work / name, {'status': 'refused'})
                elif case == 'provider-event':
                    (work / 'codex.jsonl').write_text(json.dumps({'type': 'error', 'code': 'content_policy_violation'}))
                loop.save(base / 'result.json', record)
                result = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
                self.assertEqual(result['status'], 'refused' if case.startswith(('provider-', 'refused-')) else 'failed')
                self.assertFalse(self.log.exists())

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

    def test_invalid_reply_retries_with_reason_once(self):
        job = dict(id='invalid-first', round=1, attempt=0, role='guardian', stage='test',
                   guardian='moon', model='primary-test', effort='high', images=[],
                   prompt='Only this seat prompt.', reply_schema=lamp.schema.obj({'why': lamp.S}))
        with patch.dict(os.environ, {'FAKE_BAD_REPLY': 'invalid-first'}):
            record = lamp.execute(self.run, job)
        self.assertEqual(record['attempt'], 1)
        calls = self.calls()
        self.assertEqual(len(calls), 2)
        self.assertTrue(calls[1]['prompt'].startswith(calls[0]['prompt']))
        self.assertIn('$.why: missing', calls[1]['prompt'])
        self.assertTrue((self.run / 'rejections/001/invalid-first-0.json').exists())
        lamp.execute(self.run, job)
        self.assertEqual(len(self.calls()), 2)

    def test_transport_keeps_full_checks_and_does_not_mutate_frozen_schema(self):
        rule = lamp.schema.obj({'ranking': lamp.schema.array({'type': 'string', 'enum': ['A', 'B']}, 2, True),
            'veto': lamp_compare.nullable(lamp.schema.obj({'why': lamp.S})),
            'count': {'type': 'integer', 'minimum': 0, 'maximum': 3}})
        before = json.dumps(rule)
        wire = lamp.schema.transport(rule)
        check_strict(wire)
        self.assertEqual(json.dumps(rule), before)
        self.assertIn('anyOf', wire['properties']['veto'])
        self.assertEqual(wire['properties']['veto']['anyOf'][1], {'type': 'null'})
        bad = {'ranking': ['A', 'A'], 'veto': None, 'count': -1}
        # The wire schema admits duplicate entries; the frozen full schema rejects them.
        self.assertNotIn('uniqueItems', wire['properties']['ranking'])
        self.assertEqual(lamp.schema.validate(bad['ranking'], wire['properties']['ranking']), [])
        self.assertEqual(lamp.schema.validate(bad, rule), ['$.ranking: repeated item', '$.count: number outside allowed range'])
        for full in (lamp.STYLE, lamp.BRIEF, lamp_hatch.RESULT):
            check_strict(lamp.schema.transport(full))
        with self.assertRaisesRegex(AssertionError, 'unsupported keywords'):
            check_strict(rule)

    def test_duplicate_ranking_repair_and_terminal_invalid_do_not_block_round(self):
        driver = self.driver()
        candidates = {'A': {}, 'B': {}}
        rule = lamp.ballot_schema(list(candidates))
        with patch.dict(os.environ, {'FAKE_REPEAT_RANKING': 'shortlist-test-painter', 'FAKE_INVALID_TWICE': '1'}):
            votes = driver.round(2, 'shortlist-test', ['painter', 'moon'], 'Rank all IDs.',
                                 {'candidates': candidates}, rule, compare=True)
        self.assertEqual(set(votes), {'moon'})
        selected = driver.tally('test', candidates, votes, 1)
        self.assertEqual(selected, ['A'])
        invalid = loop.load(self.run / 'records/002/shortlist-test-painter-m0.json')
        self.assertEqual((invalid['status'], invalid['attempt']), ('invalid', 1))
        self.assertEqual(invalid['errors'], ['$.ranking: repeated item'])
        self.assertEqual(len(invalid['costs']), 2)
        calls = self.calls()
        self.assertEqual(len(calls), 6)
        for call in calls:
            if call['work'].endswith('-1'):
                self.assertIn('$.ranking: repeated item', call['prompt'])
        driver.round(2, 'shortlist-test', ['painter', 'moon'], 'Rank all IDs.',
                     {'candidates': candidates}, rule, compare=True)
        self.assertEqual(len(self.calls()), len(calls))
        lamp_compare.compare_run(self.run)
        report = loop.load(self.run / 'comparison.json')
        self.assertEqual(len(report['replies']), 4)
        self.assertEqual(len(report['comparisons']), 1)
        self.assertEqual(report['comparisons'][0]['guardian'], 'moon')
        self.assertEqual(sum(s['invalid'] for s in report['seats']), 2)
        with patch.dict(os.environ, {'FAKE_REPEAT_RANKING': 'shortlist-repair-painter'}):
            repaired = driver.round(3, 'shortlist-repair', ['painter'], 'Rank all IDs.',
                                    {'candidates': candidates}, rule)
        self.assertEqual(repaired['painter']['ranking'], ['A', 'B'])
        self.assertEqual(loop.load(self.run / 'records/003/shortlist-repair-painter-m0.json')['attempt'], 1)

    def test_resume_after_strict_rejection_preserves_legacy_completions(self):
        driver = self.driver()
        with patch.dict(os.environ, {'FAKE_SHORTLIST_TRANSPORT_ERROR': '1'}):
            with self.assertRaisesRegex(RuntimeError, '12 job'):
                driver.run_plan()
        # Pre-fix records have no status/errors fields; their job hash is unchanged.
        for path in self.run.glob('records/*/*.json'):
            record = loop.load(path)
            record.pop('status')
            record.pop('errors')
            loop.save(path, record)
        completed = {p: p.read_bytes() for folder in ('records', 'replies', 'jobs')
                     for p in (self.run / folder).glob('*/*.json')}
        self.assertEqual(len(list(self.run.glob('records/*/*.json'))), 42)
        before = len(self.calls())
        with patch.object(driver, 'hatch_many', side_effect=RuntimeError('reached pilots')):
            with self.assertRaisesRegex(RuntimeError, 'reached pilots'):
                driver.run_plan()
        self.assertTrue(all(p.read_bytes() == data for p, data in completed.items()))
        self.assertEqual(len(self.calls()) - before, 12)
        self.assertTrue(all('shortlist-' in call['work'] for call in self.calls()[before:]))

    def test_replay_invalid_reply_is_recorded_and_excluded_from_comparison(self):
        real_repo = Path(__file__).resolve().parents[2]
        with patch.object(loop, 'REPO', real_repo), patch.dict(os.environ,
                {'FAKE_REPEAT_ALSO': 'chapter-6-moon-m0', 'FAKE_INVALID_TWICE': '1'}):
            result = lamp_compare.replay_run(self.run, ['chapter-6'], ['primary-test'], 'high', 4)
        self.assertEqual(result['replayed_jobs'], 19)
        record = loop.load(self.run / 'replay/records/001/chapter-6-moon-m0.json')
        self.assertEqual(record['status'], 'invalid')
        self.assertEqual(record['errors'], ['$.also: repeated item'])
        lamp_compare.compare_run(self.run)
        report = loop.load(self.run / 'comparison.json')
        self.assertEqual(len(report['replies']), 38)
        self.assertEqual(len(report['comparisons']), 18)

    def test_worker_report_is_repaired_once_without_losing_original(self):
        driver = self.driver()
        for key, twice in [('repair-moon', ''), ('invalid-moon', '1')]:
            with self.subTest(key=key), patch.dict(os.environ, {'FAKE_BAD_WORKER': key, 'FAKE_INVALID_TWICE': twice}):
                result = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
            self.assertEqual(result['status'], 'invalid' if twice else 'validated')
            work = Path(result['work'])
            self.assertEqual(loop.load(work / 'reply.json')['image_generations'], -1)
            self.assertIn('$.image_generations: number outside allowed range', (work / 'prompt.retry.txt').read_text())
            before = len(self.calls())
            self.assertEqual(lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None), result)
            self.assertEqual(len(self.calls()), before)
        self.assertEqual(len(self.calls()), 4)

    def test_invalid_briefs_and_failed_brief_repairs_withhold_pets(self):
        driver = self.driver()
        hatches = []
        def hatch_many(items):
            hatches.extend(items)
            return [dict(key=item['key'], pet=item['pet'],
                         status='validated' if item['key'].startswith('pilot-') else 'failed',
                         contact=str(self.fixture / 'final/spritesheet.webp')) for item in items]
        with patch.object(driver, 'hatch_many', side_effect=hatch_many), patch.dict(os.environ,
                {'FAKE_BAD_BRIEF': 'briefs-medea-m0,brief-repair-moon-m0', 'FAKE_BRIEF_REPAIR': 'moon'}):
            summary = driver.run_plan()
        self.assertEqual(len(summary['pets']), 22)
        self.assertEqual(summary['pets']['medea'], 'invalid')
        self.assertEqual(summary['pets']['moon'], 'invalid')
        self.assertEqual(len([h for h in hatches if h['key'].startswith('set-')]), 20)
        self.assertFalse(any(h['key'] in ('set-medea', 'set-moon') for h in hatches))
        self.assertEqual(loop.load(self.run / 'decisions/briefs.json')['invalid'], ['medea', 'moon'])

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

    def test_provider_stops_preserve_history_and_do_not_spend_fresh_attempt(self):
        driver = self.driver()
        key = 'set-moon'
        base = self.run / 'hatches' / key
        def hatch():
            return lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        with patch.dict(os.environ, {'FAKE_PROVIDER_STOP': 'moon'}):
            first = hatch()
            before = {p: p.read_bytes() for p in base.rglob('*') if p.is_file()}
            second = hatch()
        self.assertNotEqual(first['work'], second['work'])
        self.assertEqual(second['fresh_attempts'], 0)
        self.assertEqual(second['failure_kind'], 'provider_stop')
        self.assertTrue(second['provider_stop'])
        self.assertEqual(loop.load(Path(second['resumed_from'])), first)
        for path, data in before.items():
            if path.name != 'active-attempt.json':
                self.assertEqual(path.read_bytes(), data)
        with patch.dict(os.environ, {'FAKE_FAIL': 'moon'}):
            failed = hatch()
        self.assertEqual(failed['fresh_attempts'], 0)
        self.assertEqual(lamp_resume.decision(base)['action'], 'fresh_attempt')
        # A provider stop while trying the fresh attempt also spends no budget.
        with patch.dict(os.environ, {'FAKE_PROVIDER_STOP': 'moon'}):
            stopped = hatch()
        self.assertEqual(stopped['fresh_attempts'], 0)
        with patch.dict(os.environ, {'FAKE_FAIL': 'moon'}):
            fresh = hatch()
        self.assertEqual(fresh['fresh_attempts'], 1)
        self.assertEqual(fresh['status'], 'failed')
        request = loop.load(Path(fresh['work']) / 'driver-request.json')
        self.assertEqual(request['resume']['fresh_attempt_reason'], failed['reason'])
        self.assertIn(failed['reason'], self.calls()[-1]['prompt'])
        calls = len(self.calls())
        self.assertEqual(hatch(), fresh)
        self.assertEqual(len(self.calls()), calls)
        self.assertEqual(len(list(base.glob('attempt-*'))), 5)
        self.assertEqual(len(list(base.glob('resume-results/*.json'))), 4)

    def test_provider_stop_detection_requires_actual_events_without_work(self):
        work = self.case / 'events'
        work.mkdir()
        log = work / 'codex.jsonl'
        def events(error, middle=()):
            values = [{'type': 'thread.started'}, {'type': 'turn.started'}, *middle,
                      {'type': 'error', **error}, {'type': 'turn.failed', 'error': error}]
            log.write_text(''.join(json.dumps(value) + '\n' for value in values))
        for error in ({'message': 'You’ve hit your usage limit.'},
                      {'message': 'Rate limit exceeded; retry later'},
                      {'code': 'server_error', 'message': 'Upstream unavailable'},
                      {'code': 'insufficient_quota', 'message': 'Account quota exhausted'}):
            with self.subTest(error=error):
                events(error)
                self.assertTrue(lamp_resume.stopped_before_work(work))
        for middle in ([{'type': 'item.completed', 'item': {'type': 'image_generation', 'status': 'completed'}}],
                       [{'type': 'item.started', 'item': {'type': 'command_execution'}}],
                       [{'type': 'turn.completed'}]):
            events({'message': 'You’ve hit your usage limit.'}, middle)
            self.assertIsNone(lamp_resume.stopped_before_work(work))
        events({'message': 'codex exec exited 1'})
        self.assertIsNone(lamp_resume.stopped_before_work(work))
        events({'message': 'You’ve hit your usage limit.'})
        log.write_text(log.read_text() + '{truncated')
        self.assertIsNone(lamp_resume.stopped_before_work(work))
        log.unlink()
        loop.save(work / 'reply.json', {'status': 'failed', 'image_generations': 0,
                                     'reason': 'You’ve hit your usage limit.'})
        self.assertIsNone(lamp_resume.stopped_before_work(work))

    def test_set_gate_fresh_attempt_is_once_even_after_interrupted_completion(self):
        driver = self.driver()
        key = 'set-moon'
        with patch.dict(os.environ, {'FAKE_FAIL': 'moon'}):
            old = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        base = self.run / 'hatches' / key
        original = (base / 'result.json').read_bytes()
        with patch.object(lamp_hatch, 'validate', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        calls = len(self.calls())
        pending = lamp_resume.decision(base)
        self.assertFalse(pending['model_call'])
        self.assertIn('finish recorded worker reply', pending['reason'])
        with patch.object(lamp_hatch, 'validate', side_effect=ValueError('quality gate failed again')):
            result = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        self.assertEqual(result['fresh_attempts'], 1)
        self.assertEqual((base / 'result.json').read_bytes(), original)
        self.assertEqual(loop.load(Path(result['resumed_from'])), old)
        self.assertEqual(lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None), result)
        self.assertEqual(len(self.calls()), calls)
        self.assertEqual(len(list(base.glob('attempt-*'))), 2)

    def test_partial_provider_stop_continues_with_existing_budget_and_art(self):
        driver = self.driver()
        key = 'set-moon'
        with patch.dict(os.environ, {'FAKE_FAIL': 'moon'}):
            failed = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        with patch.dict(os.environ, {'FAKE_PROVIDER_STOP_AFTER_ART': 'moon'}):
            stopped = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        self.assertEqual(stopped['fresh_attempts'], 1)
        base = self.run / 'hatches' / key
        self.assertEqual(lamp_resume.decision(base)['action'], 'continue_attempt')
        before = {p: p.read_bytes() for p in Path(stopped['work']).rglob('*') if p.is_file()}
        with patch.dict(os.environ, {'FAKE_FAIL': 'moon'}):
            result = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        self.assertEqual(result['fresh_attempts'], 1)
        self.assertEqual(result['fresh_attempt_reason'], failed['reason'])
        self.assertTrue(all(path.read_bytes() == data for path, data in before.items()))
        self.assertIn('two-repair limit is cumulative', self.calls()[-1]['prompt'])
        self.assertIn('Do not restart the pet', self.calls()[-1]['prompt'])
        calls = len(self.calls())
        self.assertEqual(lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None), result)
        self.assertEqual(len(self.calls()), calls)

    def test_interrupted_fresh_provider_stop_keeps_budget_and_does_not_overwrite_events(self):
        driver = self.driver()
        with patch.dict(os.environ, {'FAKE_FAIL': 'moon'}):
            lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        with patch.dict(os.environ, {'FAKE_PROVIDER_STOP': 'moon'}):
            stopped = lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        base = self.run / 'hatches/set-moon'
        target, _ = lamp_resume.latest_result(base)
        target.unlink()  # Driver died before settling the fresh attempt's provider stop.
        log = Path(stopped['work']) / 'codex.jsonl'
        before = log.read_bytes()
        result = lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        self.assertEqual(result['status'], 'validated')
        self.assertEqual(result['fresh_attempts'], 1)
        self.assertEqual(log.read_bytes(), before)
        self.assertEqual(loop.load(Path(result['resumed_from']))['fresh_attempts'], 0)

    def test_set_worker_gate_failure_gets_feedback_but_redo_does_not_retry(self):
        driver = self.driver()
        for key in ('set-moon', 'redo-moon'):
            with patch.dict(os.environ, {'FAKE_MOTION_FAILURE': '1'}):
                failed = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
            before = len(self.calls())
            result = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
            if key.startswith('set-'):
                self.assertEqual(result['status'], 'validated')
                self.assertEqual(result['fresh_attempts'], 1)
                self.assertIn(failed['reason'], self.calls()[-1]['prompt'])
            else:
                self.assertEqual(result, failed)
                self.assertEqual(len(self.calls()), before)

    def test_refusal_overrides_provider_and_gate_retry_eligibility(self):
        driver = self.driver()
        for kind in ('event', 'reply', 'repair'):
            key = 'set-' + kind
            with patch.dict(os.environ, {'FAKE_PROVIDER_STOP': 'moon'}):
                old = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
            work = Path(old['work'])
            if kind == 'event':
                with (work / 'codex.jsonl').open('a') as handle:
                    handle.write(json.dumps({'type': 'error', 'code': 'content_policy_violation'}) + '\n')
            else:
                loop.save(work / ('reply.retry.json' if kind == 'repair' else 'reply.json'),
                          {'status': 'refused', 'reason': 'Provider refusal.'})
            before = len(self.calls())
            result = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
            self.assertEqual(result['status'], 'refused')
            self.assertEqual(lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None), result)
            self.assertEqual(len(self.calls()), before)

    def test_interrupted_provider_stop_is_recorded_before_retry(self):
        driver = self.driver()
        with patch.dict(os.environ, {'FAKE_PROVIDER_STOP': 'moon'}):
            old = lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        base = self.run / 'hatches/set-moon'
        (base / 'result.json').unlink()  # Crash after process.json, before result.json.
        log = Path(old['work']) / 'codex.jsonl'
        before = log.read_bytes()
        result = lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        self.assertEqual(result['status'], 'validated')
        self.assertEqual(result['fresh_attempts'], 0)
        self.assertEqual(log.read_bytes(), before)
        self.assertEqual(loop.load(Path(result['resumed_from']))['failure_kind'], 'provider_stop')

    def test_repackage_preserves_atlas_old_package_and_all_records_without_calls(self):
        driver = self.driver()
        for kind in ('pilot', 'set', 'redo', 'maker'):
            with self.subTest(kind=kind):
                self.check_repackage(driver, kind + '-moon')

    def check_repackage(self, driver, key):
        old = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        package = Path(old['package'])
        contact_size = (package / 'contact-sheet.webp').stat().st_size
        limit = old['bytes'] - contact_size // 4
        old.update(status='failed', reason=f'package is {old["bytes"]} bytes, exceeds {limit}; no files published')
        loop.save(self.run / 'hatches' / key / 'result.json', old)
        before = {p: p.read_bytes() for p in Path(old['work']).rglob('*') if p.is_file()}
        calls = len(self.calls())
        with patch.object(lamp_hatch, 'LIMIT', limit):
            result = lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        self.assertEqual(result['status'], 'validated', result['reason'])
        self.assertLessEqual(result['bytes'], limit)
        self.assertEqual(result['atlas_sha256'], old['atlas_sha256'])
        self.assertEqual(result['previews'], old['previews'])
        self.assertTrue(all(path.read_bytes() == data for path, data in before.items()))
        self.assertEqual(len(self.calls()), calls)
        self.assertEqual(lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None), result)
        native = Path(result['review_contact'])
        pixels = native.read_bytes()
        native.write_bytes(b'changed jury image')
        with self.assertRaisesRegex(ValueError, 'validated review contact changed'):
            lamp_hatch.hatch(driver, key, 'moon', {}, {}, None, None)
        native.write_bytes(pixels)

    def test_repackage_requires_both_validators_and_never_redraws_after_failure(self):
        driver = self.driver()
        with patch.object(lamp_hatch, 'LIMIT', 1):
            old = lamp_hatch.hatch(driver, 'maker-moon', 'moon', {}, {}, None, None)
        base = self.run / 'hatches/maker-moon'
        for invalid in ({**old, 'validators': {'atlas': old['validators']['atlas']}},
                        {**old, 'failure_kind': 'gate'}, {**old, 'status': 'refused'}):
            loop.save(base / 'result.json', invalid)
            self.assertEqual(lamp_resume.decision(base)['action'], 'keep')
        loop.save(base / 'result.json', old)
        calls = len(self.calls())
        with patch.object(lamp_hatch, 'LIMIT', 1):
            result = lamp_hatch.hatch(driver, 'maker-moon', 'moon', {}, {}, None, None)
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['resume_action'], 'repackage')
        self.assertEqual(lamp_resume.decision(base)['action'], 'keep')
        self.assertEqual(lamp_hatch.hatch(driver, 'maker-moon', 'moon', {}, {}, None, None), result)
        self.assertEqual(len(self.calls()), calls)

    def test_tight_package_budget_keeps_native_jury_contact(self):
        from PIL import Image
        driver = self.driver()
        with patch.object(lamp_hatch, 'LIMIT', 15_000):
            result = lamp_hatch.hatch(driver, 'maker-moon', 'moon', {}, {}, None, None)
        self.assertEqual(result['status'], 'validated', result['reason'])
        self.assertLessEqual(result['bytes'], 15_000)
        with Image.open(result['contact']) as preview, Image.open(result['review_contact']) as native:
            self.assertLess(preview.width, 600)
            self.assertEqual(native.size, (1536, 2530))
        self.assertEqual((Path(result['package']) / 'spritesheet.webp').read_bytes(),
                         (self.fixture / 'final/spritesheet.webp').read_bytes())

    def test_repackage_gate_failure_cannot_spend_a_fresh_drawing_attempt(self):
        driver = self.driver()
        with patch.object(lamp_hatch, 'LIMIT', 1):
            lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        calls = len(self.calls())
        with patch.object(lamp_hatch, 'validate', side_effect=ValueError('validate_pet_quality.py failed; fixture')):
            result = lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['failure_kind'], 'gate')
        self.assertEqual(lamp_resume.decision(self.run / 'hatches/set-moon')['action'], 'keep')
        self.assertEqual(lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None), result)
        self.assertEqual(len(self.calls()), calls)

    def test_completed_redo_size_failure_still_repackages_and_gets_its_final_review(self):
        driver = self.driver()
        briefs = {'moon': {}}
        loop.save(self.run / 'decisions/briefs.json', {'briefs': briefs, 'style': {}})
        original = lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        with patch.dict(os.environ, {'FAKE_REDO': 'moon'}), patch.object(lamp_hatch, 'LIMIT', 1):
            first = lamp_images.finish(driver, [original], briefs, {}, None, set())
        self.assertEqual(first['moon']['key'], 'redo-moon')
        self.assertEqual(first['moon']['failure_kind'], 'package')
        before = {p: p.read_bytes() for p in self.run.rglob('*')
                  if p.is_file() and p.name != 'active-attempt.json'}
        listing = lamp_resume.listing(self.run)
        self.assertEqual(listing['local_repackages'], 1)
        self.assertEqual(listing['model_hatches'], 0)
        calls = len(self.calls())
        result = lamp_images.finish(driver, [original], briefs, {}, None, set())
        self.assertEqual(result['moon']['status'], 'validated')
        self.assertEqual(result['moon']['atlas_sha256'], first['moon']['atlas_sha256'])
        self.assertEqual(len(self.calls()) - calls, 6)
        self.assertTrue(all('/hatches/' not in call['work'] for call in self.calls()[calls:]))
        self.assertTrue(all(p.read_bytes() == data for p, data in before.items()))
        self.assertEqual(lamp_images.finish(driver, [original], briefs, {}, None, set()), result)
        self.assertEqual(len(self.calls()) - calls, 6)

    def test_list_resume_cli_is_read_only_and_agrees_with_dispatch(self):
        driver = self.driver()
        with patch.dict(os.environ, {'FAKE_PROVIDER_STOP': 'moon'}):
            lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        with patch.dict(os.environ, {'FAKE_FAIL': 'scholar'}):
            lamp_hatch.hatch(driver, 'set-scholar', 'scholar', {}, {}, None, None)
        with patch.dict(os.environ, {'FAKE_REFUSE': 'snow-queen'}):
            lamp_hatch.hatch(driver, 'set-snow-queen', 'snow-queen', {}, {}, None, None)
        lamp_hatch.hatch(driver, 'set-medea', 'medea', {}, {}, None, None)
        loop.save(self.run / 'decisions/briefs.json', {'briefs': {'painter': {}}})
        # Listing must work without an installed generation skill or current config.
        config = loop.load(self.run / 'run.json')
        loop.save(self.run / 'run.json', {**config, 'skill_dir': '/missing-skill'})
        before = {p: p.read_bytes() for p in self.run.rglob('*') if p.is_file()}
        calls = len(self.calls())
        result = subprocess.run([sys.executable, '-m', 'factory.taste.codex_lamp', 'list-resume', str(self.run)],
                                cwd=Path(__file__).resolve().parents[2], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        listing = json.loads(result.stdout)
        self.assertEqual(listing['model_hatches'], 3)
        self.assertEqual({h['key']: h['action'] for h in listing['hatches']}, {
            'set-moon': 'provider_retry', 'set-scholar': 'fresh_attempt', 'set-snow-queen': 'keep',
            'set-medea': 'keep', 'set-painter': 'run'})
        self.assertEqual({p: p.read_bytes() for p in self.run.rglob('*') if p.is_file()}, before)
        self.assertEqual(len(self.calls()), calls)
        for item in listing['hatches']:
            pet = item['key'].removeprefix('set-')
            lamp_hatch.hatch(driver, item['key'], pet, {}, {}, None, None)
        self.assertEqual(len(self.calls()) - calls, listing['model_hatches'])

    def test_expanded_image_review_keeps_prior_jobs_and_records(self):
        driver = self.driver()
        old = lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        driver.image_review(9, 'image-review', {'moon': old}, {'moon': {}}, {})
        before = {p: p.read_bytes() for kind in ('jobs', 'records', 'replies')
                  for p in (self.run / kind).rglob('*.json')}
        new = lamp_hatch.hatch(driver, 'set-medea', 'medea', {}, {}, None, None)
        candidates = {'moon': old, 'medea': new}
        reviews = driver.image_review(9, 'image-review', candidates, {'moon': {}, 'medea': {}}, {})
        self.assertEqual(len(reviews), 6)
        for review in reviews.values():
            self.assertEqual({v['target'] for v in review['verdicts']}, set(candidates))
        self.assertTrue(all(p.read_bytes() == data for p, data in before.items()))
        calls = len(self.calls())
        driver.image_review(9, 'image-review', candidates, {'moon': {}, 'medea': {}}, {})
        self.assertEqual(len(self.calls()), calls)

    def test_completed_step_seven_expands_without_changing_spent_redos(self):
        driver = self.driver()
        new_pets = ('storybook', 'painter', 'bible-school-teacher')
        briefs = dict.fromkeys(('medea', 'baba-yaga', 'bulat-okudzhava', *new_pets), {})
        loop.save(self.run / 'decisions/briefs.json', {'briefs': briefs, 'style': {}, 'reference': None})
        items = [dict(key='set-' + p, pet=p, style={}, brief={}, reference=None, redo=None) for p in briefs]
        with patch.dict(os.environ, {'FAKE_FAIL': ','.join(new_pets),
                                     'FAKE_REDO': 'baba-yaga,bulat-okudzhava',
                                     'FAKE_FINAL_REJECT': 'baba-yaga'}):
            originals = driver.hatch_many(items)
            first = lamp_images.finish(driver, originals, briefs, {}, None, set())
        self.assertEqual(first['baba-yaga']['status'], 'rejected')
        self.assertEqual(first['bulat-okudzhava']['key'], 'redo-bulat-okudzhava')
        self.assertEqual(first['painter']['status'], 'failed')
        first_bytes = (self.run / 'decisions/images.json').read_bytes()
        originals = driver.hatch_many(items)  # The three fresh attempts now validate.
        candidates = {p['pet']: p for p in originals}
        # Reproduce the old driver: expanded jury changes old redo requests; an
        # independent new redo can finish before parallel_map reports the error.
        with patch.dict(os.environ, {'FAKE_REDO': 'baba-yaga,bulat-okudzhava,bible-school-teacher',
                                     'FAKE_REVIEW_REASON': 'New expanded jury reasons.'}):
            reviews = driver.image_review(9, 'image-review', candidates, briefs, {})
        redos = driver.redos(reviews)
        with self.assertRaisesRegex(ValueError, 'frozen input differs'):
            lamp_hatch.hatch(driver, 'redo-bulat-okudzhava', 'bulat-okudzhava', {}, {}, None,
                             {'previous': candidates['bulat-okudzhava'], 'reasons': redos['bulat-okudzhava']})
        teacher = lamp_hatch.hatch(driver, 'redo-bible-school-teacher', 'bible-school-teacher', {}, {}, None,
                                  {'previous': candidates['bible-school-teacher'],
                                   'reasons': redos['bible-school-teacher']})
        self.assertEqual(teacher['status'], 'validated')
        before = {p: p.read_bytes() for p in self.run.rglob('*') if p.is_file()}
        listing = lamp_resume.listing(self.run)
        self.assertEqual(listing['model_hatches'], 0)
        self.assertEqual(listing['images']['pending'], list(new_pets))
        self.assertEqual(listing['images']['jury_calls'], 6)
        self.assertEqual(listing['images']['redos']['bible-school-teacher']['action'], 'keep')
        self.assertTrue(all(p.read_bytes() == data for p, data in before.items()))
        calls = len(self.calls())
        result = lamp_images.finish(driver, originals, briefs, {}, None, set())
        self.assertEqual(len(self.calls()) - calls, 6)
        for call in self.calls()[calls:]:
            context = json.JSONDecoder().raw_decode(call['prompt'].split('Context:\n', 1)[1])[0]
            self.assertEqual(list(context['candidates']), ['bible-school-teacher'])
        for pet in ('medea', 'baba-yaga', 'bulat-okudzhava'):
            self.assertEqual(result[pet], first[pet])
        self.assertTrue(all(result[p]['status'] == 'validated' for p in new_pets))
        self.assertFalse((self.repo / 'factory/pets/baba-yaga').exists())
        self.assertEqual((self.run / 'decisions/images.json').read_bytes(), first_bytes)
        self.assertTrue(all(p.read_bytes() == data for p, data in before.items()))
        addition = loop.load(self.run / 'decisions/image-resumes/000001.json')
        self.assertEqual(set(addition['pets']), set(new_pets))
        self.assertEqual(set(addition['redos']), {'bible-school-teacher'})
        lamp_images.finish(driver, originals, briefs, {}, None, set())
        self.assertEqual(len(self.calls()) - calls, 6)
        # Skipping spent work must not silently accept a genuinely edited request.
        request_path = self.run / 'hatches/redo-bulat-okudzhava/request.json'
        changed = loop.load(request_path)
        saved = dict(changed)
        changed['brief'] = {'changed': True}
        loop.save(request_path, changed)
        with self.assertRaisesRegex(ValueError, 'frozen input differs'):
            lamp_images.finish(driver, originals, briefs, {}, None, set())
        loop.save(request_path, saved)
        job_path = next(self.run.glob('jobs/009/*.json'))
        job = loop.load(job_path)
        job['prompt'] += '\nChanged completed input.'
        loop.save(job_path, job)
        with self.assertRaisesRegex(ValueError, 'job changed after completion'):
            lamp_images.finish(driver, originals, briefs, {}, None, set())

    def test_new_candidates_only_and_interrupted_publication_keep_the_decision(self):
        driver = self.driver()
        briefs = {'moon': {}, 'scholar': {}}
        with patch.dict(os.environ, {'FAKE_FAIL': 'scholar', 'FAKE_REDO': 'moon', 'FAKE_FINAL_REJECT': 'moon'}):
            originals = [lamp_hatch.hatch(driver, 'set-' + p, p, {}, {}, None, None) for p in briefs]
            first = lamp_images.finish(driver, originals, briefs, {}, None, set())
        originals[1] = lamp_hatch.hatch(driver, 'set-scholar', 'scholar', {}, {}, None, None)
        calls = len(self.calls())
        with patch.dict(os.environ, {'FAKE_REDO': 'moon,scholar'}), \
                patch.object(lamp_hatch, 'publish', side_effect=OSError('publication interrupted')):
            with self.assertRaisesRegex(OSError, 'publication interrupted'):
                lamp_images.finish(driver, originals, briefs, {}, None, set())
        self.assertEqual(len(self.calls()) - calls, 13)  # Review, one new redo, final review.
        for call in self.calls()[calls:]:
            if '/hatches/' in call['work']:
                self.assertIn('/redo-scholar/', call['work'])
            else:
                context = json.JSONDecoder().raw_decode(call['prompt'].split('Context:\n', 1)[1])[0]
                self.assertEqual(list(context['candidates']), ['scholar'])
        decision = self.run / 'decisions/image-resumes/000001.json'
        before = decision.read_bytes()
        result = lamp_images.finish(driver, originals, briefs, {}, None, set())
        self.assertEqual(result['moon'], first['moon'])
        self.assertEqual(result['scholar']['status'], 'validated')
        self.assertEqual(decision.read_bytes(), before)
        self.assertEqual(len(self.calls()) - calls, 13)
        self.assertTrue((self.repo / 'factory/pets/scholar/spritesheet.webp').exists())

    def test_pending_review_recovers_partial_ballots_and_rejects_changed_inputs(self):
        driver = self.driver()
        pet = lamp_hatch.hatch(driver, 'set-moon', 'moon', {}, {}, None, None)
        driver.image_review(9, 'image-review', {'moon': pet}, {'moon': {}}, {}, seats=driver.jury(3)[:2])
        invalid_path = next(self.run.glob('records/009/*.json'))
        invalid = loop.load(invalid_path)
        invalid.update(status='invalid', errors=['Terminal invalid ballot fixture.'])
        loop.save(invalid_path, invalid)
        before = {p: p.read_bytes() for kind in ('jobs', 'records', 'replies')
                  for p in (self.run / kind).rglob('*.json')}
        calls = len(self.calls())
        reviews, sources = lamp_images.review(driver, 9, 'image-review', {'moon': pet}, {'moon': {}}, {})
        self.assertEqual(len(reviews), 5)  # Invalid completion is kept and excluded, never called again.
        self.assertEqual(len(sources), 6)
        self.assertEqual(len(self.calls()) - calls, 4)
        self.assertTrue(all(p.read_bytes() == data for p, data in before.items()))
        with self.assertRaisesRegex(ValueError, 'frozen image input differs'):
            lamp_images.review(driver, 9, 'image-review', {'moon': pet}, {'moon': {'changed': True}}, {})

    def test_maker_commission_is_explicit_bounded_and_keeps_lamp_verdicts(self):
        driver = self.driver()
        ids = ('baba-yaga', 'glassblower', 'hedge-witch', 'moon')
        briefs = dict.fromkeys(ids, {})
        originals = driver.hatch_many([dict(key='set-' + p, pet=p, style={}, brief={}, reference=None, redo=None)
                                       for p in ids])
        results = {p['pet']: {**p, 'status': 'rejected', 'reasons': [{'seat': 'painter', 'why': 'Recorded defect.'}]}
                   for p in originals}
        loop.save(self.run / 'decisions/images.json', {'pets': results, 'reviews': {}, 'redos': {}, 'redo_reviews': {}})
        baseline = (self.run / 'decisions/images.json').read_bytes()
        calls = len(self.calls())
        self.assertIsNone(lamp_maker.finish(driver, None, results, briefs, {}, None))
        self.assertEqual(len(self.calls()), calls)
        call_path = self.case / 'makers-call.json'
        (self.case / 'makers-call.md').write_text('My recorded decision, outside the Lamp budget.')
        call = {'version': 1, 'maker': 'Codex', 'statement': 'makers-call.md', 'pets': [
            {'pet': p, 'action': 'leave' if p == 'moon' else 'attempt',
             'reason': 'A named drawing problem.', 'instruction': 'Repair only the named defect.'} for p in ids]}
        loop.save(call_path, call)
        before = {p: p.read_bytes() for p in self.run.rglob('*') if p.is_file()}
        self.assertEqual(lamp_maker.listing(self.run, call_path)['model_hatches'], 3)
        self.assertTrue(all(p.read_bytes() == data for p, data in before.items()))
        with patch.dict(os.environ, {'FAKE_FINAL_REJECT': 'glassblower', 'FAKE_MAKER_FAIL': 'hedge-witch'}):
            final = lamp_maker.finish(driver, call_path, results, briefs, {}, None)
        self.assertEqual({p: r['status'] for p, r in final.items()}, {
            'baba-yaga': 'validated', 'glassblower': 'rejected', 'hedge-witch': 'failed', 'moon': 'left'})
        self.assertEqual(len(self.calls()) - calls, 9)  # Three makers, six jurors.
        for pet in ids[:3]:
            request = loop.load(self.run / 'hatches' / ('maker-' + pet) / 'request.json')
            self.assertEqual(request['maker']['previous'], results[pet])
            self.assertTrue(request['maker']['validator_reports'])
            self.assertEqual(request['maker']['authority'], 'maker')
        provenance = loop.load(self.repo / 'factory/pets/baba-yaga/provenance.json')
        self.assertEqual(provenance['maker_attempt_count'], 1)
        self.assertEqual(provenance['redo_count'], 0)
        self.assertFalse((self.repo / 'factory/pets/glassblower').exists())
        self.assertFalse((self.repo / 'factory/pets/hedge-witch').exists())
        self.assertEqual((self.run / 'decisions/images.json').read_bytes(), baseline)
        self.assertEqual(lamp_maker.finish(driver, None, results, briefs, {}, None), final)
        self.assertEqual(len(self.calls()) - calls, 9)
        self.assertEqual(lamp_maker.listing(self.run, None)['model_hatches'], 0)
        call['pets'][0]['instruction'] = 'A different instruction.'
        loop.save(call_path, call)
        with self.assertRaisesRegex(ValueError, 'frozen maker call differs'):
            lamp_maker.finish(driver, call_path, results, briefs, {}, None)

    def test_completed_maker_size_failure_repackages_then_resumes_only_its_missing_jury(self):
        driver = self.driver()
        driver.image_workers = 1
        ids = ('baba-yaga', 'glassblower', 'hedge-witch', 'moon')
        briefs = dict.fromkeys(ids, {})
        loop.save(self.run / 'decisions/briefs.json', {'briefs': briefs, 'style': {}})
        results = {pet: {'pet': pet, 'status': 'rejected'} for pet in ids}
        loop.save(self.run / 'decisions/images.json', {'pets': results, 'redos': {}})
        call_path = self.case / 'makers-call.json'
        (self.case / 'makers-call.md').write_text('Repair the named defects once.')
        loop.save(call_path, {'version': 1, 'maker': 'Codex', 'statement': 'makers-call.md', 'pets': [
            {'pet': p, 'action': 'leave' if p == 'moon' else 'attempt',
             'reason': 'Named defect.', 'instruction': 'Keep sound art.'} for p in ids]})
        hatch = lamp_hatch.hatch
        def legacy_hatch(driver, **item):
            if item['pet'] == 'hedge-witch':
                with patch.object(lamp_hatch, 'LIMIT', 1):
                    return hatch(driver, **item)
            return hatch(driver, **item)
        with patch.object(lamp_hatch, 'hatch', legacy_hatch), \
                patch.dict(os.environ, {'FAKE_FINAL_REJECT': 'glassblower'}):
            first = lamp_maker.finish(driver, call_path, results, briefs, {}, None)
        self.assertEqual({p: r['status'] for p, r in first.items()}, {
            'baba-yaga': 'validated', 'glassblower': 'rejected', 'hedge-witch': 'failed', 'moon': 'left'})
        self.assertEqual(first['hedge-witch']['failure_kind'], 'package')
        before = {p: p.read_bytes() for p in self.run.rglob('*')
                  if p.is_file() and p.name != 'active-attempt.json'}
        calls = len(self.calls())
        listing = lamp_resume.listing(self.run, call_path)
        self.assertEqual(listing['local_repackages'], 1)
        self.assertEqual(listing['model_hatches'], 0)
        self.assertEqual(listing['makers_call']['review_after_repackage'], ['hedge-witch'])
        self.assertEqual(listing['makers_call']['jury_calls_after_repackage'], 6)
        self.assertEqual(next(h['action'] for h in listing['hatches'] if h['key'] == 'maker-hedge-witch'),
                         'repackage')
        image_review = driver.image_review
        def partial_review(number, stage, candidates, briefs, style, *, seats):
            image_review(number, stage, candidates, briefs, style, seats=seats[:2])
            raise OSError('jury interrupted')
        with patch.object(driver, 'image_review', partial_review):
            with self.assertRaisesRegex(OSError, 'jury interrupted'):
                lamp_maker.finish(driver, None, results, briefs, {}, None)
        self.assertEqual(len(self.calls()) - calls, 2)
        self.assertFalse((self.repo / 'factory/pets/hedge-witch').exists())
        self.assertFalse((self.run / 'decisions/maker-image-resumes').exists())
        listing = lamp_resume.listing(self.run)
        self.assertEqual(listing['local_repackages'], 0)
        self.assertEqual(listing['model_hatches'], 0)
        self.assertEqual(listing['makers_call']['pending'], ['hedge-witch'])
        self.assertEqual(listing['makers_call']['jury_calls'], 4)
        ballots = {p: p.read_bytes() for p in self.run.glob('records/010/*.json')}
        with patch.object(lamp_hatch, 'publish', side_effect=OSError('publication interrupted')):
            with self.assertRaisesRegex(OSError, 'publication interrupted'):
                lamp_maker.finish(driver, None, results, briefs, {}, None)
        addition = loop.load(self.run / 'decisions/maker-image-resumes/000001.json')
        self.assertEqual(list(addition['pets']), ['hedge-witch'])
        self.assertEqual(len(self.calls()) - calls, 6)
        final = lamp_maker.finish(driver, None, results, briefs, {}, None)
        self.assertEqual(final['hedge-witch']['status'], 'validated')
        self.assertEqual(final['hedge-witch']['atlas_sha256'], first['hedge-witch']['atlas_sha256'])
        self.assertEqual(final['hedge-witch']['fresh_attempts'], 0)
        for pet in ('baba-yaga', 'glassblower', 'moon'):
            self.assertEqual(final[pet], first[pet])
        self.assertTrue((self.repo / 'factory/pets/hedge-witch').exists())
        self.assertTrue(all(p.read_bytes() == data for p, data in before.items()))
        self.assertTrue(all(p.read_bytes() == data for p, data in ballots.items()))
        for call in self.calls()[calls:]:
            self.assertNotIn('/hatches/', call['work'])
            context = json.JSONDecoder().raw_decode(call['prompt'].split('Context:\n', 1)[1])[0]
            self.assertEqual(list(context['candidates']), ['hedge-witch'])
            self.assertIn(final['hedge-witch']['review_contact'], call['args'])
        self.assertEqual(lamp_maker.finish(driver, None, results, briefs, {}, None), final)
        self.assertEqual(len(self.calls()) - calls, 6)
        listing = lamp_resume.listing(self.run)
        self.assertEqual(listing['makers_call']['jury_calls'], 0)
        self.assertEqual(listing['makers_call']['review_after_repackage'], [])
        self.assertFalse((self.run / 'decisions/maker-image-resumes/000002.json').exists())

    def test_maker_call_cannot_retry_provider_refusal_or_unspent_gate_attempt(self):
        driver = self.driver()
        with patch.dict(os.environ, {'FAKE_REFUSE': 'moon', 'FAKE_FAIL': 'hedge-witch'}):
            results = {p: lamp_hatch.hatch(driver, 'set-' + p, p, {}, {}, None, None)
                       for p in ('moon', 'hedge-witch')}
        call_path = self.case / 'makers-call.json'
        (self.case / 'makers-call.md').write_text('One maker attempt.')
        for pet, error in (('moon', 'provider refusal is terminal'),
                           ('hedge-witch', 'exhausted Lamp gate budget')):
            loop.save(call_path, {'version': 1, 'maker': 'Codex', 'statement': 'makers-call.md', 'pets': [
                {'pet': pet, 'action': 'attempt', 'reason': 'Try again.', 'instruction': 'Repair the defect.'}]})
            with self.assertRaisesRegex(ValueError, error):
                lamp_maker.commission(self.run, call_path, results)
        self.assertFalse((self.run / 'decisions/makers-call.json').exists())

    def test_changed_config_and_symlinks_are_rejected(self):
        self.driver()
        with self.assertRaisesRegex(ValueError, 'frozen input differs'):
            lamp.Lamp(self.run, 'different', None, 'high', 4, 3, self.skill)
        (self.run / 'jobs').symlink_to(self.case / 'elsewhere')
        with self.assertRaises(ValueError):
            lamp.execute(self.run, dict(id='safe', round=1, attempt=0))


class GuardianNameTests(unittest.TestCase):
    """A guardian's drawing is the guardian (Paul, October 15): a package goes by the seated
    guardian's name, and a pet published before the rename still counts as published."""

    def setUp(self):
        self.lamp = type('Seats', (), {'seats': {'hedge-witch': {'id': 'hedge-witch', 'name': 'The Hedge Witch'}}})()

    def test_a_package_goes_by_its_seated_guardians_name_not_its_briefs(self):
        brief = {'display_name': 'Tarragon', 'description': 'A sleepy mossy mushroom.'}
        self.assertEqual(lamp_hatch.package_metadata(self.lamp, 'hedge-witch', brief), {
            'id': 'hedge-witch', 'displayName': 'The Hedge Witch',
            'description': 'A sleepy mossy mushroom.', 'spritesheetPath': 'spritesheet.webp'})
        with self.assertRaisesRegex(ValueError, 'no seated guardian'):
            lamp_hatch.package_metadata(self.lamp, 'nobody', brief)

    def test_every_published_drawing_goes_by_its_guardians_name(self):
        repo = Path(__file__).resolve().parents[2]
        for guardian in loop.guardians():
            metadata = loop.load(repo / 'factory/pets' / guardian['id'] / 'pet.json')
            if metadata is not None:
                self.assertEqual(metadata['displayName'], guardian['name'], guardian['id'])

    def publish(self, root, package_name, existing_name, description='A sleepy mossy mushroom.', atlas=b'atlas'):
        """Publish a package named package_name over a pet published as existing_name (None: none)."""
        package = root / 'package'
        package.mkdir(exist_ok=True)
        files = {'spritesheet.webp': b'atlas', 'pet.json': json.dumps(
            {'id': 'hedge-witch', 'displayName': package_name, 'description': 'A sleepy mossy mushroom.',
             'spritesheetPath': 'spritesheet.webp'}, indent=2, ensure_ascii=False).encode()}
        for name, data in files.items():
            (package / name).write_bytes(data)
        published = root / 'repo/factory/pets/hedge-witch'
        shutil.rmtree(published, ignore_errors=True)
        if existing_name is not None:
            published.mkdir(parents=True)
            (published / 'spritesheet.webp').write_bytes(atlas)
            loop.save(published / 'pet.json', {'id': 'hedge-witch', 'displayName': existing_name,
                                               'description': description, 'spritesheetPath': 'spritesheet.webp'})
        record = {'pet': 'hedge-witch', 'package': str(package),
                  'package_hashes': {name: lamp.digest(data) for name, data in files.items()}}
        with patch.object(loop, 'REPO', root / 'repo'):
            lamp_hatch.publish(self.lamp, record, {}, {})
        return loop.load(published / 'pet.json')['displayName']

    def test_a_resumed_publish_keeps_the_guardians_name(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            # Validated under the brief's name, published under the guardian's: already published.
            self.assertEqual(self.publish(root, 'Tarragon', 'The Hedge Witch'), 'The Hedge Witch')
            # Published under the brief's name, or not yet: the guardian's name wins.
            self.assertEqual(self.publish(root, 'The Hedge Witch', 'Tarragon'), 'The Hedge Witch')
            self.assertEqual(self.publish(root, 'Tarragon', 'Tarragon'), 'The Hedge Witch')
            self.assertEqual(self.publish(root, 'Tarragon', None), 'The Hedge Witch')
            self.assertEqual((root / 'repo/factory/pets/hedge-witch/spritesheet.webp').read_bytes(), b'atlas')
            # Anything else that differs is still another run's pet.
            with self.assertRaisesRegex(ValueError, 'existing pet differs'):
                self.publish(root, 'Tarragon', 'The Hedge Witch', description='Another mushroom.')
            with self.assertRaisesRegex(ValueError, 'existing pet differs'):
                self.publish(root, 'Tarragon', 'The Hedge Witch', atlas=b'other art')


if __name__ == '__main__':
    unittest.main()
