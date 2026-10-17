"""F13 acceptance: historical byte replay and a complete toy run on canned agent replies.

python3 -m unittest discover -s tools/factory -p 'test_*taste*.py'
python3 -m unittest discover -s tools/factory -p test_loop_kit.py
"""
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from factory.taste import accounting, calibration, cli, kit, loop, pages, renderers, runners, schema, settings


class KitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='kit-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.piece = self.root / 'toy'
        self.piece.mkdir()
        config = (loop.REPO / 'factory/pieces/panel-name/piece.toml').read_text()
        config = config.replace('jury_size = 6', 'jury_size = 3').replace('proposers = 4', 'proposers = 2')
        config = config.replace('candidates_each = 3', 'candidates_each = 2')
        config = config.replace('id = "panel-name"', 'id = "toy"').replace('adapter = "panel-name"', 'adapter = "generic"')
        (self.piece / 'piece.toml').write_text(config)
        (self.piece / 'brief.md').write_text('Name two garden gates. Concrete, kind and clear.')
        loop.save(self.piece / 'slots.json', [{'slot': '1', 'incumbent': 'Old Gate'},
                                             {'slot': '2', 'incumbent': 'Other Gate'}])
        self.run_path = self.root / 'run'
        self.out = self.root / 'renders'
        self.new()

    def new(self, calibration_path=None):
        if self.run_path.exists():
            shutil.rmtree(self.run_path)
        self.record = kit.new(self.piece, self.run_path, calibration_path)
        self.run = kit.Run(self.run_path, self.out)

    def reply(self, job, data, retry=False):
        path = runners.destination(self.run_path, {**job, 'attempt': int(retry)})
        loop.save(path, data)
        return path

    def proposal(self, job):
        return {'slots': {sid: [{'name': f"{job['guardian']} {sid} {i}", 'why': 'A gate with a story.'}
                                for i in range(rule['minItems'])]
                          for sid, rule in job['reply_schema']['properties']['slots']['properties'].items()}}

    def verdict(self, job):
        ballots = loop.load(self.run.folder(job['round']) / 'ballots' / f"{job['guardian']}.json")
        result = {'slots': {}}
        for sid, ballot in ballots.items():
            data = {'candidates': {letter: {'lives': 'kind gates', 'veto': None} for letter in ballot}}
            props = job['reply_schema']['properties']['slots']['properties'][sid]['properties']
            if 'ranking' in props:
                data.update(ranking=list(ballot), note='A welcome at the gate.')
            if 'approval' in props:
                data['approval'] = list(ballot)[:2]
            result['slots'][sid] = data
        return result

    def complete(self, n=1):
        for job in self.run.jobs(n):
            self.reply(job, self.proposal(job))
        status = self.run.collect(n)
        self.assertTrue(all(s == 'accepted' for s in status.values()))
        for job in self.run.jobs(n):
            self.reply(job, self.verdict(job))
        return self.run.decide(n)

    def test_toy_three_rounds_canned_replies_and_idempotent_replay(self):
        for n in range(1, 4):
            decision = self.complete(n)
            self.assertEqual(len(decision['results']), 2)
            self.assertEqual(decision, self.run.decide(n))
        report = cli.report(self.run_path)
        self.assertEqual(len(report['standings']), 3)
        self.assertEqual(len(report['ledger']['rounds']), 3)
        original = {p.relative_to(self.run_path): p.read_bytes() for p in self.run_path.rglob('decision.json')}
        original[Path('ledger.json')] = (self.run_path / 'ledger.json').read_bytes()
        original[Path('champion.json')] = (self.run_path / 'champion.json').read_bytes()
        replayed = kit.replay(self.run_path, self.root / 'replayed')
        for path, contents in original.items():
            self.assertEqual((replayed / path).read_bytes(), contents, str(path))
        prompt = next((self.run_path / 'jobs/003').glob('proposer-*.json'))
        self.assertIn('Your past names and how they fared', loop.load(prompt)['prompt'])
        proposer = loop.load(prompt)['guardian']
        history = loop.history(self.run_path, proposer, self.run.gs)
        if any(s['source'] == proposer for d in report['standings'] for r in d['results'] for s in r['standings']):
            self.assertIn('Round', history)

    def test_both_recorded_runs_replay_byte_for_byte_through_kit(self):
        for piece, suffix in [('panel-name', ''), ('color-names', 'run')]:
            source = loop.REPO / 'factory/pieces' / piece / suffix
            original = {p.relative_to(source): p.read_bytes() for p in source.rglob('decision.json')}
            original[Path('ledger.json')] = (source / 'ledger.json').read_bytes()
            with patch.object(loop, 'guardians', side_effect=AssertionError('live seats used')):
                replayed = kit.replay(source, self.root / f'replay-{piece}')
            for path, contents in original.items():
                self.assertEqual((replayed / path).read_bytes(), contents, str(path))
            self.assertEqual((source / 'ledger.json').read_bytes(), original[Path('ledger.json')])

    def test_new_runs_have_no_georgian_option_or_glossary(self):
        self.assertNotIn('glossary', self.record)
        self.assertNotIn('sharedBar', self.record)
        for piece in ('panel-name', 'color-names', 'figure'):
            config = settings.read(loop.REPO / 'factory/pieces' / piece / 'piece.toml')
            self.assertNotIn('georgian', config.get('caps', {}))
        for guardian in self.record['guardians']:
            prompt = self.run.prompt(guardian['id'])
            self.assertIn('You are ' + guardian['name'] + '.', prompt)
            self.assertNotIn('one name in fifty', prompt)
            self.assertNotIn('Georgian thread', prompt)
        for value in (True, False):
            self.record['settings']['caps']['georgian'] = value
            with self.assertRaisesRegex(ValueError, 'unknown caps'):
                settings.validate(self.record['settings'])
            loop.save(self.run_path / 'rules.json', self.record)
            with self.assertRaisesRegex(ValueError, 'unknown caps'):
                kit.Run(self.run_path, self.out)
        self.record['settings']['caps'].pop('georgian')
        loop.save(self.run_path / 'rules.json', self.record)
        self.assertFalse(kit.Caps(self.record)({0: 'Tbilisi', 1: 'Supra'}))
        self.assertFalse(kit.Caps(self.record).contributes('Supra', 'words', 'Georgian words'))
        self.complete()
        prompt = loop.load(self.run_path / 'jobs/001/juror-originality.json')['prompt']
        self.assertNotIn('glossary', prompt.lower())
        self.assertNotIn('one name in fifty', prompt)
        self.assertIn('Emily; ', prompt)
        self.assertIn('George; Bulat;', prompt)

    def test_settings_are_frozen_and_invalid_settings_fail(self):
        first = self.run.draw(1)
        (self.piece / 'piece.toml').write_text('broken TOML')
        with patch.object(loop, 'guardians', side_effect=AssertionError('live seats used')):
            self.assertEqual(kit.Run(self.run_path, self.out).draw(1), first)
        for field, value in [('scoring', 'plurality'), ('veto_policy', 'sometimes'), ('jury_size', 0),
                             ('rules_version', 3), ('rounds', True)]:
            config = json.loads(json.dumps(self.record['settings']))
            config[field] = value
            with self.assertRaises(ValueError):
                settings.validate(config)
        with self.assertRaises(ValueError):
            self.run.draw(4)
        with self.assertRaises(ValueError):
            self.run.draw(2)
        with self.assertRaises(ValueError):
            kit.new(self.piece, self.run_path)

    def test_schema_repair_once_then_reject_blocks_decision(self):
        jobs = self.run.jobs(1)
        first = jobs[0]
        self.reply(first, {'slots': {}})
        self.assertEqual(self.run.collect(1)[first['id']], 'retry')
        repair = loop.load(self.run_path / 'retries/001' / f"{first['id']}.json")
        self.assertEqual(repair['attempt'], 1)
        self.assertEqual(repair['model'], first['model'])
        self.assertIn('missing', repair['prompt'])
        # Merely polling the same invalid original does not spend the repair attempt.
        self.assertEqual(self.run.collect(1)[first['id']], 'waiting')
        self.reply(first, {'slots': {}}, retry=True)
        self.assertEqual(self.run.collect(1)[first['id']], 'rejected')
        with self.assertRaises(ValueError):
            self.run.decide(1)
        self.assertFalse((self.run.folder(1) / 'slate.json').exists())

    def test_repaired_proposal_and_juror_are_accepted(self):
        for job in self.run.jobs(1):
            self.reply(job, {})
        self.run.collect(1)
        for job in self.run.jobs(1):
            self.reply(job, self.proposal(job), retry=True)
        self.run.collect(1)
        for job in self.run.jobs(1):
            self.reply(job, self.verdict(job))
        job = self.run.jobs(1)[-1]
        invalid = self.verdict(job)
        sid = next(iter(invalid['slots']))
        if 'ranking' in invalid['slots'][sid]:
            invalid['slots'][sid]['ranking'] = ['Z']
        else:
            invalid['slots'][sid]['candidates'] = {}
        self.reply(job, invalid)
        self.assertEqual(self.run.collect(1)[job['id']], 'retry')
        self.reply(job, self.verdict(job), retry=True)
        self.assertEqual(len(self.run.decide(1)['results']), 2)

    def test_writer_models_images_and_codex_runner_command(self):
        text = (self.piece / 'piece.toml').read_text().replace('[roles.writer]\nmodel = "opus"\neffort = "low"\nenabled = false',
                    '[roles.writer]\nmodel = "test-writer"\neffort = "high"\nenabled = true')
        (self.piece / 'piece.toml').write_text(text)
        self.new()
        job = next(j for j in self.run.jobs(1) if j['role'] == 'writer')
        self.assertEqual((job['model'], job['effort']), ('test-writer', 'high'))
        command = runners.codex_command({**job, 'images': ['/root/factory-out/test.png']}, 'schema', 'reply', self.out)
        self.assertIn('read-only', command)
        self.assertIn('model_reasoning_effort="high"', command)
        self.assertIn('--image', command)
        self.assertEqual(command[-1], '-')
        def fake_run(command, **kwargs):
            self.assertEqual(kwargs['input'], job['prompt'])
            Path(command[command.index('--output-last-message') + 1]).write_text(json.dumps(self.proposal(job)))
            kwargs['stdout'].write(json.dumps({'type': 'turn.completed', 'usage': {'input_tokens': 10, 'output_tokens': 5}}))
            return subprocess.CompletedProcess(command, 0)
        with patch.object(runners.subprocess, 'run', side_effect=fake_run):
            reply = runners.codex(self.run_path, self.run_path / 'jobs/001' / f"{job['id']}.json", self.out)
        self.assertEqual(loop.load(reply), self.proposal(job))
        self.assertEqual(accounting.report(self.run_path)['totals']['input_tokens'], 10)

    def test_contact_swatches_text_pages_and_script_injection(self):
        first, second = self.root / 'first.png', self.root / 'second.png'
        Image.new('RGB', (50, 50), 'red').save(first)
        Image.new('RGB', (50, 50), 'blue').save(second)
        sheet = renderers.contacts({'A': first, 'B': second}, self.out / 'images.png')
        with Image.open(sheet) as image:
            self.assertEqual(image.getpixel((160, 30)), (255, 0, 0))
            self.assertEqual(image.getpixel((480, 30)), (0, 0, 255))
        renderers.swatches([{'slot': 'A', 'hex': '112233'}], self.out / 'swatches.png')
        with Image.open(self.out / 'swatches.png') as image:
            self.assertEqual(image.getpixel((20, 20)), (17, 34, 51))
        renderers.text_in_use(['The garden gate'], self.out / 'text.png')
        decision = self.complete()
        winner = decision['results'][0]['winner']
        picks = self.root / 'checkpoint.json'
        loop.save(picks, [{'slot': '1', 'name': winner, 'veto': False, 'love': True,
                           'note': '</script><script>bad()</script>', 'at': '2026-10-11'}])
        for gallery in (False, True):
            path = pages.generate(self.run_path, self.out / f'page-{gallery}.html', checkpoint=picks, gallery=gallery)
            page = path.read_text()
            self.assertNotIn('</script><script>bad()', page)
            self.assertIn('checkpoint/c', page)
            self.assertIn('localStorage', page)
            self.assertIn('checkpoint.json', page)
            self.assertIn('Named by ', page)
            script = page.split('<script>', 1)[1].split('</script>', 1)[0]
            js = self.out / 'review.js'
            js.write_text(script)
            result = subprocess.run(['node', '--check', str(js)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            if not gallery:
                result = subprocess.run(['node', str(loop.REPO / 'tools/factory/test_review.mjs'), str(path)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
        with self.assertRaises(ValueError):
            renderers.text_in_use(['scratch'], loop.REPO / 'bad.png')

    def test_calibration_sources_and_jurors_are_read_by_scoring(self):
        decision = self.complete()
        result = decision['results'][0]
        pick = next(s for s in result['standings'] if s['source'] != 'incumbent')
        picks = self.root / 'checkpoint.json'
        loop.save(picks, [{'slot': '1', 'name': pick['name'], 'veto': False, 'love': True, 'note': 'Clear.'}])
        output = self.root / 'factors.json'
        factors = calibration.calculate(self.run_path, picks, output)
        self.assertGreater(factors['sources'][pick['source']], 1)
        self.assertNotIn('originality', factors['jurors'])
        self.assertTrue(factors['evidence']['jurors'])
        self.new(output)
        self.assertEqual(self.record['calibration'], factors['jurors'])
        self.assertEqual(self.record['sourceCalibration'], factors['sources'])
        decision = self.complete()
        draw = self.run.draw(1)
        slate = loop.load(self.run.folder(1) / 'slate.json')
        for slot, result in zip(slate, decision['results']):
            ballots = {gid: loop.load(self.run.folder(1) / 'ballots' / f'{gid}.json')[slot['slot']] for gid in draw['jury']}
            verdicts = {gid: loop.load(self.run.folder(1) / 'accepted' / f'juror-{gid}.json')['slots'][slot['slot']]
                        for gid in draw['jury']}
            tally = loop.score([c['name'] for c in slot['candidates']], draw['jury'], ballots, verdicts,
                               self.record, weights=draw['weights'])
            for standing in result['standings']:
                self.assertEqual(standing['score'], tally['score'][standing['name']] *
                                 factors['sources'].get(standing['source'], 1))
        with self.assertRaises(ValueError):
            settings.factors({'jurors': {'x': float('nan')}})

    def test_cli_round_trip_and_report(self):
        args = ['--run', str(self.run_path), '--out', str(self.out)]
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(args + ['draw', '1']), 0)
            self.assertEqual(cli.main(args + ['jobs', '1']), 0)
            self.assertEqual(cli.main(args + ['collect', '1']), 1)
        self.complete()
        with contextlib.redirect_stdout(io.StringIO()) as captured:
            self.assertEqual(cli.main(args + ['report']), 0)
        self.assertEqual(len(json.loads(captured.getvalue())['ledger']['rounds']), 1)
        self.assertFalse((self.run_path / 'costs').exists())

    def test_guarantee_caps_and_plants_are_piece_settings(self):
        text = (self.piece / 'piece.toml').read_text().replace('guarantee = false', 'guarantee = true')
        text = text.replace('plants = []', 'plants = [{slot="1", name="Perfect Anchor", quality="good"}, '
                            '{slot="2", name="Dull Anchor", quality="bad"}]')
        text = text.replace('[caps]', '[caps]\nlead = 1\ntrail = 1')
        (self.piece / 'piece.toml').write_text(text)
        self.new()
        for job in self.run.jobs(1):
            data = self.proposal(job)
            for sid, candidates in data['slots'].items():
                for i, c in enumerate(candidates):
                    c['name'] = f"{job['guardian'].title()} {sid}{i}"
            self.reply(job, data)
        self.run.collect(1)
        for job in self.run.jobs(1):
            verdict = self.verdict(job)
            ballots = loop.load(self.run.folder(1) / 'ballots' / f"{job['guardian']}.json")
            for sid, ballot in ballots.items():
                if 'ranking' in verdict['slots'][sid]:
                    verdict['slots'][sid]['ranking'] = sorted(ballot, key=lambda letter: 'Anchor' not in ballot[letter])
            self.reply(job, verdict)
            self.assertNotIn('Perfect Anchor — good', job['prompt'])
        decision = self.run.decide(1)
        proposers = self.run.draw(1)['proposers']
        self.assertEqual({r['winner_source'] for r in decision['results']}, set(proposers))
        self.assertFalse(any(r['winner_source'] == 'plant' for r in decision['results']))
        anchors = [s for r in decision['results'] for s in r['standings'] if s['source'] == 'plant']
        self.assertEqual(len(anchors), 2)
        self.assertGreater(anchors[0]['firsts'], 0)
        self.assertFalse(anchors[0]['vetoes'])
        caps = kit.Caps(self.record)
        self.assertEqual(caps({1: 'Quiet Door', 2: 'Quiet Room'}), [('lead', 'Quiet')])

    def test_approval_and_copeland_run_end_to_end(self):
        original = (self.piece / 'piece.toml').read_text()
        for method in ('approval', 'copeland'):
            (self.piece / 'piece.toml').write_text(original.replace('scoring = "borda"', f'scoring = "{method}"'))
            self.new()
            self.assertEqual(self.complete()['round'], 1)

    def test_image_and_parameter_candidates_carry_to_next_round(self):
        image = self.root / 'candidate.png'
        Image.new('RGB', (80, 60), '#8899aa').save(image)
        candidate_schema = schema.obj({'name': schema.STRING, 'why': schema.STRING,
            'images': schema.array(schema.STRING, 1),
            'value': schema.obj({'height': {'type': 'integer', 'minimum': 1, 'maximum': 10}})})
        loop.save(self.piece / 'slots.json', [{'slot': '1', 'incumbent': 'Old Gate', 'candidate_schema': candidate_schema}])
        self.new()
        for job in self.run.jobs(1):
            data = self.proposal(job)
            for c in data['slots']['1']:
                c.update(images=[str(image)], value={'height': 5})
            self.reply(job, data)
        self.run.collect(1)
        for job in self.run.jobs(1):
            self.assertTrue(any(path.endswith('-images.png') for path in job['images']))
            self.assertIn('Parameters:', job['prompt'])
            verdict = self.verdict(job)
            if 'ranking' in verdict['slots']['1']:
                ballot = loop.load(self.run.folder(1) / 'ballots' / f"{job['guardian']}.json")['1']
                verdict['slots']['1']['ranking'] = sorted(ballot, key=lambda letter: ballot[letter] == 'Old Gate')
            self.reply(job, verdict)
        decision = self.run.decide(1)
        self.assertNotEqual(decision['results'][0]['winner'], 'Old Gate')
        slot = self.run.slots(2)[0]
        self.assertEqual(slot['incumbent_candidate']['value'], {'height': 5})
        self.assertEqual(slot['images'], [str(image)])

    def test_claude_adapter_costs_and_legacy_calibration_gallery(self):
        job = self.run.jobs(1)[0]
        log = self.root / 'agent.output'
        log.write_text(json.dumps({'duration_ms': 500, 'message': {'role': 'assistant', 'id': 'last',
            'usage': {'input_tokens': 12, 'output_tokens': 7}, 'content': [{'type': 'tool_use',
             'name': 'SubagentHandback', 'input': {'message': json.dumps(self.proposal(job))}}]}}))
        reply = runners.claude(self.run_path, self.run_path / 'jobs/001' / f"{job['id']}.json", log)
        self.assertEqual(loop.load(reply), self.proposal(job))
        costs = accounting.report(self.run_path)
        self.assertEqual(costs['totals']['seconds'], 0.5)
        self.assertEqual(costs['totals']['output_tokens'], 7)
        self.assertGreater(costs['unmeasured']['seconds'], 0)
        source = loop.REPO / 'factory/pieces/color-names/run'
        pick = self.root / 'checkpoint.json'
        loop.save(pick, [{'slot': 1, 'name': 'Beeswax', 'love': True, 'veto': False, 'note': 'Warm.'}])
        factors = calibration.calculate(source, pick, self.root / 'calibration.json')
        self.assertGreater(factors['sources']['writer'], 1)
        self.assertEqual(len(factors['jurors']), 5)
        gallery = pages.generate(source, self.out / 'legacy-gallery.html', checkpoint=pick, gallery=True)
        self.assertIn('Honey-warm like candle wax', gallery.read_text())

    def test_builtin_adapters_start_fresh_and_share_craft_oracles(self):
        for piece, expected in [('panel-name', 1), ('color-names', 36)]:
            run_path = self.root / piece
            record = kit.new(loop.REPO / 'factory/pieces' / piece, run_path)
            self.assertEqual(len(record['initialSlots']), expected)
            runner = kit.Run(run_path, self.out)
            jobs = runner.jobs(1)
            self.assertEqual(len([j for j in jobs if j['role'] == 'proposer']), 4)
            self.assertIn('Your charter', jobs[0]['prompt'])
            if piece == 'color-names':
                self.assertTrue(jobs[0]['images'])
                self.assertTrue(runner.craft('Blue Fog', record['initialSlots'][0], {})[0])
            else:
                self.assertTrue(runner.craft('Hogwarts', record['initialSlots'][0], {})[0])


class PrimitiveTests(unittest.TestCase):
    def setUp(self):
        self.gs = [{'id': 'g1', 'name': 'One', 'charter_text': '- **guards against**: clutter.'},
                   {'id': 'g2', 'name': 'Two', 'charter_text': '- **guards against**: clutter.'},
                   {'id': 'g3', 'name': 'Three', 'charter_text': '- **guards against**: clutter.'}]
        self.record = {'version': 2, 'guardians': self.gs}
        self.ballots = {g['id']: dict(zip('ABC', ['One', 'Two', 'Three'])) for g in self.gs}
        self.verdicts = {'g1': {'ranking': ['A', 'B', 'C'], 'approval': ['B']},
                         'g2': {'ranking': ['A', 'B', 'C'], 'approval': ['B', 'C']},
                         'g3': {'ranking': ['B', 'C', 'A'], 'approval': []}}

    def tally(self, **changes):
        return loop.score(['One', 'Two', 'Three'], list(self.ballots), self.ballots, self.verdicts,
                          {**self.record, **changes})

    def test_all_scoring_methods_and_weighted_copeland_ties(self):
        self.assertEqual(self.tally()['score'], {'One': 4, 'Two': 4, 'Three': 1})
        self.assertEqual(self.tally(scoring='approval')['score'], {'One': 0, 'Two': 2, 'Three': 1})
        self.assertEqual(self.tally(scoring='copeland')['score'], {'One': 2, 'Two': 1, 'Three': 0})
        self.assertEqual(self.tally(scoring='copeland', calibration={'g3': 3})['score'],
                         {'One': 0, 'Two': 2, 'Three': 1})
        verdicts = {g: self.verdicts[g] for g in ('g1', 'g3')}
        result = loop.score(['One', 'Two', 'Three'], list(verdicts), self.ballots, verdicts,
                            {**self.record, 'scoring': 'copeland'})
        self.assertEqual(result['score'], {'One': 1, 'Two': 1.5, 'Three': 0.5})

    def test_veto_policies(self):
        self.verdicts['g1']['candidates'] = {'A': {'veto': 'arbitrary'}}
        self.assertFalse(self.tally(vetoPolicy='quote')['vetoes']['One'])
        self.assertTrue(self.tally(vetoPolicy='free')['vetoes']['One'])
        self.assertFalse(self.tally(vetoPolicy='off')['vetoes']['One'])
        self.verdicts['g1']['candidates']['A']['veto'] = 'clutter'
        self.assertTrue(self.tally(vetoPolicy='quote')['vetoes']['One'])

    def test_usage_avoids_duplicate_claude_messages_and_counts_codex_turns(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / 'agent.output'
            events = [{'timestamp': '2026-10-11T10:00:00Z', 'message': {'id': 'm1', 'usage': {'input_tokens': 10, 'output_tokens': 2}}},
                      {'timestamp': '2026-10-11T10:00:02Z', 'message': {'id': 'm1', 'usage': {'input_tokens': 10, 'output_tokens': 5, 'cache_read_input_tokens': 7}}}]
            log.write_text('\n'.join(json.dumps(e) for e in events))
            self.assertEqual(accounting.usage(log), {'input_tokens': 17, 'output_tokens': 5, 'cached_input_tokens': 7, 'seconds': 2})
            log.write_text(json.dumps({'type': 'turn.completed', 'usage': {'input_tokens': 100, 'cached_input_tokens': 20, 'output_tokens': 30}}))
            self.assertEqual(accounting.usage(log)['input_tokens'], 100)
            self.assertIsNone(accounting.usage(log)['seconds'])
            log.write_text('{}')
            self.assertIsNone(accounting.usage(log)['input_tokens'])



class TeamSeatTests(unittest.TestCase):
    """GUARDIANS.md › Teams: a team holds one seat, and every guardian on the Lamp sits on exactly
    one; one who passed its seat on (`former`) sits on none."""

    def setUp(self):
        self.gs = loop.guardians()
        self.seats = loop.team_seats(self.gs)

    def test_every_guardian_sits_on_exactly_one_team(self):
        members = [m for seat in self.seats for m in seat['members']]
        self.assertEqual(sorted(members), sorted(g['id'] for g in self.gs if not g.get('former')))
        self.assertEqual([g['id'] for g in self.gs if g.get('former')], ['bible-school-teacher'])
        self.assertTrue(all(not g['active'] for g in self.gs if g.get('former')))
        hearth = next(s for s in self.seats if s['id'] == 'hearth')
        self.assertEqual(hearth['members'], ['robber-girl', 'child-at-bedtime', 'madeleine-lengle'])
        self.assertEqual([s['id'] for s in self.seats if s.get('vetoOnly')], ['gate'])
        storytellers = next(s for s in self.seats if s['id'] == 'storytellers')
        self.assertEqual(storytellers['members'], ['storybook', 'dinotopia', 'bartimaeus', 'lotte-reiniger'])
        self.assertIn('#### Dino', storytellers['charter_text'])

    def test_a_member_vetoes_by_quoting_its_own_line(self):
        record = {'version': 2, 'guardians': self.seats, 'vetoPolicy': 'quote'}
        names = ['One', 'Two']
        ballots = {'storytellers': {'A': 'One', 'B': 'Two'}}
        quote = 'magic with no light and no weight'
        verdicts = {'storytellers': {'candidates': {'A': {'veto': quote}}, 'ranking': ['B', 'A']}}
        result = loop.score(names, ['storytellers'], ballots, verdicts, record)
        self.assertEqual(result['vetoes']['One'], [f'The Storytellers: {quote}'])
        verdicts['storytellers']['candidates']['A']['veto'] = 'not in any charter'
        self.assertFalse(loop.score(names, ['storytellers'], ballots, verdicts, record)['vetoes']['One'])

    def test_draw_seats_the_gate_and_teams_and_reads_a_guardian_ledger(self):
        ledger = {'rounds': [{'represented': ['painter', 'pirosmani', 'storybook']}]}
        drawn = loop.draw(self.seats, ledger, 'teams', jury_size=5, proposers=3)
        self.assertEqual(drawn['jury'][0], 'gate')
        self.assertEqual(len(set(drawn['jury'] + drawn['proposers'])), 8)
        # Guardians already represented count for their whole team, which sits out first.
        self.assertNotIn('studio', drawn['jury'])
        self.assertNotIn('storytellers', drawn['jury'])

if __name__ == '__main__':
    unittest.main()
