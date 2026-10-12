#!/usr/bin/env python3
"""Offline test double. Synthetic pixels are plumbing fixtures, never pet artwork."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import sys
import time

from strict_schema import check_strict

args = sys.argv[1:]
prompt = sys.stdin.read()
def option(name):
    return args[args.index(name) + 1]
work = Path(option('--cd'))
reply_path = Path(option('--output-last-message'))
rule = json.loads(Path(option('--output-schema')).read_text())
check_strict(rule)
props = rule['properties']
model = option('--model')
log = Path(os.environ['FAKE_CODEX_LOG'])
def event(kind, **extra):
    with log.open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        handle.write(json.dumps(dict(event=kind, work=str(work), model=model, args=args,
                                     prompt=prompt if kind == 'start' else None, at=time.time(), **extra)) + '\n')
event('start')
if os.environ.get('FAKE_SHORTLIST_TRANSPORT_ERROR') and 'shortlist-' in str(work):
    sys.exit(1)
if (os.environ.get('FAKE_STYLE_TRANSPORT_ERROR') and 'style-decision-' in str(work)
        and not any(seat in str(work) for seat in ('enchanted-workshop', 'storybook'))):
    sys.exit(1)
if os.environ.get('FAKE_CRASH') and os.environ['FAKE_CRASH'] in str(reply_path):
    marker = log.with_suffix('.crashed')
    try:
        marker.open('x').close()
    except FileExistsError:
        pass
    else:
        os.kill(os.getppid(), signal.SIGKILL)
        sys.exit(1)

def context():
    return json.JSONDecoder().raw_decode(prompt.split('Context:\n', 1)[1])[0]

def fill(s):
    if 'enum' in s:
        return s['enum'][0]
    if 'anyOf' in s:
        return None if any(x.get('type') == 'null' for x in s['anyOf']) else fill(s['anyOf'][0])
    t = s['type']
    if t == 'object': return {k: fill(v) for k, v in s['properties'].items()}
    if t == 'array': return [fill(s['items']) for _ in range(s.get('minItems', 0))]
    if t == 'null': return None
    if t == 'boolean': return True
    if t == 'integer': return 1
    return 'A quiet shape carries its meaning.'

reply = fill(rule)
if 'status' in props:
    request = json.JSONDecoder().raw_decode(prompt.split('Request:\n', 1)[1])[0]
    if os.environ.get('FAKE_PROVIDER_STOP') == request['pet']:
        for item in ({'type': 'thread.started'}, {'type': 'turn.started'},
                     {'type': 'error', 'message': 'You’ve hit your usage limit.'},
                     {'type': 'turn.failed', 'error': {'message': 'You’ve hit your usage limit.'}}):
            print(json.dumps(item))
        event('end')
        sys.exit(1)
    assert 'Never ask for clarification or wait for an answer.' in prompt
    assert 'eight columns by eleven rows' in prompt
    assert 'The contract overrides ANY frame count' in prompt
    assert 'record EVERY technical override' in prompt
    if request['reference'] is None:
        assert 'reference=null is intentional, not a blocker' in prompt
        assert '--image' not in args
    else:
        assert args[args.index('--image') + 1] == request['reference']
        assert "family reference is the jury's chosen pilot" in prompt
    refused = request['pet'] == os.environ.get('FAKE_REFUSE') and request['key'].startswith('set-')
    failed = (request['pet'] in os.environ.get('FAKE_FAIL', '').split(',') and request['key'].startswith('set-')
              or request['pet'] == os.environ.get('FAKE_MAKER_FAIL') and request['key'].startswith('maker-'))
    blocker = os.environ.get('FAKE_PILOT_BLOCKER') if request['key'].startswith('pilot-') else None
    if blocker:
        if blocker == 'all':
            blocker = {('style-00', 'medea'): 'reference', ('style-00', 'bulat-okudzhava'): 'frames',
                       ('style-01', 'medea'): 'looks', ('style-01', 'bulat-okudzhava'): 'clarification'}[
                           (request['key'][6:-len(request['pet']) - 1], request['pet'])]
        reasons = {'reference': 'Required family reference is null.',
                   'frames': '24 frames per row conflict with the v2 atlas.',
                   'looks': 'Sixteen palette variants and sixteen paint treatments conflict with the v2 atlas.',
                   'clarification': 'Clarification remains unanswered.'}
        reply = dict(status='failed', reason=reasons[blocker], image_generations=0, repairs=[])
    elif refused:
        reply = dict(status='refused', reason='Provider safety refusal fixture; do not retry.', image_generations=0, repairs=[])
        print(json.dumps({'type': 'error', 'code': 'content_policy_violation'}))
    else:
        fixture = Path(os.environ['FAKE_ATLAS_FIXTURE'])
        shutil.copytree(fixture, work, dirs_exist_ok=True)
        if failed:
            (work / 'final/spritesheet.webp').write_bytes(b'broken fixture')
        reply = dict(status='complete', reason='Synthetic test fixture only.', image_generations=13, repairs=[])
        if os.environ.get('FAKE_PROVIDER_STOP_AFTER_ART') == request['pet']:
            for item in ({'type': 'thread.started'}, {'type': 'turn.started'},
                         {'type': 'item.completed', 'item': {'type': 'command_execution',
                                                          'command': 'prepared existing art'}},
                         {'type': 'turn.failed', 'error': {'code': 'rate_limit_exceeded',
                                                         'message': 'Rate limit exceeded'}}):
                print(json.dumps(item))
            event('end')
            sys.exit(1)
    if os.environ.get('FAKE_MOTION_FAILURE'):
        reply.update(status='failed', image_generations=16,
                     reason='Stopped after jumping exhausted both permitted repairs: its extracted peak remains '
                            '31 pixels above baseline, exceeding the preserved 10–14-pixel lift.')
        if os.environ['FAKE_MOTION_FAILURE'] != 'with-atlas':
            (work / 'final/spritesheet.webp').unlink(missing_ok=True)
    reply.update(contract_overrides=[], decisions=['Proceed without clarification using the supplied constraints.'])
    if request['reference'] is None:
        reply['decisions'].append('Create the pilot base without a family reference.')
    for source, original in request['style'].items():
        if source == 'framing' and ('24 frames' in original or '16 frames' in original):
            reply['contract_overrides'].append(dict(source='style.framing', original=original,
                replacement='Use the nine required row counts: 6,8,8,4,5,8,6,6,6; remap the four beats.',
                reason='The v2 contract fixes animation frame counts.'))
        if source == 'palette' and 'sixteen paint treatments' in original:
            reply['contract_overrides'].append(dict(source='style.palette', original=original,
                replacement='Keep the warm palette; use sixteen clockwise look directions in rows 9 and 10.',
                reason='The v2 looks are directions with consistent paint treatment.'))
    idle = request['style'].get('rows', {}).get('idle', '')
    if 'frames 13–24' in idle:
        reply['contract_overrides'].append(dict(source='style.rows.idle', original=idle,
            replacement='Breathe, blink and settle across six idle frames.',
            reason='Remap the style motion beats to the v2 idle count.'))
elif 'preset' in props:
    reply['style_notes'] = 'Quiet warm shapes in restrained ink.'
    if os.environ.get('FAKE_CONFLICTING_STYLES'):
        frames = 24 if 'medea-' in str(work) else 16
        reply['framing'] = f'Transparent cells, {frames} frames per row in four beats.'
        reply['palette'] = 'Warm ochre and blue, with sixteen paint treatments as palette variants.'
        reply['rows']['idle'] = 'Breathe, blink, then settle in frames 13–24.'
elif 'brief' in props:
    data = context()
    reply['brief'] = ' '.join(['A small companion keeps its own form and moves with care.'] * 15)
    reply['pet_notes'] = ' '.join(['Warm shapes preserve identity with quiet clear contours and simple attached details.'] * 5)
    reply['do_not_resemble'] = data['do_not_resemble']
    if any(key and key in str(work) for key in os.environ.get('FAKE_BAD_BRIEF', '').split(',')):
        reply['brief'] = 'Too short.'
elif 'vetoes' in props:
    data = context()
    ids = list(data['candidates'])
    originality = 'You are Originality.' in prompt
    reply.update(vetoes=[], flags=[])
    if 'ranking' in props:
        reply['ranking'] = [] if originality else (list(reversed(ids)) if model == 'comparison-test' else ids)
        if 'reference_pilots' in props:
            reply['reference_pilots'] = {sid: None if originality else f'pilot-{sid}-bulat-okudzhava' for sid in ids}
            if os.environ.get('FAKE_STYLE_FLAGS') and (originality or 'style-decision-painter-' in str(work)):
                reply['flags'] = [dict(target=x, why='Waiting, work and review resemble idle; drawing note only.') for x in ids]
        if os.environ.get('FAKE_REJECT_FIRST_STYLES') and 'shortlist-0-painter-' in str(work):
            reply['flags'] = [dict(target=x, why='Synthetic technical defect.') for x in ids]
    elif 'verdicts' in props:
        redos = os.environ.get('FAKE_REDO', '').split(',') if 'image-review-' in str(reply_path) else []
        if any(stage in str(reply_path) for stage in ('redo-review-', 'maker-review-')):
            redos = os.environ.get('FAKE_FINAL_REJECT', '').split(',')
        reply['verdicts'] = [dict(target=x, verdict='redo' if x in redos else 'keep',
                                 why=os.environ.get('FAKE_REVIEW_REASON', 'Check the attached shape.')) for x in ids]
    elif os.environ.get('FAKE_BRIEF_REPAIR') in ids:
        reply['flags'] = [dict(target=os.environ['FAKE_BRIEF_REPAIR'], why='Clarify the attached prop boundary.')]
else:
    if 'stance' in props:
        reply['stance'] = 'object' if model == 'comparison-test' else 'agree'
        reply['strong'] = False
    if 'favorite_place' in props:
        reply['favorite_place'] = 'A' if model == 'primary-test' else 'B'
    if 'veto' in props:
        reply['veto'] = None
if os.environ.get('FAKE_BAD_REPLY') and os.environ['FAKE_BAD_REPLY'] in str(work) and work.name.endswith('-0'):
    reply = {}
for variable, field in [('FAKE_REPEAT_RANKING', 'ranking'), ('FAKE_REPEAT_ALSO', 'also')]:
    if os.environ.get(variable) and os.environ[variable] in str(work):
        if work.name.endswith('-0') or os.environ.get('FAKE_INVALID_TWICE'):
            choices = props[field]['items']['enum']
            reply[field] = [choices[0], choices[0]]
if os.environ.get('FAKE_BAD_WORKER') and os.environ['FAKE_BAD_WORKER'] in str(work):
    if reply_path.name == 'reply.json' or os.environ.get('FAKE_INVALID_TWICE'):
        reply['image_generations'] = -1
reply_path.write_text(json.dumps(reply))
print(json.dumps({'type': 'turn.completed', 'usage': {'input_tokens': 10, 'output_tokens': 20}}))
event('end')
