"""Append-only image decisions; completed juries belong to the pets they saw."""
import json
from pathlib import Path

from . import loop, paths
from .codex_lamp import digest, frozen


def history(run):
    files = [paths.contained(run, 'decisions/images.json')]
    files += sorted(paths.contained(run, p.relative_to(run))
                    for p in (run / 'decisions/image-resumes').glob('*.json'))
    return [(path, loop.load(path)) for path in files if path.exists()]


def state(run):
    from .lamp_resume import size_only_failure
    pets, settled = {}, {}
    for path, decision in history(run):
        for pet, result in decision['pets'].items():
            if pet in settled and pets[pet] != result:
                raise ValueError(f'completed image decision differs: {path}/{pet}')
            pets[pet] = result
            # Failed set hatches may still become candidates on a later resume.
            # A spent redo cannot draw again, but may still need local packaging.
            if (result['status'] in ('validated', 'rejected', 'refused', 'invalid')
                    or pet in decision['redos'] and not size_only_failure(result)):
                settled[pet] = (path, decision)
    return pets, settled


def review_plan(run, number, stage, candidates, briefs, style, seats, model):
    """Read-only reuse plan, including terminal invalid ballots, per seat and pet.

    Legacy expanded juries may include already settled pets. Only their verdicts
    for the pending candidates enter this pass; original jobs and replies stay whole.
    """
    sources = {seat: {} for seat in seats}
    for path in sorted((run / 'jobs' / f'{number:03}').glob(f'{stage}-*.json')):
        path = paths.contained(run, path.relative_to(run))
        job = loop.load(path)
        seat = job['guardian']
        if (seat not in sources or job['model'] != model
                or not (job['stage'] == stage or job['stage'].startswith(stage + '-resume-'))):
            continue
        record_path = paths.job_path(run, job, 'records')
        record = loop.load(record_path)
        if record is not None and record['job_sha256'] != digest(job):
            raise ValueError(f'job changed after completion: {path}')
        context = json.JSONDecoder().raw_decode(job['prompt'].split('\nContext:\n', 1)[1])[0]
        overlap = {pet for pet in candidates if pet in context['candidates']}
        if not overlap:
            continue
        for pet in overlap:
            if (context['candidates'][pet] != candidates[pet]
                    or context['briefs'][pet] != briefs[pet] or context['style'] != style):
                raise ValueError(f'frozen image input differs: {path}/{pet}')
        if record is None:
            continue
        for pet in overlap:
            sources[seat].setdefault(pet, {'job': str(path), 'record': str(record_path)})
    return {'sources': sources,
            'missing': {seat: [pet for pet in candidates if pet not in sources[seat]] for seat in seats}}


def review(lamp, number, stage, candidates, briefs, style):
    plan = review_plan(lamp.run, number, stage, candidates, briefs, style, lamp.jury(3), lamp.model)
    groups, fresh_reviews = {}, {}
    for seat, missing in plan['missing'].items():
        if missing:
            groups.setdefault(tuple(missing), []).append(seat)
    for missing, seats in groups.items():
        fresh_reviews.update(lamp.image_review(number, stage, {p: candidates[p] for p in missing},
                                               briefs, style, seats=seats))
    reviews = {}
    for seat, sources in plan['sources'].items():
        reply = {'verdicts': [], 'flags': [], 'vetoes': [], 'why': ''}
        for source in dict.fromkeys(s['record'] for s in sources.values()):
            record = loop.load(Path(source))
            if record.get('status') == 'invalid':
                continue
            targets = {pet for pet, info in sources.items() if info['record'] == source}
            for field in ('verdicts', 'flags', 'vetoes'):
                reply[field].extend(v for v in record['reply'][field] if v['target'] in targets)
            reply['why'] += record['reply']['why'] + '\n'
        fresh = fresh_reviews.get(seat)
        if fresh:
            for field in ('verdicts', 'flags', 'vetoes'):
                reply[field].extend(fresh[field])
            reply['why'] += fresh['why'] + '\n'
        if reply['verdicts']:
            reviews[seat] = reply
    # Recompute after calls so the decision names every durable source record.
    return reviews, review_plan(lamp.run, number, stage, candidates, briefs, style,
                                lamp.jury(3), lamp.model)['sources']


