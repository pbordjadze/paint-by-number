"""Local-only pet workers and independently rerun bundled acceptance gates."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from . import loop, paths, schema
from .codex_lamp import CONTRACT, MOTION_POLICY, UNATTENDED, digest, frozen

RESULT = schema.obj({'status': {'type': 'string', 'enum': ['complete', 'failed', 'refused']},
                     'reason': schema.STRING, 'image_generations': {'type': 'integer', 'minimum': 0},
                     'repairs': schema.array(schema.STRING),
                     'contract_overrides': schema.array(schema.obj({
                         'source': schema.STRING, 'original': schema.STRING,
                         'replacement': schema.STRING, 'reason': schema.STRING})),
                     'decisions': schema.array(schema.STRING)})
REQUIRED = ('validate_atlas.py', 'validate_pet_quality.py', 'make_contact_sheet.py')
LIMIT = 2_000_000
WORKER_POLICY = 3


def find_skill(explicit=None):
    if explicit:
        candidates = [Path(explicit).expanduser().resolve()]
    else:
        candidates = sorted(Path('/root/.codex/plugins/cache').glob('*/work-pets/*/skills/create-pet'))
        candidates += sorted(Path('/root/.codex/skills').glob('**/hatch-pet'))
        candidates.reverse()
    for candidate in candidates:
        if (candidate / 'SKILL.md').is_file() and all((candidate / 'scripts' / s).is_file() for s in REQUIRED):
            return candidate
    raise ValueError('installed v2 create-pet/hatch-pet skill with both validators is required; use --skill-dir')


def skill_hashes(skill):
    # Freeze the whole implementation used by the worker, not just the two entry points.
    return {str(p.relative_to(skill)): digest(p.read_bytes()) for p in sorted(skill.rglob('*'))
            if p.is_file() and '__pycache__' not in p.parts}


def command(model, effort, work, schema_path, reply_path, images):
    args = ['codex', 'exec', '--json', '--ephemeral', '-s', 'workspace-write',
            '--skip-git-repo-check', '--cd', str(work), '--model', model,
            '--config', 'model_reasoning_effort=' + json.dumps(effort),
            '--config', 'approval_policy="never"',
            '--config', 'sandbox_workspace_write.writable_roots=["/root/factory-out"]',
            '--config', 'sandbox_workspace_write.exclude_tmpdir_env_var=true',
            '--config', 'sandbox_workspace_write.exclude_slash_tmp=true',
            '--output-schema', str(schema_path), '--output-last-message', str(reply_path)]
    for path in images:
        args += ['--image', path]
    return args + ['-']


def refusal(work):
    """Only explicit provider signals; a prompt quoting the prohibition is not a refusal."""
    for log in work.glob('codex*.jsonl'):
        for line in log.read_text().splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            def explicit(value):
                if isinstance(value, dict):
                    if value.get('type') in ('refusal', 'content_filter', 'safety_refusal') or value.get('refusal'):
                        return True
                    if value.get('code') in ('content_policy_violation', 'safety_violation', 'moderation_blocked'):
                        return True
                    return any(explicit(v) for v in value.values())
                return isinstance(value, list) and any(explicit(v) for v in value)
            if explicit(event):
                return True
    return False


def worker_reply(lamp, work, prompt, reference):
    """Repair only a worker's JSON report once; keep its artwork and both replies."""
    errors, raw_reply = [], ''
    for attempt in (0, 1):
        suffix = '.retry' if attempt else ''
        reply_path = paths.contained(work, f'reply{suffix}.json')
        if not reply_path.exists():
            current = schema.repair_prompt(prompt, errors, raw_reply) if attempt else prompt
            if attempt:
                current += '\nOnly correct the JSON report using existing evidence. Do not generate or change artwork.'
            loop.write_atomic(paths.contained(work, f'prompt{suffix}.txt'), current)
            loop.save(paths.contained(work, 'schema.json'), schema.transport(RESULT))
            args = command(lamp.model, lamp.effort, work, work / 'schema.json', reply_path,
                           [reference] if reference else [])
            loop.save(paths.contained(work, f'command{suffix}.json'), args)
            start = time.monotonic()
            with paths.contained(work, f'codex{suffix}.jsonl').open('w') as out, paths.contained(work, f'stderr{suffix}.txt').open('w') as err:
                result = subprocess.run(args, input=current, text=True, stdout=out, stderr=err, check=False)
            loop.save(paths.contained(work, f'process{suffix}.json'),
                      {'returncode': result.returncode, 'seconds': time.monotonic() - start})
            if refusal(work):
                return {'status': 'refused', 'reason': 'explicit provider refusal; see codex logs'}, []
            if result.returncode:
                raise ValueError(f'codex exec exited {result.returncode}; see {work}/stderr{suffix}.txt')
        raw_reply = reply_path.read_text()
        reply = None
        try:
            reply = loop.load(reply_path)
            # A refusal never authorizes another call, even with a malformed report.
            if isinstance(reply, dict) and reply.get('status') == 'refused':
                return reply, []
            errors = schema.validate(reply, RESULT)
        except ValueError as exc:
            errors = [str(exc)]
        if not errors:
            return reply, []
        loop.save(paths.contained(work, f'rejection{suffix}.json'), {'errors': errors, 'raw_reply': raw_reply})
    return reply, errors


