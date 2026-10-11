"""Portable play sessions: strict moves, recorded drivers, jobs, turns and replay.

Drivers return screenshot paths and JSON states; perform initiates a move and settle waits
until it is safe to observe the resulting screen. The loop never calls a model. Records use
relative screenshot paths so replay outputs compare byte for byte in another directory.
"""
import json
import shutil
import tomllib
from pathlib import Path
from typing import Protocol


from . import accounting, loop, paths, renderers, schema
from .kit import outside_repo
from .pieces import play as piece

PIECE = loop.REPO / 'factory/pieces/play'
MOVE_SCHEMA = loop.load(PIECE / 'moves.schema.json')
REPLY_SCHEMA = schema.obj({'move': MOVE_SCHEMA, 'reason': schema.STRING})
STATE_SCHEMA = schema.obj({
    'screen': schema.STRING,
    'selected_paint': {'type': ['integer', 'null'], 'minimum': 1},
    'filled_areas': {'type': 'array', 'items': {'type': 'integer', 'minimum': 1},
                     'uniqueItems': True},
    'area_count': {'type': 'integer', 'minimum': 0},
})


def validate_move(move, state=None):
    if isinstance(move, dict) and move.get('do') not in ('fill', 'tap', 'drag', 'wait', 'screenshot'):
        raise ValueError(f"unknown move: {move.get('do')!r}")
    errors = schema.validate(move, MOVE_SCHEMA, '$.move')
    if errors:
        raise ValueError('; '.join(errors))
    if state is not None and move['do'] == 'fill' and move['area'] > state['area_count']:
        raise ValueError(f"area {move['area']} exceeds area_count {state['area_count']}")
    return move


def validate_state(state):
    errors = schema.validate(state, STATE_SCHEMA, '$.state')
    if errors:
        raise ValueError('; '.join(errors))
    if any(area > state['area_count'] for area in state['filled_areas']):
        raise ValueError('filled_areas exceeds area_count')
    return state


class Driver(Protocol):
    """The Mac driver implements this boundary; screenshot coordinates are pixels.

    state has screen, selected_paint (positive paint number or null), filled_areas
    (unique 1-based area numbers), and area_count. settle must complete before reads.
    A rejected perform must leave the driver unchanged.
    """
    def screenshot(self) -> Path: ...
    def state(self) -> dict: ...
    def perform(self, move: dict) -> None: ...
    def settle(self) -> None: ...


class MockDriver:
    """Play recording.json's initial frame and exact move/frame/state transitions.

    Recorded waits consume a transition without sleeping. A transition becomes visible
    only at settle; an unexpected move or exhausted recording is an explicit rejection.
    """
    def __init__(self, folder, *, recording=None):
        from PIL import Image
        self.folder = Path(folder).resolve()
        self.recording = loop.load(self.folder / 'recording.json') if recording is None else recording
        data = self.recording
        if (not isinstance(data, dict) or set(data) != {'version', 'initial', 'turns'} or
                type(data['version']) is not int or data['version'] != 1):
            raise ValueError('recording needs version 1, initial and turns')
        if not isinstance(data['turns'], list):
            raise ValueError('recording turns must be an array')
        self.observations = [data['initial'], *data['turns']]
        for i, observation in enumerate(self.observations):
            required = {'screenshot', 'state'} | ({'move'} if i else set())
            if not isinstance(observation, dict) or set(observation) != required:
                raise ValueError(f'recording observation {i} needs {sorted(required)}')
            validate_state(observation['state'])
            source = self.frame(observation)
            with Image.open(source) as image:
                image.verify()
            if i:
                validate_move(observation['move'], self.observations[i - 1]['state'])
        self.index = 0
        self.pending = False

    def frame(self, observation):
        name = observation['screenshot']
        if not isinstance(name, str) or Path(name).is_absolute():
            raise ValueError('recording screenshots must be relative paths')
        path = (self.folder / name).resolve()
        if self.folder not in path.parents:
            raise ValueError('recording screenshot leaves its folder')
        return path

    def screenshot(self):
        return self.frame(self.observations[self.index])

    def state(self):
        return json.loads(json.dumps(self.observations[self.index]['state']))

    def perform(self, move):
        validate_move(move, self.state())
        if self.pending:
            raise ValueError('settle the previous move first')
        if self.index + 1 >= len(self.observations):
            raise ValueError('mock recording exhausted')
        expected = self.observations[self.index + 1]['move']
        if move != expected:
            raise ValueError(f'mock expected {expected}, received {move}')
        self.pending = True

    def settle(self):
        if self.pending:
            self.index += 1
            self.pending = False

    def export(self, folder):
        folder = outside_repo(folder)
        entries = []
        for i, observation in enumerate(self.observations):
            name = f'frames/{i:03}{self.frame(observation).suffix}'
            destination = folder / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.frame(observation), destination)
            entries.append({**observation, 'screenshot': name})
        loop.save(folder / 'recording.json', {'version': 1, 'initial': entries[0], 'turns': entries[1:]})


