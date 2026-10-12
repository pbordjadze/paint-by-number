"""Resumable, opt-in Lamp pet run; python -m factory.taste.codex_lamp --help.

Each completed job is a durable record. Only the primary model enters decisions;
comparison jobs receive identical prompts and schemas. No service pet is created.
"""
import argparse
import ast
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import tempfile

from . import loop, paths, runners, schema
from .kit import outside_repo

WORK = Path('/root/factory-out')
ROWS = ('idle', 'running-right', 'running-left', 'waving', 'jumping', 'failed',
        'waiting', 'running', 'review')
# Geometry and row order from work-pets/references/sprite-sheet-contract.md.
CONTRACT = """The v2 sprite-sheet contract fixes 192 × 208 cells, eight columns by eleven rows,
one transparent 1536 × 2288 atlas. The nine animation rows (0–8) have these exact frame counts:
idle 6, running-right 8, running-left 8, waving 4, jumping 5, failed 8, waiting 6,
running 6 (focused work, not locomotion), review 6. Unused cells stay fully transparent.
Rows 9 and 10 hold sixteen look directions, eight per row, clockwise in screen coordinates:
row 9: 000, 022.5, 045, 067.5, 090, 112.5, 135, 157.5;
row 10: 180, 202.5, 225, 247.5, 270, 292.5, 315, 337.5.
000 is up, 090 right, 180 down, 270 left. These are gaze/pose directions with the same
palette and treatment, not sixteen palette variants, paint treatments or separate animations.
"""
MOTION_POLICY = ("Style-sheet motion numbers (pixel displacement, angles, timing and amplitudes) "
                 "are drawing guidance. Only the skill's validators gate a pet; a measured difference "
                 "from style guidance is recorded in provenance, not a reason to fail or spend repairs.")
UNATTENDED = """This is an unattended codex exec run; nobody can answer questions.
Never ask for clarification or wait for an answer. Decide within the brief, style sheet and v2
contract, and record each assumption or technical decision in your reply (why for text jurors,
decisions for hatch workers). Technical choices (resolution, frames, export) belong to Codex;
the v2 contract overrides conflicting technical numbers while the sheet's taste stays binding.
"""
S = schema.STRING
TEXT = {'type': 'string'}
STYLE = schema.obj({
    'name': S, 'preset': {'type': 'string', 'enum': ['auto', 'pixel', 'plush', 'clay', 'sticker',
                                 'flat-vector', '3d-toy', 'painterly', 'brand-inspired']},
    'style_notes': S, 'framing': S, 'palette': S, 'line': S, 'boundaries': S,
    'rows': schema.obj(dict.fromkeys(ROWS, S)), 'why': S})
BRIEF = schema.obj({'display_name': S, 'description': S, 'brief': S, 'pet_notes': S,
                    'rows': schema.obj(dict.fromkeys(ROWS, S)),
                    'do_not_resemble': schema.array(S), 'why': S})
RULES = """Answer only in your reply as JSON matching the supplied schema. Do not write files.
Read only the supplied prompt and explicitly supplied images/context. Do not inspect other jobs or replies.
Use plain words. Name no real person beyond Paul and the guardians' namesakes in the charters.
Paul waived the approval steps for this run and retains a later veto. All pets remain local.
Preserve each seed's creature and personality; express it within the supported pet constraints.
No floating effects, scene background, text, speech bubbles, shadows or new props in review.
Native cells are 192 × 208. Nine animation rows must read distinctly; v2 adds sixteen look directions.
Every veto quotes the exact guards-against charter line, with a concrete reason. Originality
only vetoes in juries and never ranks taste. The Painter also guards function: readability at
192 × 208 in all nine rows. Function defects are flags with evidence, not invented charter quotes.
"""


def digest(value):
    data = value if isinstance(value, bytes) else json.dumps(value, sort_keys=True, ensure_ascii=False).encode()
    return hashlib.sha256(data).hexdigest()


def frozen(path, value):
    if path.exists():
        if loop.load(path) != value:
            raise ValueError(f'frozen input differs: {path}')
    else:
        loop.save(path, value)
    return value


