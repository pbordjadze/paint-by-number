"""Read-only hatch resume decisions, shared by the driver and list-resume CLI."""
import json
import re
from pathlib import Path

from . import loop, paths


def latest_result(base):
    """The original completion is immutable; subsequent outcomes are append-only."""
    results = sorted(paths.contained(base, p.relative_to(base))
                     for p in (base / 'resume-results').glob('*.json'))
    target = results[-1] if results else paths.contained(base, 'result.json')
    return target, loop.load(target)


def next_result(base):
    results = list((base / 'resume-results').glob('*.json'))
    number = max((int(p.stem) for p in results), default=0) + 1
    return paths.contained(base, 'resume-results', f'{number:06}.json')


def attempt_path(base, record):
    return paths.contained(base, Path(record['work']).relative_to(base))


def read_reply(work):
    for name in ('reply.retry.json', 'reply.json'):
        try:
            reply = loop.load(paths.contained(work, name))
        except ValueError:
            continue
        if isinstance(reply, dict):
            return reply
    return {}


def provider_stop(work):
    """Require a terminal provider error in a complete recorded event stream.

    A bare exit code, missing report, worker assertion or quoted error is not evidence.
    Once any tool/work item appears we cannot prove no image was made (some transports
    omit image events), so that case can only continue with its existing repair budget.
    """
    logs = sorted(work.glob('codex*.jsonl'))
    if not logs:
        return None
    evidence = []
    before_work = True
    for log in logs:
        started = failed = terminal_signal = False
        signals = []
        for number, line in enumerate(paths.contained(work, log.name).read_text().splitlines(), 1):
            try:
                event = json.loads(line)
            except ValueError:
                return None
            if not isinstance(event, dict):
                return None
            kind = event.get('type')
            if kind not in ('thread.started', 'turn.started', 'error', 'turn.failed'):
                before_work = False
            started |= kind == 'turn.started'
            failed = kind == 'turn.failed'
            if failed:
                terminal_signal = False
            if kind not in ('error', 'turn.failed'):
                continue
            error = event.get('error', event)
            if not isinstance(error, dict):
                return None
            code, message = error.get('code', ''), error.get('message', '')
            if not isinstance(message, str):
                return None
            if (code in ('usage_limit_reached', 'insufficient_quota', 'rate_limit_exceeded',
                         'rate_limit_error', 'server_error', 'overloaded_error',
                         'internal_server_error', 'service_unavailable', 'capacity_exceeded')
                    or error.get('status_code') in (429, 500, 502, 503, 504)
                    or re.search(r"(?:hit your usage limit|usage limit (?:reached|exceeded)|"
                                 r"rate limit|too many requests|insufficient quota|"
                                 r"server (?:is overloaded|error)|service (?:is )?unavailable)",
                                 message, re.I)):
                signals.append({'log': str(log), 'line': number, 'code': code, 'message': message})
                terminal_signal = kind == 'turn.failed'
        if not started or not failed or not terminal_signal:
            return None
        evidence.extend(signals)
    return {'before_work': before_work, 'evidence': evidence}


def stopped_before_work(work):
    stop = provider_stop(work)
    return stop['evidence'] if stop and stop['before_work'] else None


def refused_attempt(base):
    from .lamp_hatch import refusal
    for entry in sorted(base.glob('attempt-*')):
        work = paths.contained(base, entry.name)
        if refusal(work):
            return work, 'explicit provider refusal; see codex logs'
        # Both reports matter: a later report cannot undo a refusal.
        for name in ('reply.json', 'reply.retry.json'):
            try:
                reply = loop.load(paths.contained(work, name), {})
            except ValueError:
                continue
            if isinstance(reply, dict) and reply.get('status') == 'refused':
                return work, reply.get('reason', 'provider refusal')
    return None


def gate_failure(record, work):
    if record.get('failure_kind') == 'gate':
        return True
    reply = read_reply(work)
    if reply.get('status') == 'failed' and reply.get('image_generations', 0) > 0:
        return True
    # Legacy independent gate failures had no failure_kind. Match the driver's
    # validator errors only, not arbitrary process failures after generated art.
    return (reply.get('status') == 'complete' and record.get('image_generations', 0) > 0
            and bool(re.match(r'(?:validate_atlas.py|validate_pet_quality.py) failed;',
                              record.get('reason', ''))))


