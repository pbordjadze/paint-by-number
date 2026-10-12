"""Frozen, step-specific Lamp flag policies and an explicit offline step-3 revision."""
from datetime import datetime, timezone

from . import loop, paths
from .codex_lamp import digest, frozen

READABILITY = ('Readability notes from the image jury: make waiting, focused work (running row 7), '
               'and review read differently from idle and from each other at 192 × 208. '
               'Apply the winning style\'s supplied attributed drawing notes to this pet, including '
               'the reference pet. Carry them into every image prompt. These are drawing guidance; '
               'keep the fixed family reference and the v2 contract.')


def rules(version):
    if version not in (1, 2):
        raise ValueError('unknown Lamp decision rules version')
    value = {'version': version, 'steps': {
        '1': {'vetoes': 'exclude', 'flags': 'exclude'},
        '3': {'vetoes': 'exclude', 'flags': 'exclude' if version == 1 else 'drawing-notes'},
        '5': {'vetoes': 'return-to-guardian-once', 'flags': 'return-to-guardian-once'},
        '7': {'vetoes': 'redo-once-then-withhold', 'flags': 'redo-once-then-withhold'}}}
    if version == 2:
        value['steps']['3']['drawing_instruction'] = READABILITY
    return value


def initialize(run, *, new=False):
    path = paths.contained(run, 'rules.json')
    value = loop.load(path)
    if value is None:
        value = frozen(path, rules(2 if new else 1))
    if value != rules(value['version']):
        raise ValueError('unknown Lamp decision rules')
    return value


def for_style(run):
    value = initialize(run)
    data = loop.load(paths.contained(run, 'provenance.json'), {})
    revision = data.get('style_flag_revision')
    if revision:
        sha = revision['after']
        value = loop.load(paths.contained(run, 'rule-revisions', sha + '.json'))
        if value != rules(2) or digest(value) != sha or revision['step'] != 3:
            raise ValueError('missing or changed Lamp style flag rules')
    return value


def tally(candidates, votes, count, *, style_rules=None):
    notes_policy = style_rules is not None and style_rules['steps']['3']['flags'] == 'drawing-notes'
    scores = dict.fromkeys(candidates, 0)
    excluded = set()
    for seat, reply in votes.items():
        excluded.update(v['target'] for v in reply['vetoes'])
        if not notes_policy:
            excluded.update(v['target'] for v in reply['flags'])
        if seat != 'originality':
            for place, target in enumerate(reply['ranking']):
                scores[target] += len(candidates) - place - 1
    order = sorted((i for i in candidates if i not in excluded), key=lambda i: (-scores[i], i)) if votes else []
    record = {'scores': scores, 'excluded': sorted(excluded), 'selected': order[:count], 'votes': votes}
    # Legacy decisions retain their exact shape and bytes on a re-tally.
    if notes_policy:
        record.update(step=3, rules_sha256=digest(style_rules),
                      drawing_notes=[{'seat': seat, **flag} for seat, reply in votes.items()
                                     for flag in reply['flags'] if flag['target'] in record['selected']])
    return record


def drawing_notes(run):
    policy = for_style(run)
    if policy['steps']['3']['flags'] != 'drawing-notes':
        return {}
    decision = loop.load(paths.contained(run, 'decisions', 'style.json'), {})
    if not decision.get('selected'):
        raise ValueError('post-decision hatch needs a selected style')
    if decision.get('rules_sha256') != digest(policy):
        raise ValueError('style decision needs re-tallying under its frozen rules')
    return {'style_id': decision['selected'][0], 'rules_sha256': decision['rules_sha256'],
            'instruction': policy['steps']['3']['drawing_instruction'], 'flags': decision['drawing_notes']}


def retally_style(run, reason):
    """Revise only a blocked style decision; keep its ballots and old decision as evidence.

    The provenance write commits the new rule before the derived decision is written.
    A repeated command (or ordinary resume) recovers an interrupted decision write.
    """
    from . import lamp_inputs
    if not reason.strip():
        raise ValueError('style rule revision reason must be nonempty')
    data = lamp_inputs.provenance(run)
    path = paths.contained(run, 'decisions', 'style.json')
    before = loop.load(path)
    if before is None:
        raise ValueError('re-tally requires a recorded style decision')
    if (any(int(key) >= 4 for key in data['steps'])
            or any((run / name).exists() for name in ('summary.json', 'decisions/briefs.json', 'decisions/images.json'))):
        raise ValueError('cannot revise style rules after a later step has started')
    old_rules = initialize(run)
    revision = data.get('style_flag_revision')
    if revision:
        old_path = paths.contained(run, revision['previous_decision'])
        before = loop.load(old_path)
        if digest(old_path.read_bytes()) != revision['previous_decision_sha256']:
            raise ValueError('archived style decision changed')
        for_style(run)  # Validate the frozen revision before recovering a decision write.
    elif old_rules != rules(1) or before['selected']:
        raise ValueError('only a blocked legacy style decision can revise its flag policy')
    # Consume only completed primary ballots, never dispatch or reinterpret a reply.
    config = loop.load(paths.contained(run, 'run.json'))
    votes = {}
    for job_path in sorted(run.glob('jobs/005/*.json')):
        job = loop.load(paths.contained(run, job_path.relative_to(run)))
        if job['stage'] != 'style-decision' or job['model'] != config['model']:
            continue
        record = loop.load(paths.job_path(run, job, 'records'))
        if record is None or record['job_sha256'] != digest(job):
            raise ValueError('style decision has an incomplete or changed job')
        if record['status'] == 'valid':
            votes[job['guardian']] = record['reply']
    if not votes or votes != before['votes'] or tally(before['scores'], votes, 1) != before:
        raise ValueError('recorded style decision does not match completed legacy ballots')
    after = tally(before['scores'], before['votes'], 1, style_rules=rules(2))
    if not revision:
        archive = paths.contained(run, 'records', 'style-policy', '001', 'style.json')
        # Preserve the previous serialized decision exactly, including its vote order.
        if archive.exists() and archive.read_bytes() != path.read_bytes():
            raise ValueError('archived style decision differs')
        if not archive.exists():
            loop.write_atomic(archive, path.read_text())
        for value in (old_rules, rules(2)):
            frozen(paths.contained(run, 'rule-revisions', digest(value) + '.json'), value)
        revision = {'step': 3, 'at': datetime.now(timezone.utc).isoformat(), 'reason': reason.strip(),
                    'before': digest(old_rules), 'after': digest(rules(2)),
                    'previous_decision': archive.relative_to(run).as_posix(),
                    'previous_decision_sha256': digest(archive.read_bytes()),
                    'decision_sha256': digest(after)}
        data['style_flag_revision'] = revision
        loop.save(paths.contained(run, 'provenance.json'), data)
    loop.save(path, after)
    return {'status': 'retallied', 'selected': after['selected'], 'scores': after['scores'],
            'drawing_notes': after['drawing_notes'], 'revision': revision}