@contextmanager
def locked(run):
    run = outside_repo(run)
    run.mkdir(parents=True, exist_ok=True)
    with paths.contained(run, '.lock').open('a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ValueError(f'another driver is using {run}') from exc
        yield run


def parallel_map(function, items, workers):
    # Settle every dispatched job before reporting a round error. Completed siblings survive.
    results, errors = {}, []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(function, item): i for i, item in enumerate(items)}
        for future in as_completed(futures):
            try:
                results[futures[future]] = future.result()
            except Exception as exc:
                errors.append(exc)
    if errors:
        raise RuntimeError(f'{len(errors)} job(s) failed: {errors[0]}') from errors[0]
    return [results[i] for i in range(len(items))]


def execute(run, job, validate=None):
    """Use the kit runner; retry invalid answers once with validation feedback.

    Transport crashes leave no completion and can resume. Invalid answers retain
    both attempts and a terminal invalid record if repair fails.
    """
    job_path = paths.job_path(run, job, 'jobs')
    frozen(job_path, job)
    record_path = paths.job_path(run, job, 'records')
    if record_path.exists():
        record = loop.load(record_path)
        if record['job_sha256'] != digest(job):
            raise ValueError(f'job changed after completion: {job_path}')
        if validate and record.get('status') != 'invalid':
            validate(record['reply'])
        return record
    errors, raw_reply = [], ''
    for attempt in (0, 1):
        current = {**job, 'attempt': attempt}
        current_path = job_path if not attempt else paths.job_path(run, current, 'retries')
        if attempt:
            current['prompt'] = schema.repair_prompt(job['prompt'], errors, raw_reply)
            # An older driver may already have dispatched an identical-prompt retry.
            if current_path.exists() and loop.load(current_path) == {**job, 'attempt': 1}:
                current = loop.load(current_path)
        frozen(current_path, current)
        reply_path = runners.destination(run, current)
        if not reply_path.exists():
            scratch = paths.contained(run, 'dispatch')
            scratch.mkdir(exist_ok=True)
            out = Path(tempfile.mkdtemp(prefix=job['id'] + '-', dir=scratch))
            runners.codex(run, current_path, out)
        raw_reply = reply_path.read_text()
        reply = None
        try:
            reply = loop.load(reply_path)
            errors = schema.validate(reply, job['reply_schema'])
            if not errors and validate:
                validate(reply)
        except ValueError as exc:
            errors = [str(exc)]
        if not errors:
            break
        loop.save(paths.job_path(run, current, 'rejections'), {'errors': errors, 'raw_reply': raw_reply})
    record = {key: job[key] for key in ('id', 'round', 'guardian', 'model', 'effort', 'role', 'stage')}
    if 'inputs_sha256' in job:
        record['inputs_sha256'] = job['inputs_sha256']
    record.update(job_sha256=digest(job), prompt_sha256=digest(job['prompt'].encode()),
                  status='invalid' if errors else 'valid', errors=errors,
                  reply=reply, reply_bytes=reply_path.stat().st_size,
                  reply_characters=len(reply_path.read_text()), attempt=attempt,
                  costs=[loop.load(paths.job_path(run, {**job, 'attempt': n}, 'costs')) for n in range(attempt + 1)])
    loop.save(record_path, record)
    return record


def source_snapshot():
    # The collection page owns the current seeds. Read its literal without running its CLI.
    tree = ast.parse((loop.REPO / 'tools/factory/collection.py').read_text())
    seeds = next(ast.literal_eval(node.value) for node in ast.walk(tree)
                 if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'PETS'
                                                        for t in node.targets))
    chapter = {p.stem: loop.load(p) for p in sorted((loop.REPO / 'factory/pieces/chapter-6/replies').glob('*.json'))}
    avoid = {gid: ['No franchise look-alike, logo, real-person likeness or copied artwork.'] for gid in seeds}
    for flag in chapter['originality']['flags']:
        avoid[flag['pet']].append(flag['risk'] + ' ' + flag['fix'])
    return {'guardians': loop.guardians(), 'seeds': seeds, 'chapter_6': chapter,
            'avoid': avoid,
            'brief': (loop.REPO / 'factory/pieces/pets/brief.md').read_text(), 'rules': RULES}


