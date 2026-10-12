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
from tools.factory.fixtures.strict_schema import check_strict


class LampTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(dir='/root/factory-out/F36')
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
                                     'FAKE_REJECT_FIRST_STYLES': '1'}):
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
            self.assertEqual(loop.load(self.run / 'decisions/shortlist-0.json')['selected'], [])
            self.assertEqual(loop.load(self.run / 'decisions/shortlist-1.json')['selected'], ['style-00', 'style-01'])
            driver.run_plan()
            self.assertEqual(len(self.calls()), len(calls))
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
                result = loop.load(path)
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
            pilot = loop.load(self.run / 'hatches' / selected[0] / 'result.json')
            set_calls = [c for c in new_calls if '/hatches/set-' in c['work'] or '/hatches/redo-' in c['work']]
            self.assertEqual(len(set_calls), 21)
            for call in set_calls:
                self.assertEqual(call['args'][call['args'].index('--image') + 1], pilot['contact'])
                provenance = loop.load(Path(call['work']) / 'package/provenance.json')
                self.assertEqual(provenance['reference'], pilot['contact'])
                self.assertEqual(provenance['reference_sha256'], lamp.digest(Path(pilot['contact']).read_bytes()))
            self.driver().run_plan()
            self.assertEqual(len(self.calls()), len(calls))

    def test_new_proposals_include_exact_contract_and_unattended_decisions(self):
        driver = self.driver()
        with patch.object(driver, 'hatch_many', side_effect=RuntimeError('reached pilots')):
            with self.assertRaisesRegex(RuntimeError, 'reached pilots'):
                driver.run_plan()
        for call in self.calls():
            self.assertIn(lamp.UNATTENDED, call['prompt'])
            self.assertIn(lamp.CONTRACT, call['prompt'])
            if 'style-proposals-' in call['work']:
                self.assertIn('Do not invent frame counts, rows or alternate paint looks.', call['prompt'])

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
        self.assertEqual(len(list(self.run.glob('records/*/*.json'))), 38)
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
        self.assertEqual(len(summary['pets']), 20)
        self.assertEqual(summary['pets']['medea'], 'invalid')
        self.assertEqual(summary['pets']['moon'], 'invalid')
        self.assertEqual(len([h for h in hatches if h['key'].startswith('set-')]), 18)
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

    def test_changed_config_and_symlinks_are_rejected(self):
        self.driver()
        with self.assertRaisesRegex(ValueError, 'frozen input differs'):
            lamp.Lamp(self.run, 'different', None, 'high', 4, 3, self.skill)
        (self.run / 'jobs').symlink_to(self.case / 'elsewhere')
        with self.assertRaises(ValueError):
            lamp.execute(self.run, dict(id='safe', round=1, attempt=0))


if __name__ == '__main__':
    unittest.main()