def verify_settled(lamp, originals, briefs, style, reference, pets, settled):
    from .lamp_hatch import hatch_request, verify_package
    for pet, (_, decision) in settled.items():
        result = pets[pet]
        if pet in decision['redos']:
            request = hatch_request(lamp, 'redo-' + pet, pet, style, briefs[pet], reference,
                                    {'previous': originals[pet], 'reasons': decision['redos'][pet]})
            target = paths.contained(lamp.run, 'hatches', 'redo-' + pet, 'request.json')
            if loop.load(target) != request:
                raise ValueError(f'frozen input differs: {target}')
        elif pet in originals and originals[pet] != result:
            raise ValueError(f'completed image candidate changed: {pet}')
        verify_package(lamp, result)


def finish(lamp, originals, briefs, style, reference, invalid_briefs):
    from .lamp_hatch import publish
    pets, settled = state(lamp.run)
    originals = {p['pet']: p for p in originals}
    verify_settled(lamp, originals, briefs, style, reference, pets, settled)
    pending = {p: value for p, value in originals.items() if p not in settled}
    candidates = {p: value for p, value in pending.items() if value['status'] == 'validated'}
    reviews, sources = review(lamp, 9, 'image-review', candidates, briefs, style)
    redos = lamp.redos(reviews)
    replacements = lamp.hatch_many([dict(key='redo-' + pet, pet=pet, style=style, brief=briefs[pet],
        reference=reference, redo={'previous': candidates[pet], 'reasons': reasons})
        for pet, reasons in redos.items()])
    final = {p['pet']: p for p in replacements if p['status'] == 'validated'}
    final_reviews, final_sources = review(lamp, 10, 'redo-review', final, briefs, style)
    rejected = lamp.redos(final_reviews)
    pending.update({p['pet']: p for p in replacements})
    for pet, reasons in rejected.items():
        pending[pet] = {**pending[pet], 'status': 'rejected', 'reasons': reasons}
    pending.update({p: {'pet': p, 'status': 'invalid', 'reason': 'No valid owner brief after one reply repair.'}
                    for p in sorted(invalid_briefs) if p not in settled})
    changed = {p: result for p, result in pending.items() if pets.get(p) != result}
    if changed or not history(lamp.run):
        prior = history(lamp.run)
        target = paths.contained(lamp.run, 'decisions/images.json') if not prior else paths.contained(
            lamp.run, 'decisions/image-resumes', f'{len(prior):06}.json')
        frozen(target, {'reviews': reviews, 'redos': redos, 'redo_reviews': final_reviews,
                        'review_sources': sources, 'redo_review_sources': final_sources, 'pets': changed})
    pets.update(pending)
    # A crash during publication resumes from the decision, never another jury.
    for pet, result in pets.items():
        if result['status'] == 'validated':
            publish(lamp, result, briefs[pet], style)
    return pets


def listing(run, seats, model):
    from .lamp_resume import latest_result, decision
    brief_record = loop.load(paths.contained(run, 'decisions/briefs.json'), {})
    if not brief_record:
        return {'pending': [], 'reason': 'No approved briefs yet.'}
    pets, settled = state(run)
    briefs, style = brief_record['briefs'], brief_record.get('style', {})
    candidates = {}
    for pet in briefs:
        _, result = latest_result(paths.contained(run, 'hatches', 'set-' + pet))
        if pet not in settled and result and result['status'] == 'validated':
            candidates[pet] = result
    plan = review_plan(run, 9, 'image-review', candidates, briefs, style, seats, model)
    reviews = {}
    for seat, sources in plan['sources'].items():
        reviews[seat] = {'verdicts': [], 'flags': [], 'vetoes': []}
        for pet, source in sources.items():
            record = loop.load(Path(source['record']))
            if record.get('status') == 'invalid':
                continue
            for field in reviews[seat]:
                reviews[seat][field].extend(v for v in record['reply'][field] if v['target'] == pet)
    from .codex_lamp import Lamp
    redos = Lamp.redos(reviews)
    replacements = {}
    for pet in redos:
        _, result = latest_result(paths.contained(run, 'hatches', 'redo-' + pet))
        if result and result['status'] == 'validated':
            replacements[pet] = result
    final = review_plan(run, 10, 'redo-review', replacements, briefs, style, seats, model)
    return {'settled': {p: pets[p]['status'] for p in sorted(settled)},
            'pending': list(candidates), 'review': plan,
            'redos': {p: decision(paths.contained(run, 'hatches', 'redo-' + p)) for p in redos},
            'redo_review': final,
            'publish_after_review': [p for p in candidates if p not in redos
                                     and all(p not in missing for missing in plan['missing'].values())],
            'jury_calls': sum(bool(missing) for missing in plan['missing'].values())
                          + sum(bool(missing) for missing in final['missing'].values())}
