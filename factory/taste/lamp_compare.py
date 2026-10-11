"""Unchanged historical prompts and descriptive, paired model comparison (no judge model)."""
from collections import defaultdict
from itertools import combinations
import json
from pathlib import Path

from . import loop, paths, schema
from .codex_lamp import S, TEXT, digest, execute, frozen, parallel_map

CLAUDE = 'Claude (Haiku)'


def nullable(rule):
    return {'oneOf': [rule, {'type': 'null'}]}


def historical_schema(piece, seat):
    veto = nullable(schema.obj({'quote': S, 'why': S}))
    if piece == 'renumber':
        return schema.obj({'guardian': {'type': 'string', 'enum': [seat]}, 'stance': {'type': 'string', 'enum': ['agree', 'object']},
                           'strong': {'type': 'boolean'}, 'why': S})
    if piece == 'chapter-6':
        if seat == 'originality':
            return schema.obj({'guardian': {'type': 'string', 'enum': [seat]}, 'flags': schema.array(schema.obj({
                'pet': S, 'risk': S, 'fix': S})),
                'veto': nullable(schema.obj({'pet': S, 'why': S})), 'making': S})
        return schema.obj({'guardian': {'type': 'string', 'enum': [seat]}, 'keep': {'type': 'boolean'}, 'new_pet': TEXT,
            'why': S, 'favorite_place': {'type': 'string', 'enum': list('ABCDEFGH')},
            'also': {'type': 'array', 'items': {'type': 'string', 'enum': list('ABCDEFGH')}, 'maxItems': 2, 'uniqueItems': True},
            'veto': nullable(schema.obj({'place': {'type': 'string', 'enum': list('ABCDEFGH')}, 'quote': S, 'why': S})),
            'style': S, 'making': S})
    if piece == 'front-door':
        fields = {'placement': {'type': 'string', 'enum': ['top', 'section', 'both']}, 'heading': S, 'first_line': S,
                  'content': {'type': 'string', 'enum': ['A', 'B', 'C']}, 'content_why': S,
                  'picture': {'type': 'integer', 'enum': [1, 2, 3, 4, 5]}}
        if seat == 'originality':
            fields = dict.fromkeys(fields, {'type': 'null'})
        return schema.obj({'guardian': {'type': 'string', 'enum': [seat]}, **fields, 'avoid': S, 'veto': veto})
    raise ValueError(f'unsupported recorded piece: {piece}')


def replay_run(run, pieces, models, effort, parallel):
    if not models or any(not m.strip() for m in models) or len(set(models)) != len(models):
        raise ValueError('supply distinct nonempty model names')
    if not pieces or len(set(pieces)) != len(pieces) or set(pieces) - {'chapter-6', 'renumber', 'front-door'}:
        raise ValueError('pieces must be chapter-6, renumber and/or front-door')
    root = paths.contained(run, 'replay')
    root.mkdir(exist_ok=True)
    frozen(paths.contained(root, 'config.json'), dict(pieces=pieces, models=models, effort=effort))
    snapshot_path = paths.contained(root, 'sources.json')
    sources = loop.load(snapshot_path)
    if sources is None:
        sources = {}
        for piece in pieces:
            folder = loop.REPO / 'factory/pieces' / piece
            sources[piece] = {'brief': (folder / 'brief.md').read_text(), 'seats': {
                p.stem: {'prompt': p.read_text(), 'claude': loop.load(folder / 'replies' / (p.stem + '.json'))}
                for p in sorted((folder / 'prompts').glob('*.md'))}}
            if not sources[piece]['seats'] or any(s['claude'] is None for s in sources[piece]['seats'].values()):
                raise ValueError(f'missing historical prompts or replies: {piece}')
        frozen(snapshot_path, sources)
    jobs = []
    for number, (piece, data) in enumerate(sources.items(), 1):
        brief = paths.contained(root, 'inputs', piece, 'brief.md')
        if not brief.exists():
            loop.write_atomic(brief, data['brief'])
        elif brief.read_text() != data['brief']:
            raise ValueError('replay brief changed')
        transport = (f'This is a read-only replay of a recorded prompt, preserved byte for byte. '
            f'When that prompt requests /home/user/paint-by-number/factory/pieces/{piece}/brief.md, '
            f'read the frozen identical brief at {brief} instead. The old Write-tool instruction is '
            'a transport instruction only: return the requested JSON as your final reply, not done; '
            'do not write files. Do not read other jobs, replies or model results. No web or service writes.')
        for seat, source in data['seats'].items():
            baseline = {'id': f'{piece}-{seat}-claude', 'round': number, 'guardian': seat,
                        'model': CLAUDE, 'effort': None, 'role': 'replay', 'stage': piece,
                        'prompt_sha256': digest(source['prompt'].encode()), 'reply': source['claude'],
                        'reply_bytes': len(json.dumps(source['claude'], ensure_ascii=False).encode()),
                        'reply_characters': len(json.dumps(source['claude'], ensure_ascii=False)), 'cost': None}
            loop.save(paths.contained(root, 'baselines', piece, seat + '.json'), baseline)
            for index, model in enumerate(models):
                jobs.append(dict(id=f'{piece}-{seat}-m{index}', round=number, attempt=0,
                    role='replay', stage=piece, guardian=seat, model=model, effort=effort,
                    images=[], prompt=source['prompt'], reply_schema=historical_schema(piece, seat),
                    transport_instructions=transport))
    parallel_map(lambda job: execute(root, job), jobs, parallel)
    return {'replayed_jobs': len(jobs), 'claude_seats': sum(len(d['seats']) for d in sources.values())}


