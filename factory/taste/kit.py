"""File-based design rounds. No model calls; runners consume the jobs this module writes."""
import contextlib
import json
import re
import shutil
from pathlib import Path

from . import loop, schema, settings
from .pieces import color_names, figure, panel_name


def outside_repo(path):
    path = Path(path).resolve()
    if path == loop.REPO or loop.REPO in path.parents:
        raise ValueError('render and scratch output must be outside the repository')
    return path


class Caps:
    def __init__(self, record):
        self.record = record
        self.config = record['settings'].get('caps', {})

    def __call__(self, table):
        failures = []
        for kind, position in (('lead', 0), ('trail', -1)):
            words = [name.split()[position] for name in table.values() if len(name.split()) == 2]
            failures += [(kind, word) for word in sorted(set(words))
                         if kind in self.config and words.count(word) > self.config[kind]]
        if self.config.get('georgian'):
            failures += loop.georgian_caps(table, self.record['glossary'])
        return failures

    def contributes(self, name, kind, word):
        if kind in ('lead', 'trail'):
            return len(name.split()) == 2 and name.split()[0 if kind == 'lead' else -1] == word
        return bool(loop.georgian_caps({0: name}, self.record['glossary']))


def new(piece, run, calibration=None):
    source, run = Path(piece).resolve(), Path(run).resolve()
    config = settings.read(source / 'piece.toml')
    if run.exists() and any(run.iterdir()):
        raise ValueError('new run directory must be empty')
    record = loop.fresh_rules(config['piece']['id'], version=config['rules_version'])
    adapter = config['piece'].get('adapter', 'generic')
    if adapter == 'panel-name':
        slots = [{'slot': '1', 'incumbent': panel_name.INCUMBENT}]
        roster = '\n'.join(f"- {g['name']}: {loop.charter_line(g['charter_text'], 'believes')}"
                           for g in record['guardians'] if not g.get('vetoOnly'))
        brief = panel_name.BRIEF.format(roster=roster)
        base = {}
    elif adapter == 'color-names':
        record['vocabulary'] = color_names.current_vocabulary()
        own_targets = {('robber-girl' if gid == 'nina' else gid): pairs
                       for gid, pairs in color_names.TARGETS.items()}
        slots = color_names.build_slots(record['vocabulary'], own_targets)
        for slot in slots:
            slot['slot'] = str(slot['slot'])
        brief = color_names.BRIEF + '\n\n' + color_names.RULES
        base = {str(v['index']): v['name'] for v in record['vocabulary']}
    elif adapter == 'figure':
        outside_repo(run)
        slots, brief, base = figure.initialize(record, source, run, config)
    else:
        slots = loop.load(source / 'slots.json')
        brief = (source / 'brief.md').read_text()
        base = loop.load(source / 'base.json', {})
    validate_slots(slots, parameter_candidates=adapter == 'figure')
    if not isinstance(base, dict) or not all(isinstance(value, str) for value in base.values()):
        raise ValueError('base.json must map slot keys to names')
    loop.draw(record['guardians'], {'rounds': []}, 'validate', jury_size=config['jury_size'],
              proposers=config['proposers'])
    if config['guarantee'] and len(slots) < config['proposers']:
        raise ValueError('the guarantee needs at least one slot per proposer')
    for plant in config.get('plants', []):
        if plant['slot'] not in [s['slot'] for s in slots]:
            raise ValueError(f"plant references unknown slot {plant['slot']}")
    for slot in slots:
        if 'images' in slot:
            slot['images'] = [str((source / p).resolve()) for p in slot['images']]
    factors = settings.factors(loop.load(calibration, {}) if calibration else {})
    record.update(kitVersion=1, settings=config, brief=brief, initialSlots=slots, base=base,
                  scoring=config['scoring'], vetoPolicy=config['veto_policy'],
                  guarantee=config['guarantee'], calibration=factors.get('jurors', {}),
                  sourceCalibration=factors.get('sources', {}),
                  style=(loop.REPO / 'factory/STYLE.md').read_text()
                  if (loop.REPO / 'factory/STYLE.md').exists() else '')
    loop.save(run / 'rules.json', record)
    loop.save(run / 'ledger.json', {'rounds': []})
    return record