def motion_guidance_failure(record):
    """Recognize the old worker's specific extra gate, not general quality failures."""
    return bool(re.fullmatch(
        r'(?:Stopped after )?jumping exhausted both permitted repairs: its extracted peak remains '
        r'\d+ pixels above baseline, exceeding the preserved \d+[–-]\d+-pixel lift\.?'
        r'(?: No final v2 WebP was produced\. All sources, prompts, generation logs, authentic '
        r'standard-frame inspection, contact sheet and nine diagnostic GIFs remain local\.)?',
        record.get('reason', '').strip(), re.I))


def retryable_pilot(record):
    """One migration for pre-generation blockers or the old style-motion gate."""
    if not record['key'].startswith('pilot-') or record['status'] != 'failed':
        return False
    policy = record.get('worker_policy', 1)
    if policy < 3 and motion_guidance_failure(record):
        return True
    reason = record.get('reason', '').lower()
    return (record.get('image_generations') == 0 and policy < 2
            and (('family reference' in reason and ('null' in reason or 'missing' in reason))
                 or ('v2' in reason and ('conflict' in reason or 'exceed' in reason))
                 or ('clarification' in reason and 'unanswered' in reason)))


def hatch(lamp, key, pet, style, brief, reference, redo):
    paths.slug(key)
    base = paths.contained(lamp.run, 'hatches', key)
    base.mkdir(parents=True, exist_ok=True)
    skill = Path(lamp.config['skill_dir'])
    frozen(paths.contained(lamp.run, 'skill.json'), skill_hashes(skill))
    request = dict(key=key, pet=pet, model=lamp.model, effort=lamp.effort, style=style,
                   brief=brief, reference=reference,
                   reference_sha256=digest(Path(reference).read_bytes()) if reference else None, redo=redo)
    frozen(paths.contained(base, 'request.json'), request)
    target = paths.contained(base, 'result.json')
    previous = None
    if target.exists():
        record = loop.load(target)
        if record['status'] == 'validated':
            package = paths.contained(lamp.run, Path(record['package']).relative_to(lamp.run))
            for name, sha in record['package_hashes'].items():
                if digest(paths.contained(package, name).read_bytes()) != sha:
                    raise ValueError(f'validated package changed: {key}/{name}')
        if not retryable_pilot(record):
            return record
        previous = record
    record = dict(key=key, pet=pet, model=lamp.model, effort=lamp.effort, status='failed',
                  worker_policy=WORKER_POLICY, motion_policy=MOTION_POLICY)
    if previous:
        old_work = paths.contained(base, Path(previous['work']).relative_to(base))
        frozen(paths.contained(old_work, 'result.json'), previous)
        record['resumed_from'] = str(old_work / 'result.json')
    # Never retry a completed or interrupted provider refusal.
    attempts = sorted(paths.contained(base, p.name) for p in base.glob('attempt-*'))
    for attempt in attempts:
        replies = []
        for name in ('reply.json', 'reply.retry.json'):
            try:
                reply = loop.load(paths.contained(attempt, name), {})
            except ValueError:
                reply = {}
            if isinstance(reply, dict) and reply.get('status') == 'refused':
                replies.append(reply)
        if refusal(attempt) or replies:
            record.update(status='refused', reason=replies[0].get('reason', 'provider refusal') if replies else 'provider refusal',
                          work=str(attempt))
            loop.save(target, record)
            return record
    active = paths.contained(base, 'active-attempt.json')
    if previous and active.exists() and loop.load(active)['directory'] == old_work.name:
        active.unlink()
    if active.exists():
        work = paths.contained(base, loop.load(active)['directory'])
    else:
        work = attempts[-1] if not previous and attempts and (attempts[-1] / 'reply.json').exists() else Path(
            tempfile.mkdtemp(prefix='attempt-', dir=base))
        frozen(active, {'directory': work.name})
    reference_policy = (
        'No family reference exists for this pilot. reference=null is intentional, not a blocker. '
        'Generate the canonical base from the seed and style without a family image; use that base '
        'and this pilot\'s approved images to ground all subsequent jobs.' if reference is None else
        'The supplied family reference is the jury\'s chosen pilot. Attach it to every image job '
        'for shared style, preserving this pet\'s own creature and identity. Keep this same reference '
        'through all set hatches and redos.')
    prompt = f"""Make only a LOCAL candidate using the bundled create-pet/hatch-pet pipeline at {skill}.
Read SKILL.md and its sprite-sheet contract. This user instruction overrides their lifecycle steps:
NEVER upload, create, select, activate or update a service pet; NEVER save to any ChatGPT Library;
never call Pets MCP or Library tools, even preflight. All task-controlled files stay in {work}.
Use only built-in imagegen for art. Copy each generated source used from the tool cache into
this work directory and record its path. One worker owns this pet; generate images sequentially, no
nested image workers. Other pets may already be generating concurrently. Independent read-only
visual reviewers are permitted. No real person beyond Paul and guardian namesakes in the charters.
{UNATTENDED}
{CONTRACT}
{MOTION_POLICY}
Keep the intended action, character and rhythm. Never enforce a style sheet's numeric motion
target as a separate acceptance threshold. Record target versus observed movement and why it
still expresses the intent in decisions; run all bundled validators on the finished atlas.
The contract overrides ANY frame count, row count, resolution or "look" number/meaning in a style
sheet or brief. Remap motion beats to the required frames and interpret looks as directions.
Keep the sheet's taste: preset, style_notes, palette, line, framing and boundaries, and this pet's
creature and personality. Preserve palette colors and material treatment as one consistent style;
do not generate the sheet's proposed palette variants or paint treatments as extra looks.
Before generating, record EVERY technical override in contract_overrides: source field (such as
style.rows.idle), exact original text, contract-compliant replacement and reason. Include frame
ranges/timing remaps and look reinterpretations wherever specified. Record other autonomous
choices in decisions. Save these in local logs and include both arrays in the final JSON reply;
the driver copies them into the pet's provenance. Empty arrays mean no overrides/choices needed.
Resolve overrides before preparing image jobs. Send contract-compliant technical instructions
with the unchanged taste to imagegen; keep superseded technical claims only in provenance/logs.
Never reword a prompt to evade a safety refusal. Stop this pet immediately on ANY safety refusal,
return status refused and preserve the provider's reason. A failed pet must not block other pets.
{reference_policy}
Use the request below. Base first, then idle and
running-right as identity/gait checks, all nine rows, cardinals, row 9 before row 10. Carry the full
style taste and pet notes, corrected row direction and do-not-resemble list into EVERY image prompt, including the
three v2 look jobs (bundled defaults omit those notes). At most five image references: when needed
combine the COMPLETE family and standard contact sheets in one labeled reference without dropping
any required visual. Keep genuine transparency and no labels in generated art.
Run the bundled preparation, extraction, inspections, assembly, one despill per candidate,
continuity and QA scripts. Do not invent validators or write success reports in place of scripts.
Bound repairs to two per row that fails the skill's checks; after persistent failure return failed.
Do not reject or repair a row solely to hit a style sheet's motion numbers.
A jury-requested redo is ONE attempt, with the existing brief and style preserved. Repair only
its identified defects. No further whole-pet redo is authorized.
Output final/spritesheet.webp (v2 1536 × 2288) and these authentic reports:
qa/chroma-despill-extended.json, qa/review.json, qa/direction-semantics.json,
qa/look-continuity.json. Render contact sheets and all required GIF/MP4 motion previews in previews/.
The caller independently runs validate_atlas.py --require-v2 and validate_pet_quality.py on the
EXACT final WebP. Keep the WebP small enough that WebP + compressed contact + metadata fit 2 MB.
Record actual image-generation count and technical repairs in the final JSON reply, plus
prompts, inputs, references, generation counts and redos in local logs. Never fabricate a count.
Request:
{json.dumps(request, indent=2, ensure_ascii=False)}
"""
    if previous:
        prompt += (f'\nPrevious attempt evidence: {old_work}. Preserve those files. Reuse suitable '
                   'source art in this new attempt and finish the required pipeline. Previous failure: '
                   + previous['reason'] + '\n')
    try:
        reply, errors = worker_reply(lamp, work, prompt, reference)
        if errors:
            record.update(status='invalid', reason='invalid worker reply after one repair', errors=errors)
        elif reply['status'] == 'refused':
            record.update(status='refused', reason=reply.get('reason', 'provider refusal'))
        else:
            record.update(status=reply['status'], reason=reply['reason'],
                          image_generations=reply['image_generations'], repairs=reply['repairs'],
                          contract_overrides=reply['contract_overrides'], decisions=reply['decisions'])
            if reply['status'] == 'complete' or (reply['status'] == 'failed' and motion_guidance_failure(reply)
                                                and paths.contained(work, 'final/spritesheet.webp').is_file()):
                record.update(validate(work, skill))
                metadata = {'id': pet, 'displayName': brief.get('display_name', pet),
                            'description': brief.get('description', brief.get('seed', pet)),
                            'spritesheetPath': 'spritesheet.webp'}
                package = paths.contained(work, 'package')
                package.mkdir(exist_ok=True)
                shutil.copyfile(paths.contained(work, 'final/spritesheet.webp'), paths.contained(package, 'spritesheet.webp'))
                from PIL import Image
                with Image.open(paths.contained(work, 'gate/contact.png')) as contact:
                    contact.convert('RGB').save(paths.contained(package, 'contact-sheet.webp'), quality=75, method=6)
                loop.save(paths.contained(package, 'pet.json'), metadata)
                provenance = {**request, 'worker_reply': reply, 'work': str(work),
                              'worker_policy': WORKER_POLICY, 'contract': CONTRACT,
                              'motion_policy': MOTION_POLICY,
                              'motion_guidance_difference': reply['reason'] if motion_guidance_failure(reply)
                                  else previous['reason'] if previous and motion_guidance_failure(previous) else None,
                              'contract_overrides': reply['contract_overrides'], 'decisions': reply['decisions'],
                              'resumed_from': record.get('resumed_from'),
                              'atlas_sha256': record['atlas_sha256'], 'validators': record['validators'],
                              'image_generations_source': 'worker report; raw events and generation logs retained',
                              'redo_count': int(redo is not None), 'local_only': True}
                loop.save(paths.contained(package, 'provenance.json'), provenance)
                size = sum(p.stat().st_size for p in package.iterdir())
                if size > LIMIT:
                    raise ValueError(f'package is {size} bytes, exceeds {LIMIT}; no files published')
                record.update(status='validated', package=str(package), bytes=size,
                    contact=str(package / 'contact-sheet.webp'), previews=str(work / 'previews'),
                    package_hashes={p.name: digest(p.read_bytes()) for p in sorted(package.iterdir())})
    except (ValueError, OSError, RuntimeError) as exc:
        record.update(status='failed', reason=str(exc))
    record['work'] = str(work)
    loop.save(target, record)
    return record