def ballot_schema(ids, ranking=True):
    target = {'type': 'string', 'enum': ids}
    veto = schema.obj({'target': target, 'quote': S, 'why': S})
    flag = schema.obj({'target': target, 'why': S})
    fields = {'vetoes': schema.array(veto), 'flags': schema.array(flag), 'why': S}
    if ranking:
        fields['ranking'] = schema.array(target, unique=True)
    else:
        fields['verdicts'] = schema.array(schema.obj({'target': target,
                            'verdict': {'type': 'string', 'enum': ['keep', 'redo']}, 'why': S}), len(ids))
    return schema.obj(fields)


class Lamp:
    def __init__(self, run, model, compare, effort, parallel, image_workers, skill_dir=None):
        self.run, self.parallel, self.image_workers = run, parallel, image_workers
        if run != WORK and WORK not in run.parents:
            raise ValueError(f'run work must be under {WORK}')
        from .lamp_hatch import find_skill, skill_hashes
        existing = loop.load(paths.contained(run, 'run.json'))
        from . import lamp_rules
        lamp_rules.initialize(run, new=existing is None)
        self.dry_resume = False
        config = {'version': 1, 'model': model, 'compare': compare, 'effort': effort,
                  'skill_dir': str(find_skill(skill_dir or (existing or {}).get('skill_dir')))}
        self.config = frozen(paths.contained(run, 'run.json'), config)
        frozen(paths.contained(run, 'skill.json'), skill_hashes(Path(config['skill_dir'])))
        inputs = paths.contained(run, 'inputs.json')
        self.inputs = loop.load(inputs) if inputs.exists() else frozen(inputs, source_snapshot())
        from . import lamp_inputs
        self.inputs = lamp_inputs.current(run)
        self.seats = {g['id']: g for g in self.inputs['guardians']}
        self.models = list(dict.fromkeys([model] + ([compare] if compare else [])))
        self.model, self.effort = model, effort

    def jury(self, stage):
        others = [g for g in self.seats if g not in ('originality', 'painter', 'bible-school-teacher')]
        offset = (stage * 4) % len(others)
        rotated = others[offset:] + others[:offset]
        return ['originality', 'painter'] + rotated[:4]

    def prompt(self, seat, task, context, inputs=None):
        inputs = inputs or self.inputs
        g = next(g for g in inputs['guardians'] if g['id'] == seat)
        text = (inputs['rules'] + '\n' + UNATTENDED + CONTRACT + MOTION_POLICY
                + f'\nYou are {g["name"]}.\nYour charter:\n{g["charter_text"]}\n'
                + task + '\nContext:\n' + json.dumps(context, indent=2, ensure_ascii=False))
        text += '\n' + loop.names_prompt(inputs['guardians'])
        return text

    def round(self, number, stage, seats, task, context, rule, *, compare=False, images=()):
        from . import lamp_inputs
        inputs_sha, inputs = lamp_inputs.for_step(self.run, number)
        jobs = []
        for seat in seats:
            payload = context[seat] if stage in ('briefs', 'brief-repair') else context
            prompt = self.prompt(seat, task, payload, inputs)
            seat_jobs, saved_prompts = [], set()
            for index, model in enumerate(self.models if compare else [self.model]):
                job = dict(id=f'{stage}-{seat}-m{index}', round=number, attempt=0,
                           role='guardian', stage=stage, guardian=seat, model=model,
                           effort=self.effort, images=list(images), prompt=prompt, reply_schema=rule,
                           inputs_sha256=inputs_sha)
                saved = loop.load(paths.job_path(self.run, job, 'jobs'))
                if saved:
                    saved_prompts.add(saved['prompt'])
                    if 'inputs_sha256' not in saved:
                        job.pop('inputs_sha256')
                seat_jobs.append(job)
            if len(saved_prompts) > 1:
                raise ValueError(f'primary/comparison prompts differ: {stage}/{seat}')
            # Keep dispatched prompts across driver fixes, including an unfinished model pair.
            # execute still checks all other job inputs and the completion hash.
            if saved_prompts:
                for job in seat_jobs:
                    job['prompt'] = next(iter(saved_prompts))
            jobs.extend(seat_jobs)
        if self.dry_resume:
            for job in jobs:
                if not paths.job_path(self.run, job, 'records').exists():
                    raise ValueError(f'dry resume needs a completed job: {job["id"]}')
        records = parallel_map(lambda job: execute(self.run, job,
            lambda reply: self.check(job['guardian'], reply, stage, context, inputs)), jobs, self.parallel)
        primary = {r['guardian']: r['reply'] for r in records
                   if r['model'] == self.model and r.get('status') != 'invalid'}
        return primary

    def check(self, seat, reply, stage, context, inputs=None):
        inputs = inputs or self.inputs
        if stage == 'style-decision':
            nominations = reply['reference_pilots'].values()
            if any((pilot is None) != (seat == 'originality') for pilot in nominations):
                raise ValueError('taste jurors must nominate reference pilots; Originality must abstain with null')
        if stage.startswith('style-proposals') and len(reply['style_notes'].split()) > 80:
            raise ValueError('style notes exceed 80 words')
        if stage in ('briefs', 'brief-repair'):
            if not 150 <= len(reply['brief'].split()) <= 300 or not 50 <= len(reply['pet_notes'].split()) <= 80:
                raise ValueError(f'{seat}: brief must be 150–300 words; pet notes 50–80')
            if not set(inputs['avoid'][seat]) <= set(reply['do_not_resemble']):
                raise ValueError(f'{seat}: omitted do-not-resemble entry')
        if 'vetoes' in reply:
            guardian = next(g for g in inputs['guardians'] if g['id'] == seat)
            guard = loop.charter_line(guardian['charter_text'], 'guards against')
            for veto in reply['vetoes']:
                if ' '.join(veto['quote'].split()) != guard:
                    raise ValueError(f'{seat}: veto must quote the entire guards-against line verbatim')
            if 'ranking' in reply:
                expected = [] if seat == 'originality' else list(context['candidates'])
                if sorted(reply['ranking']) != sorted(expected):
                    raise ValueError(f'{seat}: incomplete ranking, or Originality voted')
            if 'verdicts' in reply:
                if sorted(v['target'] for v in reply['verdicts']) != sorted(context['candidates']):
                    raise ValueError(f'{seat}: image review must cover every candidate once')

    def tally(self, name, candidates, votes, count):
        from . import lamp_rules
        record = lamp_rules.tally(candidates, votes, count,
                                 style_rules=lamp_rules.for_style(self.run) if name == 'style' else None)
        loop.save(paths.contained(self.run, 'decisions', name + '.json'), record)
        return record['selected']

    def hatch_many(self, items):
        from .lamp_hatch import hatch
        from .lamp_inputs import bind_step
        for kind in sorted({item['key'].split('-')[0] for item in items}):
            bind_step(self.run, {'pilot': '2', 'set': '6', 'redo': '7', 'maker': '7'}[kind])
        return parallel_map(lambda item: hatch(self, **item), items, self.image_workers)

    def run_plan(self, *, dry_resume=False, makers_call=None):
        self.dry_resume = dry_resume
        print('1/7 Style proposals and shortlist', flush=True)
        proposals = [g for g in self.seats if g != 'originality']
        previous = None
        for revision in range(2):
            styles = self.round(1 + revision * 2, f'style-proposals-{revision}', proposals,
                'Propose one complete family style sheet. Style notes at most 80 words. '
                'Describe expression and timing within the contract\'s fixed frame counts, nine animation '
                'rows and sixteen look directions. Do not invent frame counts, rows or alternate paint '
                'looks. Address the ink-versus-glass tension.',
                {'seeds': self.inputs['seeds'], 'chapter_6': self.inputs['chapter_6'],
                 'previous_rejection': previous}, STYLE, compare=True)
            ids = {f'style-{i:02}': value for i, value in enumerate(styles.values())}
            votes = self.round(2 + revision * 2, f'shortlist-{revision}', self.jury(0),
                'Rank all style IDs; Originality returns an empty ranking. Veto only charter violations. '
                'Flag only concrete technical or shared-boundary failures. Select two viable styles.',
                {'candidates': ids}, ballot_schema(list(ids)), compare=True) if ids else {}
            selected = self.tally(f'shortlist-{revision}', ids, votes, 2)
            if len(selected) == 2:
                break
            previous = {'candidates': ids, 'votes': votes}
        if len(selected) != 2:
            raise ValueError('no two legal styles after two rounds; see decisions')
        styles = {i: ids[i] for i in selected}
        print('2/7 Four pilot hatches', flush=True)
        pilots = self.hatch_many([dict(key=f'pilot-{sid}-{pet}', pet=pet, style=style,
            brief={'seed': self.inputs['seeds'][pet], 'do_not_resemble': self.inputs['avoid'][pet]},
            reference=None, redo=None) for sid, style in styles.items()
            for pet in ('medea', 'bulat-okudzhava')])
        viable = {sid: style for sid, style in styles.items()
                  if all(p['status'] == 'validated' for p in pilots if p['key'].startswith(f'pilot-{sid}-'))}
        if not viable:
            raise ValueError('neither style has two validated pilots; failures recorded, no style guessed')
        print('3/7 Image jury selects the style', flush=True)
        images = [p['contact'] for p in pilots if p['status'] == 'validated']
        reference_choices = {sid: [p['key'] for p in pilots if p['key'].startswith(f'pilot-{sid}-')]
                             for sid in viable}
        rule = ballot_schema(list(viable))
        rule['properties']['reference_pilots'] = schema.obj({sid: {'oneOf': [
            {'type': 'string', 'enum': keys}, {'type': 'null'}]} for sid, keys in reference_choices.items()})
        rule['required'].append('reference_pilots')
        votes = self.round(5, 'style-decision', self.jury(1),
            'Inspect the attached native contact sheets (all frames in playback order). Choose the '
            'style shared by the animal and object. Rank all viable styles; Originality ranks none. '
            'For each style nominate its best pilot as the fixed family reference in reference_pilots. '
            'Originality returns null for each reference nomination and never votes on taste. '
            'Only charter vetoes exclude a style at this step when the frozen rules use drawing notes. '
            'Function flags become readability notes for subsequent hatches under that policy. '
            'Judge identity, gait, all nine rows and sixteen look directions. Preview paths are available to read.',
            {'candidates': viable, 'pilots': pilots, 'decision_rules': self.style_rules()}, rule, images=images)
        chosen = self.tally('style', viable, votes, 1)
        if not chosen:
            raise ValueError('image jury rejected every pilot style')
        style = viable[chosen[0]]
        reference_votes = {seat: {'ranking': [reply['reference_pilots'][chosen[0]]], 'vetoes': [], 'flags': []}
                           for seat, reply in votes.items() if seat != 'originality'}
        selected_pilots = self.tally('reference', reference_choices[chosen[0]], reference_votes, 1)
        if not selected_pilots:
            raise ValueError('image jury supplied no reference pilot votes')
        reference = next(p['contact'] for p in pilots if p['key'] == selected_pilots[0])
        print('4/7 Twenty guardian briefs', flush=True)
        from .lamp_rules import drawing_notes
        notes = drawing_notes(self.run)
        if dry_resume:
            return {'status': 'dry-resume', 'next_step': 4, 'selected': chosen,
                    'reference': reference, 'readability_notes': notes}
        contexts = {seat: {'seed': self.inputs['seeds'][seat], 'style': style,
                          'do_not_resemble': self.inputs['avoid'][seat]} for seat in self.seats}
        if notes:
            for context in contexts.values():
                context['readability_notes'] = notes
        brief_task = ('Draft your own pet: brief 150–300 words, pet_notes 50–80 words of appearance, '
                      'plus one sentence for each of the nine rows. Include appearance, personality, '
                      'physical expression, emotional range, signature behavior, boundaries and every '
                      'do_not_resemble entry verbatim. Preserve the seed within the shared constraints.')
        briefs = self.round(6, 'briefs', list(self.seats), brief_task, contexts, BRIEF, compare=True)
        invalid_briefs = set(self.seats) - briefs.keys()
        print('5/7 Set review and one repair of flagged briefs', flush=True)
        review_rule = schema.obj({'vetoes': schema.array(schema.obj({
            'target': {'type': 'string', 'enum': list(briefs)}, 'quote': S, 'why': S})),
            'flags': schema.array(schema.obj({'target': {'type': 'string', 'enum': list(briefs)}, 'why': S})), 'why': S})
        reviews = self.round(7, 'set-review', self.jury(2),
            'Read the entire set side by side. Only flag off-style, broken boundaries, franchise '
            'look-alikes, real-person likenesses or function defects. No taste rankings.',
            {'style': style, 'candidates': briefs}, review_rule, compare=True) if briefs else {}
        flagged = sorted({v['target'] for r in reviews.values() for v in r['flags'] + r['vetoes']})
        if flagged:
            contexts = {s: {**contexts[s], 'previous': briefs[s], 'review': reviews} for s in flagged}
            repaired = self.round(8, 'brief-repair', flagged, brief_task + ' Repair the flagged problems once.',
                                  contexts, BRIEF, compare=True)
            for seat in flagged:
                briefs.pop(seat)
            briefs.update(repaired)
            invalid_briefs.update(set(flagged) - repaired.keys())
        loop.save(paths.contained(self.run, 'decisions', 'briefs.json'),
                  {'style': style, 'reference': reference, 'briefs': briefs, 'reviews': reviews,
                   'repaired': flagged, 'invalid': sorted(invalid_briefs)})
        print('6/7 Set hatches', flush=True)
        # The jury's validated pilot is already the first reference pet; never replace it mid-set.
        pets = self.hatch_many([dict(key=f'set-{s}', pet=s, style=style, brief=b,
            reference=reference, redo=None) for s, b in briefs.items()])
        print('7/7 Image review and at most one redo per pet', flush=True)
        from .lamp_images import finish
        results = finish(self, pets, briefs, style, reference, invalid_briefs)
        summary = {'status': 'complete', 'model': self.model, 'pets': {s: p['status'] for s, p in results.items()}}
        from .lamp_maker import finish as finish_makers
        maker_results = finish_makers(self, makers_call, results, briefs, style, reference)
        if maker_results is not None:
            summary['makers_call'] = {s: p['status'] for s, p in maker_results.items()}
        loop.save(paths.contained(self.run, 'summary.json'), summary)
        return summary

    def style_rules(self):
        from .lamp_rules import for_style
        return for_style(self.run)['steps']['3']

    def image_review(self, number, stage, candidates, briefs, style, *, seats=None):
        if not candidates:
            return {}
        from .lamp_inputs import for_step
        _, inputs = for_step(self.run, number)
        images = [p['contact'] for p in candidates.values()]
        rule = ballot_schema(list(candidates), ranking=False)
        # Different pending cohorts need distinct job IDs. lamp_images handles
        # completed ballot reuse and excludes pets whose decisions are settled.
        saved = [loop.load(paths.contained(self.run, p.relative_to(self.run)))
                 for p in (self.run / 'jobs' / f'{number:03}').glob(f'{stage}-*.json')]
        if any(job['stage'] == stage and (job['images'] != images or job['reply_schema'] != rule)
               for job in saved):
            stage += '-resume-' + digest(candidates)[:16]
        maker_context = {}
        if stage.startswith('maker-review'):
            maker_context['makers_call'] = loop.load(paths.contained(self.run, 'decisions/makers-call.json'))
        return self.round(number, stage, seats or self.jury(3),
            'Inspect every attached contact sheet, each native cell and all nine rows plus sixteen looks. '
            'Return keep or redo with a concrete reason per pet. Originality marks keep unless it '
            'finds a charter violation; it does not score taste. Judge against the supplied owner '
            'charters and briefs. The maker is a separate session. '
            + ('This is the recorded maker commission outside the Lamp budget. Judge the named repairs '
               'and the whole pet normally; any redo, flag or veto withholds it with no further attempt.'
               if maker_context else 'Each pet gets at most one redo.'),
            {'candidates': candidates, 'briefs': briefs, 'style': style,
             'owner_charters': {g['id']: g for g in inputs['guardians']}, **maker_context},
            rule, images=images)

    @staticmethod
    def redos(reviews):
        result = {}
        for seat, reply in reviews.items():
            reasons = reply['vetoes'] + reply['flags'] + [v for v in reply['verdicts'] if v['verdict'] == 'redo']
            for item in reasons:
                result.setdefault(item['target'], []).append({'seat': seat, **item})
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    run = commands.add_parser('run', help='run or resume the seven pet steps')
    run.add_argument('run_dir', type=Path)
    run.add_argument('--model', required=True)
    run.add_argument('--compare')
    run.add_argument('--effort', default='high')
    run.add_argument('--parallel', type=int, default=4)
    run.add_argument('--image-workers', type=int, default=3)
    run.add_argument('--skill-dir', type=Path, help='installed create-pet skill directory (auto-discovered)')
    run.add_argument('--dry-resume', action='store_true',
                     help='use completed records only and stop before step 4; never call a model')
    listing = commands.add_parser('list-resume',
        help='read-only: list known hatches the next resume would run and why; no model calls')
    listing.add_argument('run_dir', type=Path)
    for command in (run, listing):
        command.add_argument('--makers-call', type=Path,
                             help='explicit maker decisions JSON; frozen separately from Lamp rules')
    replay = commands.add_parser('replay', help='re-pose recorded main-round prompts unchanged')
    replay.add_argument('run_dir', type=Path)
    replay.add_argument('--pieces', default='chapter-6,renumber,front-door')
    replay.add_argument('--models', default='gpt-6-astra,gpt-6.1-sol')
    replay.add_argument('--effort', default='high')
    replay.add_argument('--parallel', type=int, default=4)
    compare = commands.add_parser('compare', help='write comparison.md and comparison.json without model calls')
    compare.add_argument('run_dir', type=Path)
    refresh = commands.add_parser('refresh-inputs', help='refresh guardian names and charters; optionally restart a step')
    refresh.add_argument('run_dir', type=Path)
    refresh.add_argument('--restart-step', type=int, choices=range(1, 8),
                         help='supersede this plan step and all later work (1–7)')
    refresh.add_argument('--reason', default='Refresh guardian names and charters from factory/GUARDIANS.md.')
    retally = commands.add_parser('retally-style', help='treat blocked legacy step-3 flags as drawing notes, without calls')
    retally.add_argument('run_dir', type=Path)
    retally.add_argument('--reason', required=True)
    args = parser.parse_args()
    if hasattr(args, 'parallel') and args.parallel < 1:
        parser.error('--parallel must be positive')
    if hasattr(args, 'image_workers') and not 1 <= args.image_workers <= 3:
        parser.error('--image-workers must be between 1 and 3')
    try:
        if args.command == 'list-resume':
            from .lamp_resume import listing
            # Do not construct Lamp or acquire its writing lock: even .lock, frozen
            # inputs, skill discovery and policy initialization must remain untouched.
            print(json.dumps(listing(args.run_dir, args.makers_call), indent=2, ensure_ascii=False))
            return
        with locked(args.run_dir) as directory:
            if args.command == 'run':
                result = Lamp(directory, args.model, args.compare, args.effort,
                              args.parallel, args.image_workers, args.skill_dir).run_plan(
                                  dry_resume=args.dry_resume, makers_call=args.makers_call)
            elif args.command == 'replay':
                from .lamp_compare import replay_run
                result = replay_run(directory, args.pieces.split(','), args.models.split(','), args.effort, args.parallel)
            elif args.command == 'refresh-inputs':
                from .lamp_inputs import refresh
                result = refresh(directory, args.reason, args.restart_step)
            elif args.command == 'retally-style':
                from .lamp_rules import retally_style
                result = retally_style(directory, args.reason)
            else:
                from .lamp_compare import compare_run
                result = compare_run(directory)
            print(json.dumps(result, ensure_ascii=False))
    except (ValueError, RuntimeError, OSError) as exc:
        parser.exit(1, f'{exc}\n')


if __name__ == '__main__':
    main()