def validate_slots(slots, *, parameter_candidates=False):
    if not isinstance(slots, list) or not slots:
        raise ValueError('slots.json must be a nonempty array')
    ids, keys = [], []
    for slot in slots:
        if not isinstance(slot, dict) or not isinstance(slot.get('slot'), str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]*', slot['slot']):
            raise ValueError('slot IDs must contain letters, digits, hyphens or underscores')
        if not isinstance(slot.get('incumbent'), str) or not slot['incumbent'].strip():
            raise ValueError('slots need an incumbent name')
        if 'candidate_schema' in slot:
            rule = slot['candidate_schema']
            schema.check(rule)
            required = {'patch', 'why'} if parameter_candidates else {'name', 'why'}
            if rule.get('type') != 'object' or not required <= set(rule.get('required', [])):
                raise ValueError('candidate_schema must require ' + ' and '.join(sorted(required)))
        ids.append(slot['slot'])
        keys.append(str(slot.get('index', slot['slot'])))
    if len(set(ids)) != len(ids):
        raise ValueError('duplicate slot IDs')
    if len(set(keys)) != len(keys):
        raise ValueError('duplicate base-set slot keys')


class Run:
    def __init__(self, path, out):
        self.path = Path(path).resolve()
        self.out = outside_repo(out)
        self.record = loop.load(self.path / 'rules.json')
        if not self.record or self.record.get('kitVersion') != 1:
            raise ValueError('use loop new to create a kit run (legacy runs support replay/report)')
        self.config = self.record['settings']
        settings.validate(self.config)
        if self.record['version'] != self.config['rules_version']:
            raise ValueError('run rules version differs from its frozen settings')
        self.gs = loop.seats(self.record)

    def folder(self, n):
        if not 1 <= n <= self.config['rounds']:
            raise ValueError('round is outside the configured range')
        return self.path / 'rounds' / f'{n:03}'

    def frozen(self, path, data):
        old = loop.load(path)
        if old is not None and old != data:
            raise ValueError(f'{path.name} is frozen; use a new run for changed inputs')
        if old is None:
            loop.save(path, data)
        return data

    def prior(self, n):
        if n > 1 and not (self.folder(n - 1) / 'decision.json').exists():
            raise ValueError('decide the previous round first')
        ledger = loop.load(self.path / 'ledger.json', {'rounds': []})
        return {'rounds': [r for r in ledger['rounds'] if r['round'] < n]}

    def draw(self, n):
        folder = self.folder(n)
        prior = self.prior(n)
        prev = loop.load(self.folder(n - 1) / 'draw.json', {}) if n > 1 else {}
        data = loop.draw(self.record['guardians'], prior, f'{self.config["piece"]["id"]}-{n}',
                         jury_size=self.config['jury_size'], proposers=self.config['proposers'],
                         recent=prev.get('jury', []) + prev.get('proposers', []),
                         calibration=self.record['calibration'])
        return self.frozen(folder / 'draw.json', {'round': n, **data})

    def slots(self, n):
        slots = json.loads(json.dumps(self.record['initialSlots']))
        if n > 1:
            results = loop.load(self.folder(n - 1) / 'decision.json')['results']
            for slot in slots:
                winner = next(r for r in results if r['slot'] == slot['slot'])
                slot['incumbent'] = winner['winner']
                previous = next(s for s in loop.load(self.folder(n - 1) / 'slate.json') if s['slot'] == slot['slot'])
                candidate = next(c for c in previous['candidates'] if c['name'] == winner['winner'])
                slot['incumbent_candidate'] = {k: v for k, v in candidate.items() if k not in ('source', 'quality')}
                slot['images'] = candidate.get('images', [])
        return slots

    def job(self, n, role, gid, prompt, reply_schema, images=()):
        job = {'id': f'{role}-{gid}', 'round': n, 'role': role, 'guardian': gid,
               'prompt': prompt, 'reply_schema': reply_schema,
               **{k: self.config['roles'][role][k] for k in ('model', 'effort')},
               'images': list(images), 'attempt': 0}
        return self.frozen(self.path / 'jobs' / f'{n:03}' / f'{job["id"]}.json', job)

    def prompt(self, gid, *, history=True):
        g = self.gs.get(gid)
        return (f"You are {g['name']}.\nYour charter:\n{g['charter_text']}\n" if g else
                'You are an independent professional designer.\n') + self.record['brief'] + \
            '\nApproved style:\n' + self.record['style'] + '\n' + \
            (loop.THREAD if self.config.get('caps', {}).get('georgian') else '') + \
            '\nWhole-set caps: ' + json.dumps(self.config.get('caps', {})) + '\n' + \
            (loop.history(self.path, gid, self.gs) if history else '') + '\n'

    def jobs(self, n):
        from . import renderers
        folder, draw = self.folder(n), self.draw(n)
        slots = self.slots(n)
        slate = loop.load(folder / 'slate.json')
        jobs = []
        is_figure = self.config['piece'].get('adapter') == 'figure'
        if slate is None:
            roles = [('proposer', gid) for gid in draw['proposers']]
            if self.config['roles']['writer']['enabled']:
                roles.append(('writer', 'writer'))
            for role, gid in roles:
                stored = loop.load(self.path / 'jobs' / f'{n:03}' / f'{role}-{gid}.json')
                if stored is not None:
                    jobs.append(stored)
                    continue
                count = self.config['candidates_each'] if role == 'proposer' else 1
                reply_schema = schema.obj({'slots': schema.obj({s['slot']: schema.array(s.get('candidate_schema', schema.CANDIDATE), count)
                                                               for s in slots})})
                if is_figure:
                    for rule in reply_schema['properties']['slots']['properties'].values():
                        rule['minItems'] = 1
                images = [p for s in slots for p in s.get('images', [])]
                if any('hex' in s for s in slots):
                    sheet = self.out / f'{n:03}' / 'swatches.png'
                    renderers.swatches([s for s in slots if 'hex' in s], sheet)
                    images.append(str(sheet))
                prompt = self.prompt(gid) + f'Propose {count} different candidates for EACH slot.\n' + \
                    json.dumps(slots, ensure_ascii=False) + '\nReply with JSON matching the supplied schema.'
                if is_figure:
                    prompt = self.prompt(gid) + figure.proposer_prompt(self.record, count) + \
                        '\nReply with JSON matching the supplied schema.'
                jobs.append(self.job(n, role, gid, prompt, reply_schema, images))
        else:
            for gid in draw['jury']:
                stored = loop.load(self.path / 'jobs' / f'{n:03}' / f'juror-{gid}.json')
                if stored is not None:
                    jobs.append(stored)
                    continue
                ballots, properties, blocks, images = {}, {}, [], []
                for slot in slate:
                    sid = slot['slot']
                    b = loop.ballot([c['name'] for c in slot['candidates']], f'{n}-{gid}-{sid}')
                    ballots[sid] = b
                    candidate_schema = schema.obj({'lives': schema.STRING, 'veto': {'type': ['string', 'null']}})
                    fields = {'candidates': schema.obj({letter: candidate_schema for letter in b})}
                    if not self.gs[gid].get('vetoOnly'):
                        letter_schema = {'type': 'string', 'enum': list(b)}
                        fields.update(ranking=schema.array(letter_schema, len(b), True), note=schema.STRING)
                        if self.config['scoring'] == 'approval':
                            fields['approval'] = schema.array(letter_schema, unique=True)
                    properties[sid] = schema.obj(fields)
                    if is_figure:
                        block, attachments = figure.blind_sheets(b, slot['candidates'],
                                         self.out / f'{n:03}' / 'jury' / gid / sid)
                        blocks.append(f'Slot {sid}:\n' + block)
                        images.extend(attachments)
                        continue
                    blocks.append(f'Slot {sid}:\n' + '\n'.join(
                        f'[{letter}] ' + '\n'.join(self.context(name, slot)) for letter, name in b.items()))
                    for letter, name in b.items():
                        candidate = next(c for c in slot['candidates'] if c['name'] == name)
                        if 'value' in candidate:
                            blocks[-1] += f'\n[{letter}] Parameters: ' + json.dumps(candidate['value'], ensure_ascii=False)
                    text_sheet = self.out / f'{n:03}' / f'{gid}-{sid}-text.png'
                    renderers.text_in_use(blocks[-1].splitlines(), text_sheet)
                    images.append(str(text_sheet))
                    by_name = {c['name']: c for c in slot['candidates']}
                    image_map = {}
                    for letter, name in b.items():
                        attachments = by_name[name].get('images', [])
                        for i, path in enumerate(attachments):
                            image_map[letter if len(attachments) == 1 else f'{letter} · {i + 1}'] = path
                    if image_map:
                        sheet = self.out / f'{n:03}' / f'{gid}-{sid}-images.png'
                        renderers.contacts(image_map, sheet)
                        images.append(str(sheet))
                    if 'hex' in slot:
                        sheet = self.out / f'{n:03}' / f'{gid}-{sid}-swatches.png'
                        renderers.swatches([{'slot': letter, 'hex': slot['hex'], 'incumbent': name}
                                           for letter, name in b.items()], sheet)
                        images.append(str(sheet))
                self.frozen(folder / 'ballots' / f'{gid}.json', ballots)
                prompt = self.prompt(gid, history=False) + '\n'.join(blocks) + '\n' + loop.veto_instruction(self.record)
                prompt += '\nRank every letter exactly once; explain where your idea lives in each candidate.'
                if self.config['scoring'] == 'approval':
                    prompt += '\nAlso list all letters you approve (possibly none).'
                if self.gs[gid].get('vetoOnly'):
                    prompt += '\nYou only veto; do not rank.'
                    prompt += '\n' + loop.glossary_prompt(self.record)
                jobs.append(self.job(n, 'juror', gid, prompt, schema.obj({'slots': schema.obj(properties)}), images))
        return jobs

    def context(self, name, slot):
        adapter = self.config['piece'].get('adapter', 'generic')
        if adapter == 'panel-name':
            return panel_name.in_context(name)
        if adapter == 'color-names':
            return color_names.in_context(name, slot)
        return [text.format(name=name, slot=slot['slot']) for text in
                self.config['piece'].get('context', ['{slot} · {name}'])]

    def accept(self, job):
        n, jid = job['round'], job['id']
        reply = self.path / 'replies' / f'{n:03}' / f'{jid}.json'
        retry = self.path / 'retries' / f'{n:03}' / f'{jid}.json'
        if retry.exists():
            reply = reply.with_name(f'{jid}.retry.json')
        if not reply.exists():
            return None, 'waiting'
        try:
            def invalid_constant(value):
                raise ValueError(f'nonfinite JSON constant {value}')
            data = json.loads(reply.read_text(), parse_constant=invalid_constant)
            errors = schema.validate(data, job['reply_schema'])
        except (ValueError, TypeError) as error:
            data, errors = None, [f'invalid JSON: {error}']
        if errors:
            if retry.exists():
                loop.save(self.folder(n) / 'validation' / f'{jid}.json', {'status': 'rejected', 'errors': errors})
                return None, 'rejected'
            repair = {**job, 'attempt': 1, 'prompt': job['prompt'] + '\nYour reply broke its schema:\n' +
                      '\n'.join(errors) + '\nRepair it once. Your previous reply:\n' + reply.read_text()}
            loop.save(retry, repair)
            return None, 'retry'
        self.frozen(self.folder(n) / 'accepted' / f'{jid}.json', data)
        return data, 'accepted'

    def collect(self, n):
        jobs = self.jobs(n)
        accepted, status = {}, {}
        for job in jobs:
            data, status[job['id']] = self.accept(job)
            if data is not None:
                accepted[job['id']] = data
        if any(state != 'accepted' for state in status.values()):
            return status
        folder = self.folder(n)
        if (folder / 'slate.json').exists():
            return status
        draw = loop.load(folder / 'draw.json')
        slots, rejected = self.slots(n), []
        is_figure = self.config['piece'].get('adapter') == 'figure'
        rendered = {}
        for slot in slots:
            sid = slot['slot']
            slot['owner'] = draw['proposers'][[s['slot'] for s in slots].index(sid) % len(draw['proposers'])]
            candidates = [{**slot.get('incumbent_candidate', {}), 'name': slot['incumbent'], 'source': 'incumbent', 'why': '',
                           'images': slot.get('images', [])}]
            for job in jobs:
                for candidate in accepted[job['id']]['slots'][sid]:
                    candidates.append({**candidate, 'name': '' if is_figure else ' '.join(candidate['name'].split()),
                                       'source': job['guardian'], 'images': candidate.get('images', slot.get('images', []))})
            # Plants are deliberately allowed through craft, including known-bad anchors.
            candidates += [{'name': p['name'], 'source': 'plant', 'quality': p['quality'], 'why': '',
                            'images': slot.get('images', [])}
                           for p in self.config.get('plants', []) if p['slot'] == sid]
            seen, kept = {}, []
            for c in candidates:
                if is_figure:
                    # Every figure, including the incumbent, goes through the same gate.
                    # Cache only within this collection; incomplete renders never get reused.
                    patch_key = json.dumps(c.get('patch', {}), sort_keys=True)
                    if patch_key not in rendered:
                        rendered[patch_key] = figure.craft(c, self.record,
                            self.path / 'inputs/hero.json', self.out / f'{n:03}' / 'candidates')
                    failures, key, artifacts = rendered[patch_key]
                    failures = list(failures)
                    if '\n' in c['why'] or '\r' in c['why']:
                        failures.append('why: expected a one-line reason')
                    c.update(artifacts, name=key)
                else:
                    failures, key = self.craft(c['name'], slot, seen)
                if not is_figure and c['source'] in ('plant', 'incumbent'):
                    failures = []
                if key in seen:
                    failures.append('duplicate in slot')
                if failures:
                    rejected.append({'slot': sid, **c, 'fails': failures})
                else:
                    seen[key] = True
                    kept.append(c)
            slot['candidates'] = kept
            if is_figure and not kept:
                self.frozen(folder / 'rejected.json', rejected)
                raise ValueError('no figure candidate passed the engine checks; see rejected.json')
        self.frozen(folder / 'rejected.json', rejected)
        self.frozen(folder / 'slate.json', slots)
        self.jobs(n)
        return status

    def craft(self, name, slot, taken):
        adapter = self.config['piece'].get('adapter', 'generic')
        if adapter == 'panel-name':
            return panel_name.craft(name, taken)
        if adapter == 'color-names':
            names = {v['name'].lower() for v in self.record['vocabulary']}
            return color_names.craft(name, slot, names), name.casefold()
        return [], name.casefold()

    def decide(self, n):
        folder = self.folder(n)
        slate = loop.load(folder / 'slate.json')
        if slate is None:
            raise ValueError('collect proposals first')
        status = self.collect(n)
        if any(s != 'accepted' for s in status.values()):
            raise ValueError(f'jury replies incomplete: {status}')
        draw = loop.load(folder / 'draw.json')
        results, represented, lines = [], [], {}
        for slot in slate:
            sid = slot['slot']
            names = [c['name'] for c in slot['candidates']]
            ballots = {gid: loop.load(folder / 'ballots' / f'{gid}.json')[sid] for gid in draw['jury']}
            verdicts = {gid: loop.load(folder / 'accepted' / f'juror-{gid}.json')['slots'][sid]
                        for gid in draw['jury']}
            tally = loop.score(names, draw['jury'], ballots, verdicts, self.record, weights=draw['weights'])
            sources = {c['name']: c['source'] for c in slot['candidates']}
            for name in names:
                tally['score'][name] *= self.record['sourceCalibration'].get(sources[name], 1)
            order = sorted(names, key=lambda name: (bool(tally['vetoes'][name]), -tally['score'][name],
                           -tally['firsts'][name], name != slot['incumbent'], name))
            standings = [{'name': name, 'source': sources[name],
                          **{k: tally[k][name] for k in ('score', 'firsts', 'vetoes', 'notes', 'lives')}} for name in order]
            results.append({'slot': sid, 'owner': slot['owner'], 'winner': order[0],
                            'winner_source': sources[order[0]], 'standings': standings,
                            'guaranteed': False, 'ignored_vetoes': tally['ignored'],
                            **loop.favorites(standings)})
        keys = {s['slot']: str(s.get('index', s['slot'])) for s in slate}
        base = dict(self.record['base'])
        # Anchors measure judgment but cannot become production winners. Keep their actual
        # jury scores and vetoes in the report, without inventing a veto for their exclusion.
        selection = []
        for result in results:
            eligible = [st for st in result['standings'] if st['source'] != 'plant']
            if not eligible:
                raise ValueError('no production candidate available')
            selection.append({**result, 'standings': eligible, 'winner': eligible[0]['name'],
                              'winner_source': eligible[0]['source']})
        loop.select(selection, base, keys, Caps(self.record), owners=draw['proposers'],
                    guarantee=self.record['guarantee'])
        for result, selected in zip(results, selection):
            for key in ('winner', 'winner_source', 'guaranteed', 'notes'):
                if key in selected:
                    result[key] = selected[key]
        for result in results:
            winning = next(s for s in result['standings'] if s['name'] == result['winner'])
            if winning['source'] in self.gs:
                represented.append(winning['source'])
            for gid, line in winning['lives'].items():
                if not re.match(r'^\s*absent\b', line, re.I):
                    represented.append(gid)
                    lines.setdefault(gid, []).append(line)
        decision = {'round': n, 'results': results}
        loop.save(folder / 'decision.json', decision)
        loop.record_round(self.path, {'round': n, 'represented': list(dict.fromkeys(represented)),
                                     'lines': lines, 'winners': {r['slot']: r['winner'] for r in results}})
        loop.save(self.path / 'champion.json', decision)
        return decision


