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
    refused = request['pet'] == os.environ.get('FAKE_REFUSE') and request['key'].startswith('set-')
    failed = request['pet'] == os.environ.get('FAKE_FAIL') and request['key'].startswith('set-')
    if refused:
        reply = dict(status='refused', reason='Provider safety refusal fixture; do not retry.', image_generations=0, repairs=[])
        print(json.dumps({'type': 'error', 'code': 'content_policy_violation'}))
    else:
        fixture = Path(os.environ['FAKE_ATLAS_FIXTURE'])
        shutil.copytree(fixture, work, dirs_exist_ok=True)
        if failed:
            (work / 'final/spritesheet.webp').write_bytes(b'broken fixture')
        reply = dict(status='complete', reason='Synthetic test fixture only.', image_generations=13, repairs=[])
elif 'preset' in props:
    reply['style_notes'] = 'Quiet warm shapes in restrained ink.'
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
        if os.environ.get('FAKE_REJECT_FIRST_STYLES') and 'shortlist-0-painter-' in str(work):
            reply['flags'] = [dict(target=x, why='Synthetic technical defect.') for x in ids]
    elif 'verdicts' in props:
        redo = 'image-review-' in str(reply_path) and os.environ.get('FAKE_REDO') in ids
        reply['verdicts'] = [dict(target=x, verdict='redo' if redo and x == os.environ['FAKE_REDO'] else 'keep',
                                 why='Check the attached shape.') for x in ids]
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
