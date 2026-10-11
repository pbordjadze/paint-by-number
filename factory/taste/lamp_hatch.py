"""Local-only pet workers and independently rerun bundled acceptance gates."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from . import loop, paths, schema
from .codex_lamp import digest, frozen

RESULT = schema.obj({'status': {'type': 'string', 'enum': ['complete', 'failed', 'refused']},
                     'reason': schema.STRING, 'image_generations': {'type': 'integer', 'minimum': 0},
                     'repairs': schema.array(schema.STRING)})
REQUIRED = ('validate_atlas.py', 'validate_pet_quality.py', 'make_contact_sheet.py')
LIMIT = 2_000_000


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
    log = work / 'codex.jsonl'
    if log.exists():
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
    if target.exists():
        record = loop.load(target)
        if record['status'] == 'validated':
            package = paths.contained(lamp.run, Path(record['package']).relative_to(lamp.run))
            for name, sha in record['package_hashes'].items():
                if digest(paths.contained(package, name).read_bytes()) != sha:
                    raise ValueError(f'validated package changed: {key}/{name}')
        return record
    record = dict(key=key, pet=pet, model=lamp.model, effort=lamp.effort, status='failed')
    # Never retry a completed or interrupted provider refusal.
    attempts = sorted(paths.contained(base, p.name) for p in base.glob('attempt-*'))
    for attempt in attempts:
        try:
            reply = loop.load(paths.contained(attempt, 'reply.json'), {})
        except ValueError:
            reply = {}
        reply = reply if isinstance(reply, dict) else {}
        if refusal(attempt) or reply.get('status') == 'refused':
            record.update(status='refused', reason=reply.get('reason', 'provider refusal'), work=str(attempt))
            loop.save(target, record)
            return record
    work = attempts[-1] if attempts and (attempts[-1] / 'reply.json').exists() else Path(
        tempfile.mkdtemp(prefix='attempt-', dir=base))
    prompt = f"""Make only a LOCAL candidate using the bundled create-pet/hatch-pet pipeline at {skill}.
Read SKILL.md and its sprite-sheet contract. This user instruction overrides their lifecycle steps:
NEVER upload, create, select, activate or update a service pet; NEVER save to any ChatGPT Library;
never call Pets MCP or Library tools, even preflight. All task-controlled files stay in {work}.
Use only built-in imagegen for art. Copy each generated source used from the tool cache into
this work directory and record its path. One worker owns this pet; generate images sequentially, no
nested image workers. Other pets may already be generating concurrently. Independent read-only
visual reviewers are permitted. No real person beyond Paul and guardian namesakes in the charters.
The set's style and this pet's creature, personality and boundaries are binding. Do not redesign them.
Never reword a prompt to evade a safety refusal. Stop this pet immediately on ANY safety refusal,
return status refused and preserve the provider's reason. A failed pet must not block other pets.
Use the request below and attach the family reference to image jobs. Base first, then idle and
running-right as identity/gait checks, all nine rows, cardinals, row 9 before row 10. Carry the full
style and pet notes, row direction and do-not-resemble list into EVERY image prompt, including the
three v2 look jobs (bundled defaults omit those notes). At most five image references: when needed
combine the COMPLETE family and standard contact sheets in one labeled reference without dropping
any required visual. Keep genuine transparency and no labels in generated art.
Run the bundled preparation, extraction, inspections, assembly, one despill per candidate,
continuity and QA scripts. Do not invent validators or write success reports in place of scripts.
Bound internal visual repairs to two per failing row; after persistent failure return failed.
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
    try:
        reply_path = paths.contained(work, 'reply.json')
        if not reply_path.exists():
            loop.write_atomic(paths.contained(work, 'prompt.txt'), prompt)
            loop.save(paths.contained(work, 'schema.json'), RESULT)
            args = command(lamp.model, lamp.effort, work, work / 'schema.json', reply_path,
                           [reference] if reference else [])
            loop.save(paths.contained(work, 'command.json'), args)
            start = time.monotonic()
            with paths.contained(work, 'codex.jsonl').open('w') as out, paths.contained(work, 'stderr.txt').open('w') as err:
                result = subprocess.run(args, input=prompt, text=True, stdout=out, stderr=err, check=False)
            loop.save(paths.contained(work, 'process.json'),
                      {'returncode': result.returncode, 'seconds': time.monotonic() - start})
            if refusal(work):
                record.update(status='refused', reason='explicit provider refusal; see codex.jsonl')
            elif result.returncode:
                raise ValueError(f'codex exec exited {result.returncode}; see {work}/stderr.txt')
        if record['status'] != 'refused':
            reply = loop.load(reply_path, {})
            errors = schema.validate(reply, RESULT)
            if errors:
                raise ValueError(f'invalid worker reply: {errors}')
            record.update(status=reply['status'], reason=reply['reason'],
                          image_generations=reply['image_generations'], repairs=reply['repairs'])
            if reply['status'] == 'complete':
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