@contextlib.contextmanager
def legacy_run(module, path):
    old = module.RUN
    module.RUN = str(path)
    try:
        yield
    finally:
        module.RUN = old


def replay(run, out):
    """Rebuild decisions and ledger in a fresh outside-repo copy, including v1/v2 archives."""
    run, out = Path(run).resolve(), outside_repo(out)
    if run == out or run in out.parents or out in run.parents:
        raise ValueError('replay output must be separate from its input')
    shutil.copytree(run, out)
    for path in (out / 'ledger.json', out / 'champion.json', out / 'decision.json'):
        path.unlink(missing_ok=True)
    for path in out.glob('rounds/*/decision.json'):
        path.unlink()
    record = loop.load(out / 'rules.json')
    with contextlib.redirect_stdout(None):
        if record.get('kitVersion') == 1:
            runner = Run(out, out / 'renders')
            for folder in sorted((out / 'rounds').iterdir()):
                if folder.is_dir() and (folder / 'slate.json').exists():
                    runner.decide(int(folder.name))
        elif record['piece'] == 'panel-name':
            with legacy_run(panel_name, out):
                for folder in sorted((out / 'rounds').iterdir()):
                    panel_name.decide(int(folder.name))
        elif record['piece'] == 'color-names':
            with legacy_run(color_names, out):
                color_names.decide()
        else:
            raise ValueError('unknown legacy piece')
    return out