def _decision(base):
    """Describe exactly one hatch invocation; never create files or call a model."""
    from .lamp_hatch import retryable_pilot
    target, record = latest_result(base)
    info = {'key': base.name, 'action': 'keep', 'model_call': False,
            'result': str(target) if record else None}
    if record and record['status'] in ('validated', 'refused'):
        return {**info, 'reason': 'already validated' if record['status'] == 'validated'
                else 'provider refusal is terminal'}
    refused = refused_attempt(base)
    if refused:
        work, reason = refused
        return {**info, 'action': 'refused', 'work': str(work), 'reason': reason}
    if not record:
        active = loop.load(paths.contained(base, 'active-attempt.json'))
        if active:
            work = paths.contained(base, active['directory'])
            stop = provider_stop(work)
            if stop:
                return {**info, 'action': 'provider_retry' if stop['before_work'] else 'continue_attempt',
                        'model_call': True, 'work': str(work),
                        'reason': stop['evidence'][0]['message'] or stop['evidence'][0]['code'],
                        'provider_stop': stop['evidence']}
        return {**info, 'action': 'run', 'model_call': True,
                'reason': 'resume unfinished attempt' if active else 'not attempted'}
    info['fresh_attempts'] = record.get('fresh_attempts', 0)
    if record['status'] != 'failed':
        return {**info, 'reason': record['status'] + ' is terminal'}
    work = attempt_path(base, record)
    stop = provider_stop(work)
    if stop:
        unstarted = stop['before_work'] and not record.get('image_generations', 0)
        return {**info, 'action': 'provider_retry' if unstarted else 'continue_attempt', 'model_call': True,
                'reason': ('provider stop before work: ' if unstarted else
                           'continue preserved work with existing repair counts: ')
                          + (stop['evidence'][0]['message'] or stop['evidence'][0]['code']),
                'provider_stop': stop['evidence']}
    if (record.get('atlas_sha256') and record.get('validators')
            and re.fullmatch(r'package is \d+ bytes, exceeds \d+; no files published', record.get('reason', ''))
            and record.get('resume_action') != 'repackage'):
        return {**info, 'action': 'repackage', 'reason': 'validated atlas; shrink contact preview to fit 2 MB'}
    if retryable_pilot(record):
        return {**info, 'action': 'pilot_migration', 'model_call': True, 'reason': record['reason']}
    if base.name.startswith('set-') and gate_failure(record, work):
        if info['fresh_attempts'] < 1:
            return {**info, 'action': 'fresh_attempt', 'model_call': True, 'reason': record['reason']}
        return {**info, 'reason': 'one fresh gate attempt already used: ' + record['reason']}
    return {**info, 'reason': 'no retry authorized: ' + record.get('reason', record['status'])}


def decision(base):
    info = _decision(base)
    if not info['model_call']:
        return info
    active = loop.load(paths.contained(base, 'active-attempt.json'))
    _, previous = latest_result(base)
    if active:
        work = paths.contained(base, active['directory'])
        if (not previous or work != attempt_path(base, previous)) and (work / 'reply.json').exists():
            from .lamp_hatch import RESULT
            from .schema import validate
            if (work / 'reply.retry.json').exists() or not validate(read_reply(work), RESULT):
                info['model_call'] = False
                info['reason'] += '; finish recorded worker reply without another model call'
    return info


def listing(run, makers_call=None):
    run = Path(run).resolve()
    if not paths.contained(run, 'run.json').is_file():
        raise ValueError('list-resume requires an existing run.json')
    keys = {p.name for p in paths.contained(run, 'hatches').glob('*') if p.is_dir()}
    briefs = loop.load(paths.contained(run, 'decisions/briefs.json'), {})
    keys.update('set-' + pet for pet in briefs.get('briefs', {}))
    from .codex_lamp import Lamp
    from . import lamp_images, lamp_maker
    config = loop.load(paths.contained(run, 'run.json'))
    # Jury rotation needs only the frozen panel; constructing Lamp would write.
    inputs = loop.load(paths.contained(run, 'inputs.json'))
    panel = object.__new__(Lamp)
    panel.seats = {g['id']: g for g in inputs['guardians']}
    images = lamp_images.listing(run, panel.jury(3), config['model'])
    _, settled = lamp_images.state(run)
    maker_results = loop.load(paths.contained(run, 'decisions/maker-images.json'), {}).get('pets', {})
    keys.update('redo-' + pet for pet in images.get('redos', {}))
    hatches = []
    for key in sorted(keys):
        info = decision(paths.contained(run, 'hatches', paths.slug(key)))
        pet = key.split('-', 1)[1]
        if key.startswith(('set-', 'redo-')) and pet in settled:
            info.update(action='keep', model_call=False,
                        reason='completed image decision retained: ' + str(settled[pet][0]))
        if key.startswith('maker-') and pet in maker_results:
            info.update(action='keep', model_call=False, reason='completed maker decision retained')
        hatches.append(info)
    maker = lamp_maker.listing(run, makers_call)
    return {'status': 'list-resume', 'run': str(run), 'hatches': hatches,
            'model_hatches': sum(h['model_call'] for h in hatches),
            'local_repackages': sum(h['action'] == 'repackage' for h in hatches),
            'images': images, 'makers_call': maker,
            'scope': 'Known hatches, pending image juries and explicit maker decisions; future verdicts may request redos.'}
