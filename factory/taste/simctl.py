"""Host simulator driver. The wire contract is factory/pieces/play/README.md.

Construction boots and installs, starts the UI test, and waits for its settled hello.
Use as a context manager so failures and interrupts also stop the runner and video.
All Apple commands go through _command, as argument arrays without a shell.
"""
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

from . import paths
from .kit import outside_repo
from .play import validate_move, validate_state

DEFAULT_DEVICE = 'iPad Pro 13-inch (M5)'


class SimctlDriver:
    def __init__(self, folder, *, app, xctestrun, test, device=DEFAULT_DEVICE,
                 appearance='light', mailbox=None, timeout=60, video=False):
        if (not isinstance(timeout, (int, float)) or isinstance(timeout, bool)
                or not math.isfinite(timeout) or timeout <= 0):
            raise ValueError('timeout must be a finite positive number of seconds')
        if appearance not in ('light', 'dark'):
            raise ValueError('appearance must be light or dark')
        if not isinstance(test, str) or not test.strip():
            raise ValueError('test must name a UI test')
        self.app, self.xctestrun = Path(app).resolve(), Path(xctestrun).resolve()
        if not self.app.is_dir() or self.app.suffix != '.app':
            raise ValueError(f'app must be an existing .app directory: {self.app}')
        if not self.xctestrun.is_file():
            raise ValueError(f'xctestrun file does not exist: {self.xctestrun}')
        self.folder = outside_repo(folder)
        self.mailbox = outside_repo(mailbox) if mailbox is not None else paths.contained(self.folder, 'mailbox')
        # No stale hello or acknowledgements, and no overwriting another session's logs.
        for directory in (self.folder, self.mailbox):
            if directory.exists() and any(directory.iterdir()):
                raise ValueError(f'simulator session directory must be empty: {directory}')
        self.folder.mkdir(parents=True, exist_ok=True)
        self.mailbox.mkdir(parents=True, exist_ok=True)
        self.timeout, self.test = timeout, test
        self.runner = self.recorder = None
        self.udid = ''
        self.closed = False
        self.pending = None
        self.number = self.shot_number = 0
        self._state = None
        self.failure = None
        try:
            devices = json.loads(self._command('list'))['devices']
            matches = [(runtime, d) for runtime, entries in devices.items() for d in entries
                       if d.get('name') == device and d.get('isAvailable', False)]
            if not matches:
                raise ValueError(f'no available simulator named {device!r}')
            if len(matches) != 1:
                raise ValueError(f'ambiguous simulator name {device!r}: ' +
                                 ', '.join(f"{runtime}: {d['udid']}" for runtime, d in matches))
            selected = matches[0][1]
            self.udid = selected['udid']
            if selected.get('state') != 'Booted':
                self._command('boot')
            self._command('bootstatus')
            self._command('appearance', appearance)
            self._command('install')
            if video:
                self.recorder = self._command('video', background=True)
            self.runner = self._command('test', background=True)
            hello = self._wait(('hello.json',))
            if (not isinstance(hello, dict) or set(hello) != {'version', 'state'}
                    or type(hello['version']) is not int or hello['version'] != 1):
                raise ValueError('hello.json needs version 1 and state')
            self._state = validate_state(hello['state'])
        except BaseException:
            self.close()
            raise

    def _command(self, action, *args, background=False):
        """Build, log and execute every command here; background output goes to files."""
        commands = {
            'list': ['simctl', 'list', 'devices', '--json'],
            'boot': ['simctl', 'boot', self.udid],
            'bootstatus': ['simctl', 'bootstatus', self.udid, '-b'],
            'appearance': ['simctl', 'ui', self.udid, 'appearance', *args],
            'install': ['simctl', 'install', self.udid, str(self.app)],
            'test': ['xcodebuild', 'test-without-building', '-xctestrun', str(self.xctestrun),
                     f'-only-testing:{self.test}', '-destination', f'platform=iOS Simulator,id={self.udid}',
                     '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1'],
            'screenshot': ['simctl', 'io', self.udid, 'screenshot', '--type=png', *args],
            'video': ['simctl', 'io', self.udid, 'recordVideo',
                      str(paths.contained(self.folder, 'video.mp4'))],
        }
        command = ['xcrun', *commands[action]]
        env = os.environ.copy()
        extra = {'TEST_RUNNER_PLAY_MAILBOX': str(self.mailbox)} if action == 'test' else {}
        env.update(extra)
        with paths.contained(self.folder, 'commands.jsonl').open('a') as log:
            log.write(json.dumps({'argv': command, 'env': extra}) + '\n')
        log_path = paths.contained(self.folder, f'{action}.log')
        try:
            if background:
                with log_path.open('ab') as log:
                    return subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=self.timeout)
            with log_path.open('a') as log:
                log.write(result.stdout + result.stderr)
            if result.returncode:
                raise RuntimeError(f'{action} exited {result.returncode}: {result.stderr.strip() or result.stdout.strip()} (log: {log_path})')
            return result.stdout
        except subprocess.TimeoutExpired as error:
            with log_path.open('a') as log:
                for output in (error.stdout, error.stderr):
                    if output:
                        log.write(output.decode(errors='replace') if isinstance(output, bytes) else output)
            raise RuntimeError(f'{action} timed out after {self.timeout:g}s (log: {log_path})') from error
        except OSError as error:
            raise RuntimeError(f'cannot run {command[0]} for {action}: {error}') from error

    def check_alive(self):
        if self.closed:
            raise RuntimeError('simulator driver is closed')
        if self.failure:
            raise RuntimeError(self.failure)
        if self.runner is not None and self.runner.poll() is not None:
            raise RuntimeError(f'UI-test runner exited {self.runner.returncode} before the next mailbox response (log: {self.folder / "test.log"})')
        if self.recorder is not None and self.recorder.poll() is not None:
            raise RuntimeError(f'video recorder exited {self.recorder.returncode} (log: {self.folder / "video.log"})')

    def _wait(self, names):
        deadline = time.monotonic() + self.timeout
        while True:
            candidates = [paths.contained(self.mailbox, name) for name in names]
            found = [path for path in candidates if path.exists()]
            if len(found) > 1:
                raise RuntimeError(f'conflicting mailbox responses: {", ".join(names)}')
            if found:
                try:
                    data = json.loads(found[0].read_text())
                except (OSError, ValueError) as error:
                    raise RuntimeError(f'invalid mailbox response {found[0].name}: {error}') from error
                return data
            self.check_alive()
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError(f'timed out after {self.timeout:g}s waiting for {" or ".join(names)} in {self.mailbox}')
            time.sleep(min(0.05, remaining))

    def perform(self, move):
        validate_move(move, self._state)
        self.check_alive()
        if self.pending is not None:
            raise ValueError('settle the previous move first')
        number = self.number + 1
        target = paths.contained(self.mailbox, f'move-{number}.json')
        if any(paths.contained(self.mailbox, f'{prefix}-{number}.json').exists()
               for prefix in ('move', 'done', 'error')):
            raise RuntimeError(f'mailbox number {number} already exists')
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=self.mailbox, prefix='.move-', suffix='.tmp', delete=False) as stream:
                temporary = Path(stream.name)
                json.dump(move, stream, allow_nan=False)
                stream.write('\n')
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, target)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        self.number = self.pending = number

    def settle(self):
        if self.closed or self.failure:
            self.check_alive()
        if self.pending is None:
            self.check_alive()
            return
        n = self.pending
        try:
            response = self._wait((f'done-{n}.json', f'error-{n}.json'))
            if paths.contained(self.mailbox, f'error-{n}.json').exists():
                if (not isinstance(response, dict) or set(response) != {'reason'}
                        or not isinstance(response['reason'], str) or not response['reason'].strip()):
                    raise ValueError(f'error-{n}.json needs a nonempty reason')
                raise RuntimeError(f'UI test rejected move {n}: {response["reason"]}')
            if not isinstance(response, dict) or set(response) != {'state'}:
                raise ValueError(f'done-{n}.json needs state')
            self._state = validate_state(response['state'])
            self.pending = None
        except (ValueError, OSError, RuntimeError) as error:
            # A published move may have changed the app: never treat it as a retryable reply.
            self.failure = f'move {n} failed: {error}'
            raise RuntimeError(self.failure) from error

    def state(self):
        return json.loads(json.dumps(self._state))

    def screenshot(self):
        self.check_alive()
        if self.pending is not None:
            raise ValueError('settle the previous move before a screenshot')
        target = paths.contained(self.folder, 'screenshots', f'{self.shot_number:03}.png')
        target.parent.mkdir(parents=True, exist_ok=True)
        self._command('screenshot', str(target))
        if not target.is_file():
            raise RuntimeError(f'simctl did not write screenshot: {target}')
        self.shot_number += 1
        return target

    @staticmethod
    def _stop(process, first_signal):
        if process is None or process.poll() is not None:
            return
        try:
            process.send_signal(first_signal)
        except ProcessLookupError:  # The runner may exit between poll and signal.
            process.wait()
            return
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

    def close(self):
        if not self.closed:
            self.closed = True
            try:
                self._stop(self.recorder, signal.SIGINT)
            finally:
                self._stop(self.runner, signal.SIGINT)

    def __enter__(self):
        return self

    def __exit__(self, *exception):
        self.close()
