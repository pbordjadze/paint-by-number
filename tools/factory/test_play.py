"""Linux play checks; generated screenshots and sessions stay in TMPDIR outside the repo."""
import contextlib
import io
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

from factory.taste import cli, loop, play, runners, schema


def state(filled=(), *, count=3, screen='painting', paint=1):
    return {'screen': screen, 'selected_paint': paint, 'filled_areas': list(filled), 'area_count': count}


def recording(folder, moves=None):
    folder.mkdir(parents=True)
    moves = moves or [{'do': 'fill', 'area': i} for i in range(1, 4)]
    observations = []
    filled = []
    for i in range(len(moves) + 1):
        if i and moves[i - 1]['do'] == 'fill':
            filled.append(moves[i - 1]['area'])
        image = Image.new('RGB', (240, 160), '#f4f1ea')
        draw = ImageDraw.Draw(image)
        for area in range(1, 4):
            draw.rectangle(((area - 1) * 80, 0, area * 80 - 1, 159),
                           fill=('#91b5a0' if area in filled else '#f4f1ea'), outline='#2a2622', width=2)
            draw.text(((area - 1) * 80 + 36, 76), str(area), fill='#2a2622')
        name = f'{i:03}.png'
        image.save(folder / name)
        observations.append({'screenshot': name, 'state': state(filled),
                             **({'move': moves[i - 1]} if i else {})})
    loop.save(folder / 'recording.json', {'version': 1, 'initial': observations[0],
                                        'turns': observations[1:]})
    return folder


class PlayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = recording(self.root / 'recording')
        self.run = self.root / 'session'

    def tearDown(self):
        self.temp.cleanup()

    def session(self, budget=100):
        return play.Session.create(self.run, play.MockDriver(self.source), 'moon', budget=budget)

    def reply(self, session, move, reason='Fill the next numbered area.', *, retry=False):
        job = session.job()
        path = runners.destination(session.path, {**job, 'attempt': int(retry)})
        loop.save(path, {'move': move, 'reason': reason})
        return path

    def test_three_area_session_jobs_history_and_completion(self):
        session = self.session()
        for area in range(1, 4):
            job = session.job()
            self.assertEqual(job, session.job())
            self.assertIn(session.rules['guardian']['charter_text'], job['prompt'])
            self.assertIn(job['images'][0], job['prompt'])
            self.assertEqual(job['state'], state(range(1, area)))
            self.assertEqual(len(job['history']), area - 1)
            self.assertEqual(job['reply_schema'], play.REPLY_SCHEMA)
            self.reply(session, {'do': 'fill', 'area': area})
            result = session.collect()
            self.assertEqual(result['status'], 'accepted')
            self.assertEqual(result['turn']['state']['filled_areas'], list(range(1, area + 1)))
            self.assertTrue((self.run / result['turn']['screenshot']).is_file())
        self.assertEqual(session.status(), 'complete')
        self.assertEqual(len(session.turns()), 3)
        self.assertTrue((self.run / 'contact.png').is_file())
        with self.assertRaisesRegex(ValueError, 'ended: complete'):
            session.job()
        with self.assertRaisesRegex(ValueError, 'ended: complete'):
            session.apply({'move': {'do': 'screenshot'}, 'reason': 'Look again.'})
        # Optional retained dry run is plumbing evidence, not a guardian taste decision.
        if os.environ.get('PLAY_DRY_RUN'):
            destination = Path(os.environ['PLAY_DRY_RUN'])
            shutil.copytree(self.run, destination / 'session')
            shutil.copytree(self.source, destination / 'recording')
            play.replay(destination / 'session', destination / 'replay', destination / 'recording')

    def test_all_move_variants_and_settle_boundary(self):
        moves = [{'do': 'tap', 'label': 'Paint 1'},
                 {'do': 'drag', 'from': {'x': 10, 'y': 20}, 'to': {'x': 50.5, 'y': 80}, 'steps': 12},
                 {'do': 'wait', 'seconds': 0.25}, {'do': 'screenshot'}, {'do': 'fill', 'area': 1}]
        folder = recording(self.root / 'all-moves', moves)
        driver = play.MockDriver(folder)
        before = driver.screenshot()
        driver.perform(moves[0])
        self.assertEqual(driver.screenshot(), before)
        with self.assertRaisesRegex(ValueError, 'settle'):
            driver.perform(moves[0])
        driver.settle()
        self.assertNotEqual(driver.screenshot(), before)
        for move in moves[1:]:
            driver.perform(move)
            driver.settle()
        self.assertEqual(driver.state()['filled_areas'], [1])
        with self.assertRaisesRegex(ValueError, 'exhausted'):
            driver.perform({'do': 'screenshot'})

    def test_move_schema_rejects_unknown_malformed_and_nonfinite(self):
        malformed = [None, [], {}, {'do': 'erase'}, {'do': 'fill'},
                     {'do': 'fill', 'area': True}, {'do': 'fill', 'area': 0},
                     {'do': 'fill', 'area': 1.0}, {'do': 'tap', 'label': '   '},
                     {'do': 'wait', 'seconds': -1}, {'do': 'wait', 'seconds': float('nan')},
                     {'do': 'wait', 'seconds': float('inf')}, {'do': 'screenshot', 'extra': 1},
                     {'do': 'drag', 'from': [0, 0], 'to': {'x': 1, 'y': 2}, 'steps': 2},
                     {'do': 'drag', 'from': {'x': -1, 'y': 0}, 'to': {'x': 1, 'y': 2}, 'steps': 2},
                     {'do': 'drag', 'from': {'x': 0, 'y': 0}, 'to': {'x': 1, 'y': 2}, 'steps': 0}]
        schema.check(play.MOVE_SCHEMA)
        for move in malformed:
            with self.subTest(move=move), self.assertRaises(ValueError) as error:
                play.validate_move(move)
            self.assertTrue(str(error.exception))
        with self.assertRaisesRegex(ValueError, 'area_count'):
            play.validate_move({'do': 'fill', 'area': 4}, state())

    def test_schema_one_of_requires_exactly_one_matching_variant(self):
        branch = schema.obj({'do': {'type': 'string', 'enum': ['screenshot']}})
        self.assertFalse(schema.validate({'do': 'screenshot'}, {'oneOf': [branch]}))
        self.assertTrue(schema.validate({'do': 'screenshot'}, {'oneOf': [branch, {'type': 'object'}]}))
        for rule in [{'oneOf': []}, {'oneOf': [ {'pattern': '.*'} ]}]:
            with self.assertRaises(ValueError):
                schema.check(rule)

    def test_rejection_records_reason_and_retries_once_without_advancing(self):
        session = self.session()
        self.reply(session, {'do': 'fill', 'area': 4})
        result = session.collect()
        self.assertEqual(result['status'], 'rejected')
        self.assertIn('area_count', result['reason'])
        self.assertEqual(session.driver.index, 0)
        self.assertFalse(session.turns())
        retry = loop.load(self.run / 'retries/001/player-moon.json')
        self.assertEqual(retry['attempt'], 1)
        self.assertIn(result['reason'], retry['prompt'])
        self.assertEqual(session.collect()['status'], 'waiting')
        self.reply(session, {'do': 'fill', 'area': 1}, retry=True)
        self.assertEqual(session.collect()['status'], 'accepted')
        self.assertTrue((self.run / 'rejections/001/player-moon-0.json').exists())
        self.assertEqual(session.driver.index, 1)

    def test_failed_repair_and_malformed_json_are_rejected(self):
        session = self.session()
        path = self.reply(session, {'do': 'fill', 'area': 1})
        path.write_text('{bad json')
        self.assertEqual(session.collect()['status'], 'rejected')
        self.reply(session, {'do': 'fill', 'area': 1}, reason='Two\nlines.', retry=True)
        self.assertEqual(session.collect()['status'], 'blocked')
        self.reply(session, {'do': 'fill', 'area': 1}, retry=True)
        self.assertEqual(session.collect()['status'], 'blocked')
        self.assertEqual(session.driver.index, 0)
        self.assertFalse(session.turns())

    def test_unexpected_valid_move_is_rejected_without_advancing(self):
        session = self.session()
        self.reply(session, {'do': 'fill', 'area': 2})
        result = session.collect()
        self.assertEqual(result['status'], 'rejected')
        self.assertIn('mock expected', result['reason'])
        self.assertEqual(session.driver.index, 0)

    def test_budget_and_initially_complete_picture(self):
        session = self.session(budget=1)
        session.apply({'move': {'do': 'fill', 'area': 1}, 'reason': 'Start.'})
        self.assertEqual(session.status(), 'budget')
        with self.assertRaisesRegex(ValueError, 'ended: budget'):
            session.job()
        play.replay(self.run, self.root / 'budget-replay')
        data = loop.load(self.source / 'recording.json')
        data['initial']['state'] = state(range(1, 4))
        data['turns'] = []
        loop.save(self.source / 'recording.json', data)
        complete = play.Session.create(self.root / 'complete', play.MockDriver(self.source), 'moon')
        self.assertEqual(complete.status(), 'complete')
        self.assertEqual(complete.turns(), [])
        play.replay(complete.path, self.root / 'complete-replay')

    def test_history_keeps_only_last_few_moves_and_turn_order_is_numeric(self):
        moves = [{'do': 'wait', 'seconds': i} for i in range(6)]
        driver = play.MockDriver(recording(self.root / 'history', moves))
        session = play.Session.create(self.run, driver, 'moon')
        for i, move in enumerate(moves):
            session.apply({'move': move, 'reason': f'Observe turn {i}.'})
        self.assertEqual(session.job()['history'], [
            {'move': move, 'reason': f'Observe turn {i}.'} for i, move in enumerate(moves) if i > 0])
        # Budgets above 999 still use chronological order with minimum-width filenames.
        loop.save(self.run / 'turns/999.json', {'turn': 999})
        loop.save(self.run / 'turns/1000.json', {'turn': 1000})
        self.assertEqual([turn['turn'] for turn in session.turns()], [1, 2, 3, 4, 5, 6, 999, 1000])

    def test_mock_rejects_invalid_state_and_escaping_frame(self):
        for bad_state in [state([1, 1]), state([4]), state(count=True),
                          {**state(), 'selected_paint': 0}, {**state(), 'other': 1}]:
            with self.subTest(state=bad_state), self.assertRaises(ValueError):
                play.validate_state(bad_state)
        data = loop.load(self.source / 'recording.json')
        data['initial']['screenshot'] = '../outside.png'
        loop.save(self.source / 'recording.json', data)
        with self.assertRaisesRegex(ValueError, 'leaves its folder'):
            play.MockDriver(self.source)

    def test_replay_bytes_and_independent_recording_mismatch(self):
        session = self.session()
        for area in range(1, 4):
            session.apply({'move': {'do': 'fill', 'area': area}, 'reason': f'Paint area {area}.'})
        for name, folder in [('self', None), ('independent', self.source)]:
            out = play.replay(self.run, self.root / name, folder)
            for path in out.rglob('*'):
                if path.is_file():
                    self.assertEqual(path.read_bytes(), (self.run / path.relative_to(out)).read_bytes())
        with self.assertRaisesRegex(ValueError, 'separate'):
            play.replay(self.run, self.run / 'replay')
        data = loop.load(self.source / 'recording.json')
        data['turns'][0]['state']['selected_paint'] = 2
        loop.save(self.source / 'recording.json', data)
        with self.assertRaisesRegex(ValueError, 'replay differs'):
            play.replay(self.run, self.root / 'mismatch', self.source)

    def test_driver_settles_before_observation(self):
        class CheckedDriver:
            def __init__(driver):
                driver.mock = play.MockDriver(self.source)
                driver.settled = False

            def perform(driver, move):
                driver.mock.perform(move)
                driver.settled = False

            def settle(driver):
                driver.mock.settle()
                driver.settled = True

            def state(driver):
                self.assertTrue(driver.settled)
                return driver.mock.state()

            def screenshot(driver):
                self.assertTrue(driver.settled)
                return driver.mock.screenshot()
        session = play.Session.create(self.run, CheckedDriver(), 'moon')
        session.apply({'move': {'do': 'fill', 'area': 1}, 'reason': 'Start.'})

    def test_cli_resumes_frozen_recording_and_replays(self):
        def command(*args):
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                result = cli.main(['--run', str(self.run), '--out', str(self.root / 'cli-replay'),
                                   'play', *args])
            return result, json.loads(stdout.getvalue())
        self.assertEqual(command('new', '--recording', str(self.source), '--guardian', 'moon')[0], 0)
        shutil.rmtree(self.source)  # Resuming must only use the frozen recording.
        for area in range(1, 4):
            _, job = command('jobs')
            self.assertEqual(command('collect')[0], 1)
            loop.save(runners.destination(self.run, job),
                      {'move': {'do': 'fill', 'area': area}, 'reason': 'Paint the next area.'})
            code, result = command('collect')
            self.assertEqual(code, 0)
            self.assertEqual(result['status'], 'accepted')
        self.assertEqual(command('report')[1]['session']['status'], 'complete')
        self.assertEqual(command('replay')[0], 0)


if __name__ == '__main__':
    unittest.main()