def votes(reply):
    result = {k: reply[k] for k in ('stance', 'strong', 'keep', 'favorite_place', 'also',
                                   'placement', 'content', 'picture', 'ranking') if k in reply}
    if 'verdicts' in reply:
        result['verdicts'] = {v['target']: v['verdict'] for v in reply['verdicts']}
    return result


def vetoes(reply):
    result = list(reply.get('vetoes', []))
    if reply.get('veto'):
        result.append(reply['veto'])
    return result


def reasons(reply):
    values = []
    def visit(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in ('why', 'making', 'content_why', 'risk', 'reason') and isinstance(item, str):
                    values.append(item)
                else:
                    visit(item)
        elif isinstance(value, list):
            for item in value:
                visit(item)
    visit(reply)
    return values[:3]


def agreement(a, b):
    av, bv = votes(a), votes(b)
    fields = {}
    for key in sorted(av.keys() & bv.keys()):
        if key == 'ranking':
            ar, br = av[key], bv[key]
            common = sorted(set(ar) & set(br))
            pairs = list(combinations(common, 2))
            fields[key] = {'top_equal': ar[0] == br[0] if ar and br else None,
                'pairs': len(pairs), 'agree': sum((ar.index(x) < ar.index(y)) ==
                (br.index(x) < br.index(y)) for x, y in pairs)}
        else:
            fields[key] = {'equal': av[key] == bv[key]}
    def targets(reply):
        return sorted(v.get('target', v.get('place', v.get('pet', 'whole-piece'))) for v in vetoes(reply))
    # Compare the presence and targets, not free-text wording. No vote is not agreement.
    return {'votes': fields, 'veto_targets_equal': targets(a) == targets(b),
            'vote_fields': len(fields), 'equal_vote_fields': sum(v.get('equal', False) for v in fields.values())}


def compare_run(run):
    records = []
    for source, pattern in [('pets', 'records/*/*.json'), ('replay', 'replay/records/*/*.json'),
                            ('replay', 'replay/baselines/*/*.json')]:
        for path in sorted(run.glob(pattern)):
            record = loop.load(path)
            records.append({**record, 'source': source})
    grouped = defaultdict(list)
    summaries = defaultdict(lambda: {'jobs': 0, 'vetoes': 0, 'reply_characters': 0, 'votes': [], 'reasons': []})
    for record in records:
        grouped[(record['source'], record['stage'], record['guardian'])].append(record)
        key = (record['guardian'], record['model'])
        summary = summaries[key]
        summary['jobs'] += 1
        summary['vetoes'] += len(vetoes(record['reply']))
        summary['reply_characters'] += record['reply_characters']
        summary['votes'].append({'source': record['source'], 'stage': record['stage'],
                                  'values': votes(record['reply'])})
        summary['reasons'] = (summary['reasons'] + reasons(record['reply']))[:3]
    comparisons = []
    for (source, stage, seat), rows in sorted(grouped.items()):
        for a, b in combinations(rows, 2):
            if a['model'] == b['model']:
                continue
            if a['prompt_sha256'] != b['prompt_sha256']:
                raise ValueError('cannot compare different prompts as matched jobs')
            comparisons.append({'source': source, 'stage': stage, 'guardian': seat,
                                'models': [a['model'], b['model']], **agreement(a['reply'], b['reply'])})
    seats = []
    for (seat, model), summary in sorted(summaries.items()):
        paired = [p for p in comparisons if p['guardian'] == seat and model in p['models']]
        seats.append({'guardian': seat, 'model': model, **summary, 'agreement': paired})
    report = {'version': 1, 'method': 'Matched prompts; categorical equality and ranking pair agreement. '
              'Free prose is quoted, not scored. Missing vote fields have no denominator. '
              'Pet comparison replies observe primary context; they are not an independent branch. '
              'Claude lengths are JSON-normalized; Codex lengths are raw reply characters.',
              'seats': seats, 'comparisons': comparisons,
              'replies': [{k: r[k] for k in ('source', 'stage', 'guardian', 'model', 'effort',
                                           'reply', 'reply_characters', 'prompt_sha256')} for r in records]}
    loop.save(paths.contained(run, 'comparison.json'), report)
    lines = ['# The Lamp across models', '', report['method'], '',
             '| Seat | Model | Jobs | Vetoes | Mean reply characters |', '| --- | --- | ---: | ---: | ---: |']
    for row in seats:
        lines.append(f'| {row["guardian"]} | {row["model"]} | {row["jobs"]} | {row["vetoes"]} | '
                     f'{row["reply_characters"] / row["jobs"]:.0f} |')
    for (source, stage, seat), rows in sorted(grouped.items()):
        lines += ['', f'## {seat} · {source}/{stage}', '']
        for row in rows:
            lines += [f'**{row["model"]}** (effort: {row["effort"] or "not recorded"})', '',
                      'Votes: `' + json.dumps(votes(row['reply']), ensure_ascii=False) + '`', '',
                      'Vetoes: `' + json.dumps(vetoes(row['reply']), ensure_ascii=False) + '`', '']
            for reason in reasons(row['reply']):
                lines += ['> ' + reason.replace('\n', '\n> '), '']
        for pair in comparisons:
            if (pair['source'], pair['stage'], pair['guardian']) == (source, stage, seat):
                lines += [f'Agreement {pair["models"][0]} / {pair["models"][1]}: `'
                          + json.dumps({k: pair[k] for k in ('votes', 'veto_targets_equal')}) + '`', '']
    loop.write_atomic(paths.contained(run, 'comparison.md'), '\n'.join(lines) + '\n')
    return {'records': len(records), 'paired_comparisons': len(comparisons),
            'markdown': str(run / 'comparison.md'), 'json': str(run / 'comparison.json')}