def config_read():
    with (PIECE / 'piece.toml').open('rb') as stream:
        return tomllib.load(stream)


def observe(driver, run, n):
    from PIL import Image
    state = validate_state(driver.state())
    source = Path(driver.screenshot())
    # Decode as well as copy: an unreadable frame must never become a recorded turn.
    with Image.open(source) as image:
        image.load()
    name = f'screenshots/{n:03}{source.suffix}'
    target = run / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    return {'screenshot': name, 'state': state}


def turn_paths(run):
    return sorted((Path(run) / 'turns').glob('*.json'), key=lambda path: int(path.stem))


class Session:
    """One guardian, frozen jobs and sequential turns against any Driver.

    create captures the settled initial screen. job/collect exchange files with the kit's
    runners; apply also accepts a canned reply directly. The driver must already match
    latest when resuming (restore does this for the CLI's mock).
    """
    def __init__(self, run, driver: Driver):
        self.path = outside_repo(run)
        self.driver = driver
        self.rules = loop.load(self.path / 'rules.json')
        if not self.rules or self.rules.get('playVersion') != 1:
            raise ValueError('use loop play new to create a session')

    @classmethod
    def create(cls, run, driver: Driver, guardian, *, budget=None):
        run = outside_repo(run)
        if run.exists() and any(run.iterdir()):
            raise ValueError('new play session directory must be empty')
        config = config_read()
        budget = config['move_budget'] if budget is None else budget
        if type(budget) is not int or budget < 1:
            raise ValueError('move budget must be a positive integer')
        seats = loop.seats(loop.fresh_rules('play'))
        if guardian not in seats or not seats[guardian].get('active') or seats[guardian].get('vetoOnly'):
            raise ValueError(f'unknown or non-playing guardian: {guardian}')
        rules = {'playVersion': 1, 'piece': 'play', 'guardian': seats[guardian],
                 'budget': budget, 'history': config['history'], 'role': config['roles']['player'],
                 'brief': (PIECE / 'brief.md').read_text(), 'reply_schema': REPLY_SCHEMA}
        driver.settle()
        initial = observe(driver, run, 0)
        loop.save(run / 'rules.json', rules)
        loop.save(run / 'initial.json', initial)
        session = cls(run, driver)
        session.finish()
        return session

    def turns(self):
        return [loop.load(path) for path in turn_paths(self.path)]

    def latest(self):
        turns = self.turns()
        return turns[-1] if turns else loop.load(self.path / 'initial.json')

    def status(self):
        state = self.latest()['state']
        if len(state['filled_areas']) == state['area_count']:
            return 'complete'
        return 'budget' if len(self.turns()) >= self.rules['budget'] else 'active'

    def finish(self):
        result = {'version': 1, 'status': self.status(), 'turns': len(self.turns()),
                  'budget': self.rules['budget'], 'guardian': self.rules['guardian']['id']}
        loop.save(self.path / 'session.json', result)
        frames = [loop.load(self.path / 'initial.json'), *self.turns()]
        renderers.contacts({f"{i}: {frame.get('move', {}).get('do', 'start')}":
                            self.path / frame['screenshot'] for i, frame in enumerate(frames)},
                           self.path / 'contact.png')
        return result

    def job(self):
        if self.status() != 'active':
            raise ValueError(f'play session ended: {self.status()}')
        n = len(self.turns()) + 1
        guardian = self.rules['guardian']
        latest = self.latest()
        screenshot = str(self.path / latest['screenshot'])
        history = [{'move': t['move'], 'reason': t['reason']} for t in self.turns()[-self.rules['history']:]]
        job = {'id': f"player-{guardian['id']}", 'round': n, 'role': 'player',
               'guardian': guardian['id'], 'model': self.rules['role']['model'],
               'effort': self.rules['role']['effort'], 'images': [screenshot], 'attempt': 0,
               'reply_schema': self.rules['reply_schema'], 'state': latest['state'], 'history': history,
               'prompt': piece.prompt(self.rules['brief'], guardian, screenshot, latest['state'], history)}
        path = paths.job_path(self.path, job, 'jobs')
        old = loop.load(path)
        if old is not None and old != job:
            raise ValueError('play job is frozen; use a new session')
        loop.save(path, job)
        return job

    def apply(self, reply):
        if self.status() != 'active':
            raise ValueError(f'play session ended: {self.status()}')
        errors = schema.validate(reply, self.rules['reply_schema'])
        if errors:
            raise ValueError('; '.join(errors))
        if len(reply['reason'].splitlines()) != 1:
            raise ValueError('reason must be one line')
        move = validate_move(reply['move'], self.latest()['state'])
        self.driver.perform(move)
        n = len(self.turns()) + 1
        try:
            self.driver.settle()
            observation = observe(self.driver, self.path, n)
        except (ValueError, OSError) as error:
            raise RuntimeError(f'driver failed after performing turn {n}: {error}') from error
        turn = {'turn': n, 'guardian': self.rules['guardian']['id'],
                'move': move, 'reason': reply['reason'], **observation}
        loop.save(self.path / 'turns' / f'{n:03}.json', turn)
        self.finish()
        return turn

    def collect(self):
        job = self.job()
        folder = f"{job['round']:03}"
        reply_path = paths.job_path(self.path, job, 'replies')
        retry_path = paths.job_path(self.path, job, 'retries')
        repairing = retry_path.exists()
        if repairing:
            rejection = loop.load(paths.job_path(self.path, {**job, 'attempt': 1}, 'rejections'))
            if rejection is not None:
                return {'status': 'blocked', 'reason': rejection['error']}
            reply_path = paths.job_path(self.path, {**job, 'attempt': 1}, 'replies')
        if not reply_path.exists():
            return {'status': 'waiting', 'reply': str(reply_path)}
        try:
            reply = loop.load(reply_path)
            turn = self.apply(reply)
        except (ValueError, KeyError) as error:
            reason = str(error)
            if not repairing:
                retry = {**job, 'attempt': 1, 'error': reason, 'reply': reply_path.read_text()}
                retry['prompt'] += f'\nYour reply was rejected: {reason}. Repair it once.'
                loop.save(retry_path, retry)
            loop.save(paths.job_path(self.path, {**job, 'attempt': int(repairing)}, 'rejections'),
                      {'error': reason, 'reply': reply_path.read_text()})
            return {'status': 'blocked' if repairing else 'rejected', 'reason': reason}
        return {'status': 'accepted', 'turn': turn, 'session': self.status()}


