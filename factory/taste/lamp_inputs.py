"""Immutable Lamp inputs, with explicit charter revisions and lossless step restarts."""
from datetime import datetime, timezone

from . import loop, paths
from .codex_lamp import digest, frozen


def step(number):
    return str({1: 1, 2: 1, 3: 1, 4: 1, 5: 3, 6: 4, 7: 5, 8: 5, 9: 7, 10: 7}[number])


def snapshot(run, sha):
    value = loop.load(paths.contained(run, 'input-revisions', sha + '.json'))
    if value is None or digest(value) != sha:
        raise ValueError('missing or changed Lamp input revision: ' + sha)
    return value


def provenance(run):
    original = loop.load(paths.contained(run, 'inputs.json'))
    if original is None:
        raise ValueError('refresh requires an existing Lamp run with inputs.json')
    sha = digest(original)
    frozen(paths.contained(run, 'input-revisions', sha + '.json'), original)
    data = loop.load(paths.contained(run, 'provenance.json'),
                     {'version': 1, 'initial': sha, 'current': sha, 'steps': {}, 'refreshes': []})
    if data['initial'] != sha:
        raise ValueError('original Lamp inputs changed')
    from .lamp_restart import finish
    data = finish(run, data)
    # Import pre-revision jobs without touching their bytes or completion hashes.
    for path in sorted(run.glob('jobs/*/*.json')):
        job = loop.load(paths.contained(run, path.relative_to(run)))
        key = step(job['round'])
        identity = job.get('inputs_sha256', data['steps'].get(key, sha))
        if data['steps'].setdefault(key, identity) != identity:
            raise ValueError('different inputs within Lamp step ' + key)
    for prefix, key in (('pilot-', '2'), ('set-', '6'), ('redo-', '7')):
        if any(run.glob('hatches/' + prefix + '*/request.json')):
            data['steps'].setdefault(key, sha)
    return data


def for_step(run, number):
    return bind_step(run, step(number))


def bind_step(run, key):
    data = provenance(run)
    sha = data['steps'].setdefault(key, data['current'])
    value = snapshot(run, sha)
    loop.save(paths.contained(run, 'provenance.json'), data)
    return sha, value


def current(run):
    data = provenance(run)
    return snapshot(run, data['current'])


def refresh(run, reason, restart_step=None):
    if not reason.strip():
        raise ValueError('refresh reason must be nonempty')
    if restart_step is not None and (type(restart_step) is not int or not 1 <= restart_step <= 7):
        raise ValueError('restart step must be between 1 and 7')
    data = provenance(run)
    before = data['current']
    inputs = snapshot(run, before)
    guardians = {g['id']: g for g in loop.guardians()}
    if set(guardians) != {g['id'] for g in inputs['guardians']}:
        raise ValueError('a changed panel needs a new run')
    inputs['guardians'] = [{**g, **{key: guardians[g['id']][key]
                                  for key in ('name', 'charter', 'charter_text')}}
                           for g in inputs['guardians']]
    for guardian in inputs['guardians']:
        current = guardians[guardian['id']]
        if 'description' in current:
            guardian['description'] = current['description']
    inputs.pop('glossary', None)
    after = digest(inputs)
    if after == before and restart_step is None:
        return {'status': 'unchanged', 'inputs_sha256': before}
    frozen(paths.contained(run, 'input-revisions', after + '.json'), inputs)
    restart = None
    if restart_step is not None:
        from .lamp_restart import prepare
        restart = prepare(run, data, restart_step, reason, after)
    event = {'at': datetime.now(timezone.utc).isoformat(), 'reason': reason.strip(),
             'before': before, 'after': after, 'preserved_steps': {
                 key: sha for key, sha in data['steps'].items()
                 if restart_step is None or int(key) < restart_step}}
    if after != before:
        data['refreshes'].append(event)
    data['current'] = after
    if restart:
        from .lamp_restart import finish
        data['pending_restart'] = restart
        # A durable journal precedes every move; any later command finishes it first.
        loop.save(paths.contained(run, 'provenance.json'), data)
        finish(run, data)
        from .lamp_compare import compare_run
        compare_run(run)
        return {**restart, 'status': 'restarted'}
    # This single atomic write commits the revision and its step boundary together.
    loop.save(paths.contained(run, 'provenance.json'), data)
    return {'status': 'refreshed', **event}