def validate(work, skill):
    atlas = paths.contained(work, 'final/spritesheet.webp')
    if not atlas.is_file():
        raise ValueError('missing final/spritesheet.webp')
    reports = {name: paths.contained(work, name) for name in
               ('qa/chroma-despill-extended.json', 'qa/review.json',
                'qa/direction-semantics.json', 'qa/look-continuity.json')}
    if any(not p.is_file() for p in reports.values()):
        raise ValueError('missing required quality evidence')
    gate = paths.contained(work, 'gate')
    gate.mkdir(exist_ok=True)
    chroma = loop.load(reports['qa/chroma-despill-extended.json']).get('chroma_key')
    if not isinstance(chroma, str):
        raise ValueError('chroma cleanup report must record its actual chroma_key')
    cmds = [
        ['validate_atlas.py', str(atlas), '--require-v2', '--chroma-key', chroma,
         '--json-out', str(gate / 'atlas.json')],
        ['validate_pet_quality.py', str(atlas), '--atlas-validation', str(gate / 'atlas.json'),
         '--chroma-report', str(reports['qa/chroma-despill-extended.json']),
         '--frame-review', str(reports['qa/review.json']),
         '--direction-semantics', str(reports['qa/direction-semantics.json']),
         '--continuity', str(reports['qa/look-continuity.json']), '--json-out', str(gate / 'quality.json')],
        ['make_contact_sheet.py', str(atlas), '--output', str(gate / 'contact.png'), '--scale', '1']]
    for i, cmd in enumerate(cmds):
        args = [sys.executable, str(skill / 'scripts' / cmd[0]), *cmd[1:]]
        loop.save(paths.contained(gate, f'{i}-command.json'), args)
        with paths.contained(gate, f'{i}.log').open('w') as log:
            result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, check=False)
        if result.returncode:
            raise ValueError(f'{cmd[0]} failed; see {gate}/{i}.log')
    sha = digest(atlas.read_bytes())
    for name in ('atlas', 'quality'):
        report = loop.load(paths.contained(gate, name + '.json'))
        if report.get('ok') is not True or report.get('sha256') != sha:
            raise ValueError(f'{name} did not validate exact final bytes')
    return {'atlas_sha256': sha, 'validators': {'atlas': str(gate / 'atlas.json'), 'quality': str(gate / 'quality.json')}}


def publish(lamp, pet, brief, style):
    """Only the parent can write the repository; workers have no writable repository root."""
    del brief, style  # Both are already frozen in the validated package's provenance.
    destination = paths.contained(loop.REPO, 'factory', 'pets', pet['pet'])
    source = Path(pet['package'])
    names = pet['package_hashes']
    if sum(paths.contained(source, n).stat().st_size for n in names) > LIMIT:
        raise ValueError('pet exceeds package size limit')
    destination.mkdir(parents=True, exist_ok=True)
    for name, sha in names.items():
        data = paths.contained(source, name).read_bytes()
        if digest(data) != sha:
            raise ValueError('validated bytes changed before publication')
        target = paths.contained(destination, name)
        # Resume can safely finish a partial copy, but cannot overwrite another run's art.
        if target.exists():
            if target.read_bytes() != data:
                raise ValueError(f'existing pet differs; refusing overwrite: {target}')
            continue
        fd, temp = tempfile.mkstemp(prefix='.pet-', dir=destination)
        try:
            with os.fdopen(fd, 'wb') as handle:
                handle.write(data)
            os.replace(temp, target)
        finally:
            Path(temp).unlink(missing_ok=True)
