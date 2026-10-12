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


def history(run):
    files = [paths.contained(run, 'decisions/maker-images.json')]
    files += sorted(paths.contained(run, p.relative_to(run))
                    for p in (run / 'decisions/maker-image-resumes').glob('*.json'))
    return [(path, loop.load(path)) for path in files if path.exists()]


def state(run):
    from .lamp_resume import size_only_failure
    pets, settled = {}, {}
    for path, record in history(run):
        for pet, result in record['pets'].items():
            if pet in settled and pets[pet] != result:
                raise ValueError(f'completed maker decision differs: {path}/{pet}')
            pets[pet] = result
            # A package failure has not reached the maker jury yet. Everything
            # else retains its decision, including rejections and exhausted gates.
            if not size_only_failure(result):
                settled[pet] = path
    return pets, settled


def finish(lamp, call_path, results, briefs, style, reference):
    from .lamp_images import review
    from .lamp_hatch import publish, hatch_request, verify_package
    record = commission(lamp.run, call_path, results)
    if record is None:
        return None
    frozen(paths.contained(lamp.run, 'decisions/makers-call.json'), record)
    prior = history(lamp.run)
    if any(completed['commission_sha256'] != digest(record) for _, completed in prior):
        raise ValueError('maker image decision belongs to a different commission')
    pets, settled = state(lamp.run)
    items = [dict(key='maker-' + pet, pet=pet, brief=briefs[pet], style=style,
                  reference=reference, redo=None,
                  maker={'authority': 'maker', 'maker': record['call']['maker'],
                         'statement_sha256': record['call']['statement_sha256'],
                         'limits': record['limits'], **evidence})
             for pet, evidence in record['evidence'].items() if evidence['decision']['action'] == 'attempt']
    for item in items:
        if item['pet'] not in pets:
            continue
        request = paths.contained(lamp.run, 'hatches', item['key'], 'request.json')
        if loop.load(request) != hatch_request(lamp, **item):
            raise ValueError(f'frozen input differs: {request}')
        verify_package(lamp, pets[item['pet']])
    attempts = lamp.hatch_many([item for item in items if item['pet'] not in settled])
    candidates = {p['pet']: p for p in attempts if p['status'] == 'validated'}
    reviews, sources = review(lamp, 10, 'maker-review', candidates, briefs, style)
    rejected = lamp.redos(reviews)
    pending = {p['pet']: {**p, 'status': 'rejected', 'reasons': rejected[p['pet']]}
               if p['pet'] in rejected else p for p in attempts}
    pending.update({pet: {'pet': pet, 'status': 'left', 'reason': evidence['decision']['reason']}
                    for pet, evidence in record['evidence'].items() if evidence['decision']['action'] == 'leave'})
    changed = {pet: result for pet, result in pending.items() if pets.get(pet) != result}
    if changed or not prior:
        target = paths.contained(lamp.run, 'decisions/maker-images.json') if not prior else paths.contained(
            lamp.run, 'decisions/maker-image-resumes', f'{len(prior):06}.json')
        frozen(target, {'authority': 'maker', 'commission_sha256': digest(record),
                        'reviews': reviews, 'review_sources': sources, 'pets': changed})
    pets.update(pending)
    for pet, result in pets.items():
        if result['status'] == 'validated':
            publish(lamp, result, briefs[pet], style)
    return pets


def listing(run, call_path):
    from .lamp_images import state as image_state, review_plan
    from .lamp_resume import decision, latest_result
    from .codex_lamp import Lamp
    pets, _ = image_state(run)
    record = commission(run, call_path, pets)
    if record is None:
        return None
    completed, settled = state(run)
    choices, candidates, repackages = [], {}, []
    for pet, evidence in record['evidence'].items():
        choice = evidence['decision']
        info = {'pet': pet, 'authority': 'maker', 'decision': choice,
                'action': choice['action'], 'reason': choice['reason'], 'model_call': False}
        if pet in settled:
            info.update(action='keep', status=completed[pet]['status'], reason='completed maker decision retained')
        elif choice['action'] == 'attempt':
            base = paths.contained(run, 'hatches', 'maker-' + pet)
            info.update(decision(base))
            _, result = latest_result(base)
            if result and result['status'] == 'validated':
                candidates[pet] = result
                info.update(action='review', reason='validated maker candidate still needs its jury decision')
            elif info['action'] == 'repackage':
                repackages.append(pet)
        choices.append(info)
    inputs = loop.load(paths.contained(run, 'inputs.json'))
    panel = object.__new__(Lamp)
    panel.seats = {g['id']: g for g in inputs['guardians']}
    seats = panel.jury(3)
    brief_record = loop.load(paths.contained(run, 'decisions/briefs.json'), {})
    plan = review_plan(run, 10, 'maker-review', candidates, brief_record.get('briefs', {}),
                       brief_record.get('style', {}), seats, loop.load(paths.contained(run, 'run.json'))['model'])
    return {'authority': 'maker', 'recorded': paths.contained(run, 'decisions/makers-call.json').exists(),
            'statement_sha256': record['call']['statement_sha256'], 'pets': choices,
            'model_hatches': sum(p['model_call'] for p in choices),
            'pending': list(candidates), 'review_plan': plan,
            'jury_calls': sum(bool(missing) for missing in plan['missing'].values()),
            'review_after_repackage': repackages,
            'jury_calls_after_repackage': len(seats) if repackages else 0,
            'review': 'Each validated maker candidate needs a separate jury; no further redo.'}
