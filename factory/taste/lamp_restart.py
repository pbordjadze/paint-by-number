"""Journalled, lossless supersession of a Lamp plan step and its dependents."""
from datetime import datetime, timezone

from . import loop, paths
from .codex_lamp import digest, frozen

HATCH_STEPS = {'pilot': 2, 'set': 6, 'redo': 7, 'maker': 7}
DECISION_STEPS = {'shortlist-0': 1, 'shortlist-1': 1, 'style': 3, 'reference': 3,
                  'briefs': 5, 'images': 7, 'makers-call': 7, 'maker-images': 7}


def prepare(run, data, number, reason, after):
    from .lamp_inputs import step
    selected = set()
    job_steps = {}
    for path in sorted(run.glob('jobs/*/*.json')):
        job = loop.load(paths.contained(run, path.relative_to(run)))
        job_steps[job['id']] = int(step(job['round']))
    for kind in ('jobs', 'replies', 'records', 'costs', 'retries', 'rejections'):
        for path in (run / kind).glob('*'):
            if path.name.isdecimal() and int(step(int(path.name))) >= number:
                selected.add(path.relative_to(run).as_posix())
    for path in (run / 'dispatch').glob('*'):
        # The outer temporary folder can be empty if the driver stopped before dispatch.
        rounds = [int(step(int(p.name))) for p in path.glob('*') if p.name.isdecimal()]
        owners = rounds or [n for jid, n in job_steps.items() if path.name.startswith(jid + '-')]
        if not owners:
            raise ValueError(f'cannot identify Lamp dispatch step: {path}')
        if min(owners) < number <= max(owners):
            raise ValueError(f'mixed steps in Lamp dispatch: {path}')
        if min(owners) >= number:
            selected.add(path.relative_to(run).as_posix())
    for path in (run / 'hatches').glob('*'):
        kind = path.name.split('-', 1)[0]
        if kind not in HATCH_STEPS:
            raise ValueError(f'cannot identify Lamp hatch step: {path}')
        if HATCH_STEPS[kind] >= number:
            selected.add(path.relative_to(run).as_posix())
    for name, owner in DECISION_STEPS.items():
        path = run / 'decisions' / (name + '.json')
        if owner >= number and path.exists():
            selected.add(path.relative_to(run).as_posix())
    if number <= 7 and (run / 'decisions/image-resumes').exists():
        selected.add('decisions/image-resumes')
    for name in ('summary.json', 'comparison.json', 'comparison.md'):
        if (run / name).exists():
            selected.add(name)
    archive = f'records/superseded/{len(data.get("restarts", [])) + 1:03}'
    if paths.contained(run, archive).exists():
        raise ValueError('restart archive already exists: ' + archive)
    # Check every source and destination before writing the recovery journal.
    for relative in selected:
        paths.contained(run, relative)
        paths.contained(run, archive, relative)
    old_steps = {key: sha for key, sha in data['steps'].items() if int(key) >= number}
    replies = []
    for path in sorted(run.glob('replies/*/*.json')):
        key = step(int(path.parent.name))
        if int(key) < number:
            continue
        jid = path.stem.removesuffix('.retry')
        job = loop.load(paths.contained(run, 'jobs', path.parent.name, jid + '.json'), {})
        relative = path.relative_to(run).as_posix()
        replies.append({'status': 'superseded', 'original_path': relative,
                        'path': archive + '/' + relative,
                        'inputs_sha256': job.get('inputs_sha256', old_steps.get(key, data['initial']))})
    return {'status': 'superseded', 'at': datetime.now(timezone.utc).isoformat(),
            'restart_step': number, 'reason': reason.strip(), 'before': data['current'],
            'after': after, 'old_steps': old_steps, 'archive': archive,
            'artifacts': sorted(selected), 'replies': replies}


def finish(run, data):
    """Recover the pending move before any active jobs or decisions can be consumed."""
    event = data.get('pending_restart')
    if event is None:
        return data
    archive = event['archive']
    frozen(paths.contained(run, archive, 'manifest.json'), event)
    for relative in event['artifacts']:
        source = paths.contained(run, relative)
        target = paths.contained(run, archive, relative)
        if source.exists() and not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            source.rename(target)
        elif source.exists() or not target.exists():
            raise ValueError('cannot recover Lamp restart artifact: ' + relative)
    data['steps'] = {key: sha for key, sha in data['steps'].items()
                     if int(key) < event['restart_step']}
    data.setdefault('restarts', []).append(event)
    del data['pending_restart']
    loop.save(paths.contained(run, 'provenance.json'), data)
    return data


def records(run, provenance):
    """Report archived completions and even replies interrupted before collection.

    Original bytes stay untouched. Status and archive context are report annotations.
    """
    from .lamp_inputs import step
    for event in provenance.get('restarts', []):
        root = paths.contained(run, event['archive'])
        seen = set()
        archived = []
        for path in sorted(root.glob('records/*/*.json')):
            record = loop.load(paths.contained(root, path.relative_to(root)))
            suffix = '.retry' if record.get('attempt', 0) else ''
            seen.add(f'replies/{record["round"]:03}/{record["id"]}{suffix}.json')
            archived.append((record, path.relative_to(root).as_posix()))
        for info in event['replies']:
            relative = info['original_path']
            if relative in seen:
                continue
            path = paths.contained(root, relative)
            job = loop.load(paths.contained(root, 'jobs', path.parent.name,
                                           path.stem.removesuffix('.retry') + '.json'))
            if job is None:
                raise ValueError('superseded reply has no job: ' + relative)
            raw = path.read_text()
            try:
                reply, errors = loop.load(path), []
            except ValueError as exc:
                reply, errors = None, [str(exc)]
            record = {**job, 'reply': reply, 'errors': errors, 'raw_reply': raw,
                      'status': 'uncollected', 'prompt_sha256': digest(job['prompt'].encode()),
                      'reply_characters': len(raw)}
            archived.append((record, relative))
        for record, relative in archived:
            yield {**record, 'source': 'pets', 'previous_status': record.get('status', 'valid'),
                   'status': 'superseded', 'superseded_reason': event['reason'],
                   'superseded_by': event['archive'], 'archived_path': event['archive'] + '/' + relative,
                   'inputs_sha256': record.get('inputs_sha256',
                       event['old_steps'].get(step(record['round']), provenance['initial']))}
