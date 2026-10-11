"""Usage from Claude transcripts or Codex JSONL; unknown measurements remain null."""
import datetime
import json
from pathlib import Path

from . import loop


def usage(path):
    records = [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]
    timestamps, claude, codex, durations = [], {}, [], []
    for index, event in enumerate(records):
        stamp = event.get('timestamp')
        if stamp:
            timestamps.append(datetime.datetime.fromisoformat(stamp.replace('Z', '+00:00')))
        if event.get('duration_ms') is not None:
            durations.append(event['duration_ms'] / 1000)
        message = event.get('message', {})
        if isinstance(message, dict) and message.get('usage'):
            # Streaming snapshots of the same message replace, rather than double-count, usage.
            claude[message.get('id', str(index))] = message['usage']
        if event.get('type') == 'turn.completed' and event.get('usage'):
            codex.append(event['usage'])
    inputs, outputs, cached, found = 0, 0, 0, bool(claude or codex)
    for u in claude.values():
        cache = u.get('cache_read_input_tokens', 0) + u.get('cache_creation_input_tokens', 0)
        inputs += u.get('input_tokens', 0) + cache
        cached += cache
        outputs += u.get('output_tokens', 0)
    for u in codex:
        inputs += u.get('input_tokens', 0)
        cached += u.get('cached_input_tokens', 0)
        outputs += u.get('output_tokens', 0)
    seconds = (max(timestamps) - min(timestamps)).total_seconds() if len(timestamps) >= 2 else None
    if durations:
        seconds = durations[-1]
    return {'input_tokens': inputs if found else None, 'output_tokens': outputs if found else None,
            'cached_input_tokens': cached if found else None, 'seconds': seconds}


def record(run, job, log, elapsed=None):
    measurements = usage(log)
    if elapsed is not None:
        measurements['seconds'] = elapsed
    item = {'job': job['id'], 'round': job['round'], 'attempt': job['attempt'],
            'role': job['role'], 'guardian': job['guardian'], 'model': job['model'],
            'log': str(Path(log).resolve()), **measurements}
    loop.save(Path(run) / 'costs' / f"{job['round']:03}" / f"{job['id']}-{job['attempt']}.json", item)
    return item


def report(run):
    agents = [loop.load(p) for p in sorted(Path(run).glob('costs/*/*.json'))]
    fields = ('input_tokens', 'output_tokens', 'cached_input_tokens', 'seconds')
    measured = {(a['round'], a['job'], a['attempt']) for a in agents}
    for path in sorted([*Path(run).glob('jobs/*/*.json'), *Path(run).glob('retries/*/*.json')]):
        job = loop.load(path)
        if (job['round'], job['id'], job['attempt']) not in measured:
            agents.append({'job': job['id'], 'round': job['round'], 'attempt': job['attempt'],
                           'role': job['role'], 'guardian': job['guardian'], 'model': job['model'],
                           'log': None, **dict.fromkeys(fields)})
    return {'agents': agents, 'totals': {f: sum(a[f] for a in agents if a[f] is not None) for f in fields},
            'unmeasured': {f: sum(a[f] is None for a in agents) for f in fields}}
