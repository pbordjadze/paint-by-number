"""An explicit maker's commission, separate from the Lamp's immutable verdicts."""
from pathlib import Path

from . import loop, paths, schema
from .codex_lamp import frozen, digest

CALL = schema.obj({'version': {'type': 'integer', 'enum': [1]}, 'maker': schema.STRING,
    'statement': schema.STRING, 'pets': schema.array(schema.obj({
        'pet': schema.STRING, 'action': {'type': 'string', 'enum': ['attempt', 'leave']},
        'reason': schema.STRING, 'instruction': schema.STRING}))})
CALL['properties']['pets']['minItems'] = 1


def load_call(path):
    call = loop.load(path)
    errors = schema.validate(call, CALL)
    if errors:
        raise ValueError('invalid maker call: ' + '; '.join(errors))
    ids = [paths.slug(p['pet']) for p in call['pets']]
    if len(ids) != len(set(ids)):
        raise ValueError('duplicate pet in maker call')
    statement = paths.contained(path.parent.resolve(), call['statement']).read_text()
    return {**call, 'statement_text': statement, 'statement_sha256': digest(statement.encode())}


def commission(run, call_path, results):
    """Read-only, so list-resume can show precisely the same authorization."""
    from .lamp_resume import decision, refused_attempt
    saved = loop.load(paths.contained(run, 'decisions/makers-call.json'))
    call = load_call(Path(call_path)) if call_path else saved['call'] if saved else None
    if call is None:
        return None
    if saved and saved['call'] != call:
        raise ValueError('frozen maker call differs; the recorded commission cannot be replaced')
    evidence = {}
    for choice in call['pets']:
        pet = choice['pet']
        previous = results.get(pet)
        if previous is None:
            raise ValueError('maker call requires a recorded Lamp outcome: ' + pet)
        if choice['action'] == 'attempt':
            for prefix in ('set-', 'redo-'):
                if refused_attempt(paths.contained(run, 'hatches', prefix + pet)):
                    raise ValueError('provider refusal is terminal: ' + pet)
            if previous['status'] == 'failed':
                plan = decision(paths.contained(run, 'hatches', previous['key']))
                if plan['action'] != 'keep' or previous.get('fresh_attempts', 0) < 1:
                    raise ValueError('maker attempt requires an exhausted Lamp gate budget: ' + pet)
            elif previous['status'] != 'rejected':
                raise ValueError('maker attempt requires a rejected or terminal failed pet: ' + pet)
        reports = []
        if previous.get('work'):
            work = paths.contained(run, Path(previous['work']).relative_to(run))
            for name in ('qa/direction-semantics.json', 'qa/pet-quality.json', 'gate/quality.json'):
                path = paths.contained(work, name)
                if path.exists():
                    reports.append({'path': str(path), 'sha256': digest(path.read_bytes()),
                                    'report': loop.load(path)})
        evidence[pet] = {'decision': choice, 'previous': previous, 'validator_reports': reports}
    record = {'authority': 'maker', 'call': call, 'evidence': evidence,
              'limits': 'One maker attempt per commissioned pet; unchanged validators, two repairs per failing row, '
                        'one image jury, no jury redo. Lamp outcomes remain as recorded.'}
    if saved and saved != record:
        raise ValueError('frozen maker evidence differs')
    return record


def finish(lamp, call_path, results, briefs, style, reference):
    from .lamp_images import review
    from .lamp_hatch import publish, hatch_request, verify_package
    record = commission(lamp.run, call_path, results)
    if record is None:
        return None
    frozen(paths.contained(lamp.run, 'decisions/makers-call.json'), record)
    target = paths.contained(lamp.run, 'decisions/maker-images.json')
    completed = loop.load(target)
    items = [dict(key='maker-' + pet, pet=pet, brief=briefs[pet], style=style,
                  reference=reference, redo=None,
                  maker={'authority': 'maker', 'maker': record['call']['maker'],
                         'statement_sha256': record['call']['statement_sha256'],
                         'limits': record['limits'], **evidence})
             for pet, evidence in record['evidence'].items() if evidence['decision']['action'] == 'attempt']
    if completed:
        for item in items:
            request = paths.contained(lamp.run, 'hatches', item['key'], 'request.json')
            if loop.load(request) != hatch_request(lamp, **item):
                raise ValueError(f'frozen input differs: {request}')
            verify_package(lamp, completed['pets'][item['pet']])
    else:
        attempts = lamp.hatch_many(items)
        candidates = {p['pet']: p for p in attempts if p['status'] == 'validated'}
        reviews, sources = review(lamp, 10, 'maker-review', candidates, briefs, style)
        rejected = lamp.redos(reviews)
        pets = {p['pet']: {**p, 'status': 'rejected', 'reasons': rejected[p['pet']]}
                if p['pet'] in rejected else p for p in attempts}
        pets.update({pet: {'pet': pet, 'status': 'left', 'reason': evidence['decision']['reason']}
                     for pet, evidence in record['evidence'].items() if evidence['decision']['action'] == 'leave'})
        completed = frozen(target, {'authority': 'maker', 'commission_sha256': digest(record),
                                   'reviews': reviews, 'review_sources': sources, 'pets': pets})
    if completed['commission_sha256'] != digest(record):
        raise ValueError('maker image decision belongs to a different commission')
    for pet, result in completed['pets'].items():
        if result['status'] == 'validated':
            publish(lamp, result, briefs[pet], style)
    return completed['pets']


def listing(run, call_path):
    from .lamp_images import state
    from .lamp_resume import decision
    pets, _ = state(run)
    record = commission(run, call_path, pets)
    if record is None:
        return None
    completed = loop.load(paths.contained(run, 'decisions/maker-images.json'))
    choices = []
    for pet, evidence in record['evidence'].items():
        choice = evidence['decision']
        info = {'pet': pet, 'authority': 'maker', 'decision': choice,
                'action': choice['action'], 'reason': choice['reason'], 'model_call': False}
        if completed:
            info.update(action='keep', status=completed['pets'][pet]['status'])
        elif choice['action'] == 'attempt':
            info.update(decision(paths.contained(run, 'hatches', 'maker-' + pet)))
        choices.append(info)
    return {'authority': 'maker', 'recorded': paths.contained(run, 'decisions/makers-call.json').exists(),
            'statement_sha256': record['call']['statement_sha256'], 'pets': choices,
            'model_hatches': sum(p['model_call'] for p in choices),
            'review': 'Each validated maker candidate needs a separate jury; no further redo.'}