def restore(run):
    """Restore the CLI's mock to the current turn, checking each recorded observation."""
    run = outside_repo(run)
    driver = MockDriver(run / 'driver')
    session = Session(run, driver)
    observations = [loop.load(run / 'initial.json'), *session.turns()]
    for i, observation in enumerate(observations):
        if i:
            driver.perform(observation['move'])
            driver.settle()
        if driver.state() != observation['state'] or driver.screenshot().read_bytes() != (
                run / observation['screenshot']).read_bytes():
            raise ValueError(f'mock observation differs at turn {i}')
    return session


def replay(run, out, recording=None):
    run, out = outside_repo(run), outside_repo(out)
    if run == out or run in out.parents or out in run.parents:
        raise ValueError('replay destination must be separate from the source session')
    if out.exists() and any(out.iterdir()):
        raise ValueError('replay output must be empty')
    initial = loop.load(run / 'initial.json')
    turns = [loop.load(p) for p in turn_paths(run)]
    # A real driver session is itself a recording; replay never needs the live app.
    playback = {'version': 1, 'initial': initial,
                'turns': [{k: turn[k] for k in ('move', 'screenshot', 'state')} for turn in turns]}
    if recording is None:
        driver = MockDriver(run, recording=playback)
    else:
        driver = MockDriver(recording)
    rules = loop.load(run / 'rules.json')
    driver.settle()
    loop.save(out / 'initial.json', observe(driver, out, 0))
    loop.save(out / 'rules.json', rules)
    session = Session(out, driver)
    session.finish()
    for turn in turns:
        session.apply({'move': turn['move'], 'reason': turn['reason']})
    paths = [Path('rules.json'), Path('initial.json'), Path('session.json'), Path('contact.png'),
             *[p.relative_to(run) for p in sorted((run / 'turns').glob('*.json'))],
             *[p.relative_to(run) for p in sorted((run / 'screenshots').glob('*'))]]
    for path in paths:
        if (run / path).read_bytes() != (out / path).read_bytes():
            raise ValueError(f'replay differs: {path}')
    return out


def add_parser(commands):
    parser = commands.add_parser('play', help='guardian play jobs against a recorded driver')
    actions = parser.add_subparsers(dest='play_command', required=True)
    create = actions.add_parser('new')
    create.add_argument('--recording', type=Path, required=True)
    create.add_argument('--guardian', required=True)
    create.add_argument('--budget', type=int)
    for action in ('jobs', 'collect', 'report'):
        actions.add_parser(action)
    actions.add_parser('replay').add_argument('--recording', type=Path)


def dispatch(args):
    if args.play_command == 'new':
        driver = MockDriver(args.recording)
        session = Session.create(args.run, driver, args.guardian, budget=args.budget)
        driver.export(session.path / 'driver')
        return loop.load(session.path / 'session.json')
    if args.play_command == 'replay':
        return {'replayed': str(replay(args.run, args.out, args.recording))}
    if args.play_command == 'report':
        run = outside_repo(args.run)
        return {'session': loop.load(run / 'session.json'), 'costs': accounting.report(run),
                'contact': str(run / 'contact.png')}
    session = restore(args.run)
    return session.job() if args.play_command == 'jobs' else session.collect()
