"""Linux simulator-driver checks. Every Apple command goes to a fake xcrun on PATH."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from factory.taste import cli, loop, play, runners
from factory.taste.simctl import DEFAULT_DEVICE, SimctlDriver
from tools.factory.test_play import recording, state


FAKE_XCRUN = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, signal, sys, time
root = pathlib.Path(os.environ['FAKE_SIMCTL_ROOT'])
config = json.loads((root / 'config.json').read_text())
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps({'argv': sys.argv, 'mailbox': os.environ.get('TEST_RUNNER_PLAY_MAILBOX')}) + '\n')
def publish(path, data):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data))
    temporary.replace(path)
def stop(signum, frame):
    (root / ('runner-stopped' if args[0] == 'xcodebuild' else 'video-stopped')).write_text(str(signum))
    if args[0] == 'simctl':
        pathlib.Path(args[-1]).write_bytes(b'fake video finalized by SIGINT')
    sys.exit(0)
if config.get('fail_command') == args[1]:
    sys.stderr.write('scripted command failure')
    sys.exit(9)
if config.get('sleep_command') == args[1]:
    print('waiting in fake command', flush=True)
    time.sleep(5)
if args == ['simctl', 'list', 'devices', '--json']:
    print(json.dumps({'devices': config['devices']}))
elif args[:2] == ['simctl', 'boot'] or args[:2] == ['simctl', 'bootstatus']:
    pass
elif args[:2] == ['simctl', 'ui'] or args[:2] == ['simctl', 'install']:
    pass
elif args[:2] == ['simctl', 'io'] and args[3] == 'screenshot':
    index = int((root / 'index').read_text())
    shutil.copyfile(root / 'script' / f'{index:03}.png', args[-1])
elif args[:2] == ['simctl', 'io'] and args[3] == 'recordVideo':
    signal.signal(signal.SIGINT, stop)
    while True: time.sleep(.01)
elif args[0] == 'xcodebuild':
    signal.signal(signal.SIGINT, stop)
    mailbox = pathlib.Path(os.environ['TEST_RUNNER_PLAY_MAILBOX'])
    # Emulate xcodebuild stripping TEST_RUNNER_ before the Swift test reads PLAY_MAILBOX.
    os.environ['PLAY_MAILBOX'] = str(mailbox)
    (root / 'runner-env.json').write_text(json.dumps({'PLAY_MAILBOX': os.environ['PLAY_MAILBOX']}))
    data = json.loads((root / 'script/recording.json').read_text())
    (root / 'index').write_text('0')
    if config.get('hello') == 'die': sys.exit(7)
    if config.get('hello') != 'timeout':
        hello = {'version': 1, 'state': data['initial']['state']}
        if config.get('hello') == 'invalid': hello['state']['area_count'] = True
        publish(mailbox / 'hello.json', hello)
    for n, turn in enumerate(data['turns'], 1):
        move = mailbox / f'move-{n}.json'
        while not move.exists(): time.sleep(.01)
        actual = json.loads(move.read_text())
        if config.get('die_move') == n: sys.exit(8)
        if config.get('timeout_move') == n:
            while True: time.sleep(.01)
        if config.get('error_move') == n or actual != turn['move']:
            publish(mailbox / f'error-{n}.json', {'reason': 'scripted move rejection'})
            break
        (root / 'index').write_text(str(n))
        response = {'state': turn['state']}
        if config.get('bad_state_move') == n: response['state']['filled_areas'] = [99]
        if config.get('bad_json_move') == n:
            (mailbox / f'done-{n}.json').write_text('{broken')
        else:
            publish(mailbox / f'done-{n}.json', response)
    while True: time.sleep(.01)
else:
    sys.stderr.write('unexpected fake xcrun command: ' + repr(args))
    sys.exit(99)
'''


class SimctlTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        fake = self.bin / 'xcrun'
        fake.write_text(FAKE_XCRUN)
        fake.chmod(0o755)
        self.environment = patch.dict(os.environ, {
            'PATH': str(self.bin) + os.pathsep + os.environ['PATH'],
            'FAKE_SIMCTL_ROOT': str(self.root),
            'PYTHONDONTWRITEBYTECODE': '1',
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        recording(self.root / 'script')
        self.config = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [
            {'name': DEFAULT_DEVICE, 'udid': 'FAKE-IPAD', 'isAvailable': True, 'state': 'Shutdown'}]}}
        self.save_config()
        self.app = self.root / 'Paint by Moonlight.app'
        self.app.mkdir()
        self.xctestrun = self.root / 'UI tests.xctestrun'
        self.xctestrun.write_text('fake built test bundle')

    def save_config(self, **updates):
        self.config.update(updates)
        (self.root / 'config.json').write_text(json.dumps(self.config))

    def driver(self, **options):
        driver = SimctlDriver(self.root / 'host', app=self.app, xctestrun=self.xctestrun,
                              test='PaintByNumberUITests/PlayTests/testMailbox',
                              timeout=options.pop('timeout', 2), **options)
        self.addCleanup(driver.close)
        return driver

    def calls(self):
        return [json.loads(line) for line in (self.root / 'calls.jsonl').read_text().splitlines()]

    def test_three_move_session_atomic_mailbox_commands_video_and_mock_replay(self):
        with self.driver(appearance='dark', video=True, mailbox=self.root / 'wire') as driver:
            session = play.Session.create(self.root / 'session', driver, 'moon')
            self.assertEqual(driver.state(), state())
            published = []
            real_replace = os.replace

            def checked_replace(source, target):
                self.assertEqual(Path(source).parent, Path(target).parent)
                published.append((Path(target).name, json.loads(Path(source).read_text())))
                real_replace(source, target)

            with patch('factory.taste.simctl.os.replace', side_effect=checked_replace):
                for area in range(1, 4):
                    session.apply({'move': {'do': 'fill', 'area': area}, 'reason': f'Paint area {area}.'})
            self.assertEqual(published, [(f'move-{i}.json', {'do': 'fill', 'area': i}) for i in range(1, 4)])
            self.assertEqual(session.status(), 'complete')
            self.assertEqual(driver.state(), state([1, 2, 3]))
            self.assertFalse(list(driver.mailbox.glob('*.tmp')))
            copied = driver.state()
            copied['filled_areas'].clear()
            self.assertEqual(driver.state()['filled_areas'], [1, 2, 3])
            play.replay(session.path, self.root / 'replay')
            play.replay(session.path, self.root / 'independent-replay', self.root / 'script')
        self.assertEqual((self.root / 'video-stopped').read_text(), '2')
        self.assertEqual((self.root / 'runner-stopped').read_text(), '2')
        self.assertIn(b'SIGINT', (driver.folder / 'video.mp4').read_bytes())
        calls = self.calls()
        commands = [c['argv'][1:] for c in calls]
        self.assertEqual(commands[:5], [
            ['simctl', 'list', 'devices', '--json'], ['simctl', 'boot', 'FAKE-IPAD'],
            ['simctl', 'bootstatus', 'FAKE-IPAD', '-b'], ['simctl', 'ui', 'FAKE-IPAD', 'appearance', 'dark'],
            ['simctl', 'install', 'FAKE-IPAD', str(self.app)]])
        test = next(c for c in calls if c['argv'][1] == 'xcodebuild')
        self.assertEqual(test['mailbox'], str(driver.mailbox))
        self.assertEqual(json.loads((self.root / 'runner-env.json').read_text()), {'PLAY_MAILBOX': str(driver.mailbox)})
        self.assertIn('-only-testing:PaintByNumberUITests/PlayTests/testMailbox', test['argv'])
        self.assertIn('platform=iOS Simulator,id=FAKE-IPAD', test['argv'])
        logged = [json.loads(line) for line in (driver.folder / 'commands.jsonl').read_text().splitlines()]
        self.assertEqual(sorted(c['argv'] for c in logged), sorted(['xcrun', *c] for c in commands))
        self.assertTrue(all(Path(c['argv'][0]) == self.bin / 'xcrun' for c in calls))
        self.assertEqual(sum(c[:2] == ['simctl', 'io'] and c[3] == 'screenshot' for c in commands), 4)
        if os.environ.get('SIMCTL_DRY_RUN'):
            shutil.copytree(self.root, Path(os.environ['SIMCTL_DRY_RUN']), ignore=shutil.ignore_patterns('bin'))

    def test_pending_move_and_invalid_move_do_not_publish_or_advance(self):
        driver = self.driver()
        for move in ({'do': 'fill', 'area': 4}, {'do': 'erase'}, {'do': 'wait', 'seconds': float('nan')}):
            with self.assertRaises(ValueError): driver.perform(move)
        self.assertEqual(driver.number, 0)
        self.assertFalse(list(driver.mailbox.glob('move-*')))
        driver.perform({'do': 'fill', 'area': 1})
        self.assertEqual(driver.state(), state())
        with self.assertRaisesRegex(ValueError, 'settle'): driver.perform({'do': 'fill', 'area': 2})
        with self.assertRaisesRegex(ValueError, 'settle'): driver.screenshot()
        driver.settle()
        self.assertEqual(driver.state(), state([1]))
        driver.settle()  # No second acknowledgement required.

    def test_all_move_variants_cross_the_mailbox_unchanged(self):
        moves = [{'do': 'tap', 'label': 'Paint 1'},
                 {'do': 'drag', 'from': {'x': 10, 'y': 20}, 'to': {'x': 50.5, 'y': 80}, 'steps': 12},
                 {'do': 'wait', 'seconds': .25}, {'do': 'screenshot'}, {'do': 'fill', 'area': 1}]
        shutil.rmtree(self.root / 'script')
        recording(self.root / 'script', moves)
        with self.driver() as driver:
            for n, move in enumerate(moves, 1):
                driver.perform(move)
                driver.settle()
                self.assertEqual(json.loads((driver.mailbox / f'move-{n}.json').read_text()), move)
                self.assertEqual(driver.number, n)
            self.assertEqual(driver.state(), state([1]))

    def test_error_response_is_fatal_and_retains_last_settled_state(self):
        self.save_config(error_move=1)
        driver = self.driver()
        session = play.Session.create(self.root / 'session', driver, 'moon')
        with self.assertRaisesRegex(RuntimeError, 'UI test rejected move 1: scripted move rejection'):
            session.apply({'move': {'do': 'fill', 'area': 1}, 'reason': 'Start.'})
        self.assertEqual(driver.state(), state())
        self.assertFalse(session.turns())
        with self.assertRaisesRegex(RuntimeError, 'move 1 failed'): driver.perform({'do': 'fill', 'area': 1})
        self.assertEqual(driver.number, 1)

    def test_runner_dies_before_acknowledgement(self):
        self.save_config(die_move=1)
        driver = self.driver()
        driver.perform({'do': 'fill', 'area': 1})
        with self.assertRaisesRegex(RuntimeError, 'runner exited 8.*test.log'): driver.settle()
        self.assertEqual(driver.state(), state())

    def test_move_timeout_and_context_cleanup(self):
        self.save_config(timeout_move=1)
        driver = self.driver(timeout=.5)
        with self.assertRaisesRegex(RuntimeError, 'timed out.*done-1.json or error-1.json'):
            with driver:
                driver.perform({'do': 'fill', 'area': 1})
                driver.settle()
        self.assertIsNotNone(driver.runner.poll())
        (driver.mailbox / 'done-1.json').write_text(json.dumps({'state': state([1])}))
        with self.assertRaisesRegex(RuntimeError, 'closed'): driver.settle()
        self.assertEqual(driver.state(), state())

    def test_missing_unavailable_and_ambiguous_devices(self):
        device = self.config['devices'][next(iter(self.config['devices']))]
        for devices, message in [({}, 'no available simulator'),
                                 ({'iOS': [{'name': DEFAULT_DEVICE, 'isAvailable': False}]}, 'no available simulator'),
                                 ({'iOS-26': device, 'iOS-27': device}, 'ambiguous.*FAKE-IPAD')]:
            with self.subTest(devices=devices):
                self.save_config(devices=devices)
                with self.assertRaisesRegex(ValueError, message): self.driver()
                shutil.rmtree(self.root / 'host')
        self.assertTrue(all(c['argv'][1:] == ['simctl', 'list', 'devices', '--json'] for c in self.calls()))

    def test_already_booted_device_skips_boot(self):
        self.config['devices'][next(iter(self.config['devices']))][0]['state'] = 'Booted'
        self.save_config()
        with self.driver(): pass
        commands = [c['argv'][1:] for c in self.calls()]
        self.assertNotIn(['simctl', 'boot', 'FAKE-IPAD'], commands)
        self.assertIn(['simctl', 'bootstatus', 'FAKE-IPAD', '-b'], commands)

    def test_hello_exit_timeout_and_invalid_state_clean_up_runner(self):
        for mode, message in [('die', 'runner exited 7'), ('timeout', 'timed out.*hello.json'),
                              ('invalid', 'area_count')]:
            with self.subTest(mode=mode):
                self.save_config(hello=mode)
                with self.assertRaisesRegex((ValueError, RuntimeError), message): self.driver(timeout=.5)
                shutil.rmtree(self.root / 'host')
        self.assertEqual((self.root / 'runner-stopped').read_text(), '2')

    def test_invalid_acknowledgement_is_fatal(self):
        for mode, message in [('bad_state_move', 'filled_areas exceeds'), ('bad_json_move', 'invalid mailbox response')]:
            with self.subTest(mode=mode):
                self.save_config(**{mode: 1})
                with self.driver() as driver:
                    driver.perform({'do': 'fill', 'area': 1})
                    with self.assertRaisesRegex(RuntimeError, message): driver.settle()
                    self.assertEqual(driver.state(), state())
                shutil.rmtree(self.root / 'host')
                self.config.pop(mode)

    def test_conflicting_acknowledgements_and_reused_numbers_fail(self):
        driver = self.driver()
        (driver.mailbox / 'done-1.json').write_text(json.dumps({'state': state([1])}))
        with self.assertRaisesRegex(RuntimeError, 'number 1 already exists'):
            driver.perform({'do': 'fill', 'area': 1})
        (driver.mailbox / 'done-1.json').unlink()
        driver.perform({'do': 'fill', 'area': 1})
        deadline = time.monotonic() + 2
        while not (driver.mailbox / 'done-1.json').exists() and time.monotonic() < deadline:
            time.sleep(.01)
        (driver.mailbox / 'error-1.json').write_text(json.dumps({'reason': 'conflict'}))
        with self.assertRaisesRegex(RuntimeError, 'conflicting mailbox responses'): driver.settle()

    def test_command_error_and_validation_prevent_unwanted_writes(self):
        self.save_config(fail_command='bootstatus')
        with self.assertRaisesRegex(RuntimeError, 'bootstatus exited 9: scripted command failure'): self.driver()
        self.assertFalse(any(c['argv'][1] == 'xcodebuild' for c in self.calls()))
        shutil.rmtree(self.root / 'host')
        for timeout in (0, -1, float('nan'), float('inf'), True):
            with self.assertRaisesRegex(ValueError, 'timeout'): self.driver(timeout=timeout)
        self.assertFalse((self.root / 'host').exists())
        with self.assertRaisesRegex(ValueError, 'outside the repository'):
            SimctlDriver(loop.REPO, app=self.app, xctestrun=self.xctestrun, test='test')
        host = self.root / 'host'
        host.mkdir()
        (host / 'hello.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'must be empty'): self.driver()
        (host / 'hello.json').unlink()
        (host / 'commands.jsonl').symlink_to(self.root / 'victim')
        with self.assertRaises(ValueError): self.driver()
        self.assertFalse((self.root / 'victim').exists())

    def test_command_timeout_preserves_diagnostic_output(self):
        self.save_config(sleep_command='bootstatus')
        with self.assertRaisesRegex(RuntimeError, 'bootstatus timed out.*bootstatus.log'):
            self.driver(timeout=.5)
        self.assertEqual((self.root / 'host/bootstatus.log').read_text(), 'waiting in fake command\n')
        self.assertFalse(any(c['argv'][1] == 'xcodebuild' for c in self.calls()))

    def test_cli_simctl_foreground_collects_replies_and_replays(self):
        run = self.root / 'cli-session'
        output = self.root / 'cli-host'
        command = [sys.executable, '-m', 'factory.taste', '--run', str(run), '--out', str(output),
                   'play', 'new', '--driver', 'simctl', '--guardian', 'moon', '--app', str(self.app),
                   '--xctestrun', str(self.xctestrun), '--test', 'UITests/Play/testMailbox', '--video']
        with (self.root / 'cli.stdout').open('w') as stdout, (self.root / 'cli.stderr').open('w') as stderr:
            process = subprocess.Popen(command, stdout=stdout, stderr=stderr)
        try:
            deadline = time.monotonic() + 10
            for area in range(1, 4):
                job_path = run / f'jobs/{area:03}/player-moon.json'
                while not job_path.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue(job_path.exists(), (self.root / 'cli.stderr').read_text())
                job = loop.load(job_path)
                if area == 1:
                    loop.save(runners.destination(run, job), {'move': {'do': 'fill', 'area': 4}, 'reason': 'Invalid.'})
                    retry_path = run / 'retries/001/player-moon.json'
                    while not retry_path.exists() and time.monotonic() < deadline: time.sleep(.02)
                    self.assertTrue(retry_path.exists())
                    job = {**job, 'attempt': 1}
                loop.save(runners.destination(run, job), {'move': {'do': 'fill', 'area': area}, 'reason': 'Fill the next area.'})
            self.assertEqual(process.wait(timeout=5), 0, (self.root / 'cli.stderr').read_text())
        finally:
            if process.poll() is None:
                process.send_signal(2)
                process.wait(timeout=15)
        self.assertEqual(json.loads((self.root / 'cli.stdout').read_text())['status'], 'complete')
        self.assertTrue((output / 'video.mp4').exists())
        play.replay(run, self.root / 'cli-replay')

    def test_cli_requires_driver_inputs_without_apple_commands(self):
        for args, message in [(['new', '--guardian', 'moon'], 'requires --recording'),
                              (['new', '--guardian', 'moon', '--driver', 'simctl'], 'requires --app')]:
            with self.subTest(args=args), patch('sys.stderr') as stderr:
                with self.assertRaises(SystemExit) as caught:
                    cli.main(['--run', str(self.root / 'session'), 'play', *args])
                self.assertEqual(caught.exception.code, 1)
                self.assertIn(message, str(stderr.write.call_args))
        self.assertFalse((self.root / 'calls.jsonl').exists())


if __name__ == '__main__':
    unittest.main()
