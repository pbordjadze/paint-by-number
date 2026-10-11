"""FigureSpec patches, the engine's craft gate, and full-size blind review sheets.

The v1 field contract mirrors factory/SPEC.md and FigureSpec's strict decoder. Freeze
it and the baseline in rules.json so later edits cannot change an existing run.
Rendering uses tools/factory/render.py; FIGURES_BIN selects the host executable.
"""
import copy
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path

from .. import loop, renderers, schema


RANGES = {
    'figure': {
        'headSize': (.10, .26), 'headAspect': (.6, 1.2), 'neck': (0, .08),
        'torso': (.18, .42), 'hunch': (0, .6), 'shoulderWidth': (0, .25),
        'hipWidth': (0, .2), 'upperArm': (.10, .30), 'forearm': (.10, .30),
        'thigh': (.12, .32), 'shin': (.12, .32), 'foot': (0, .10),
        'knobs': (0, 1), 'headwearSize': (.6, 1.6), 'knot': (0, 1), 'skirt': (0, .5)},
    'ink': {'width': (.01, .08), 'taper': (0, 1), 'pressure': (0, 1),
            'wobble': (0, .03), 'wobbleLength': (.03, .5), 'boilFps': (0, 24),
            'overshoot': (0, .05)},
    'motion': {'fps': (12, 60), 'step': (.08, .4), 'cadence': (.8, 3.5),
               'bounce': (0, .08), 'sway': (0, .04), 'lean': (-5, 20),
               'armSwing': (0, 60), 'footLift': (.01, .15), 'ease': (0, 1),
               'turnRate': (90, 1080), 'anticipation': (0, .5),
               'followThrough': (0, .4), 'settle': (.1, 1)},
    'magic': {'size': (.01, .1), 'trail': (0, 20), 'burst': (0, 80),
              'life': (.3, 3), 'drift': (0, 1), 'spread': (0, 2),
              'twinkle': (0, 8), 'glow': (0, 1)},
    'view': {'depth': (0, 1), 'heightScale': (.7, 1.2)},
    'card': {'size': (11, 22), 'fade': (.1, .8), 'holdBase': (.3, 1.5),
             'perWord': (.12, .35)}}
CHOICES = {
    'figure.hands': ['none', 'dot', 'mitten'],
    'figure.headwear': ['none', 'kerchief', 'hood'],
    'magic.shape': ['sparkle', 'dot', 'leaf', 'star'],
    'card.position': ['top', 'bottom', 'topLeading', 'bottomLeading'],
    'card.backdrop': ['none', 'paper'], 'motion.headingSteps': [0, 8, 16]}
SHEETS = ('contact', 'atsize-light', 'atsize-dark', 'silhouette')
CHECKS = {'footSlide', 'kneeReverse', 'elbowReverse', 'ikClamps', 'inkWidth',
          'figureHeight', 'inBounds', 'particles', 'cardHold', 'cardSize',
          'cardOnScreen', 'inkContrast'}


def is_color(value):
    return isinstance(value, str) and bool(re.fullmatch(
        r'#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})', value))


def contract():
    fields = {'version': {'kind': 'integer', 'choices': [1]}}
    for group, ranges in RANGES.items():
        for key, bounds in ranges.items():
            fields[f'{group}.{key}'] = {'kind': 'integer' if f'{group}.{key}' in
                                       ('motion.fps', 'magic.burst') else 'number',
                                       'range': list(bounds)}
    fields.update({key: {'kind': 'integer' if key == 'motion.headingSteps' else 'string',
                         'choices': values} for key, values in CHOICES.items()})
    fields.update({'motion.onTwos': {'kind': 'boolean'}, 'ink.color': {'kind': 'color'},
                   'figure.accent': {'kind': 'color', 'nullable': True},
                   'magic.colors': {'kind': 'colors', 'range': [1, 4]}})
    return fields


def problems(patch, fields):
    failures = []
    if not isinstance(patch, dict):
        return ['patch: expected an object']
    groups = {key.split('.')[0] for key in fields if '.' in key}
    values = {}
    for group, value in patch.items():
        if group == 'version':
            values[group] = value
        elif group not in groups:
            failures.append(f'{group}: unknown FigureSpec field')
        elif not isinstance(value, dict):
            failures.append(f'{group}: expected an object')
        else:
            values.update({f'{group}.{key}': item for key, item in value.items()})
    for key, value in values.items():
        rule = fields.get(key)
        if rule is None:
            failures.append(f'{key}: unknown FigureSpec field')
            continue
        if value is None and rule.get('nullable'):
            continue
        kind = rule['kind']
        valid = {'integer': type(value) is int,
                 'number': type(value) is int or (type(value) is float and math.isfinite(value)),
                 'boolean': type(value) is bool, 'string': isinstance(value, str),
                 'color': is_color(value),
                 'colors': isinstance(value, list)}[kind]
        if not valid:
            failures.append(f'{key}: expected {kind}')
        elif 'choices' in rule and value not in rule['choices']:
            failures.append(f'{key}: expected one of {rule["choices"]}')
        elif kind == 'colors':
            if not rule['range'][0] <= len(value) <= rule['range'][1]:
                failures.append(f'{key}: expected 1–4 hex colors')
            for i, color in enumerate(value):
                if not is_color(color):
                    failures.append(f'{key}[{i}]: expected hex color')
        elif 'range' in rule and not rule['range'][0] <= value <= rule['range'][1]:
            failures.append(f'{key}: expected {rule["range"][0]}…{rule["range"][1]}')
    return failures


def apply(baseline, patch, fields):
    failures = problems(patch, fields)
    if failures:
        raise ValueError('; '.join(failures))
    spec = copy.deepcopy(baseline)
    for group, value in patch.items():
        if group == 'version':
            spec[group] = value
        else:
            spec[group].update(value)
    return spec


def identity(spec):
    return 'spec-' + hashlib.sha256(json.dumps(spec, sort_keys=True,
                         separators=(',', ':')).encode()).hexdigest()


def initialize(record, source, run, config):
    if config['rules_version'] != 2 or config['veto_policy'] != 'quote':
        raise ValueError('figure requires rules v2 and quoted vetoes')
    if config['candidates_each'] > 3 or config.get('plants') or config['roles']['writer']['enabled']:
        raise ValueError('figure requires at most three patches, no plants and no writer')
    fields = contract()
    baseline = loop.load(loop.REPO / 'factory/specs/baseline.json')
    apply(baseline, baseline, fields)
    record['figure'] = {'baseline': baseline, 'fields': fields}
    # Keep the hero and its background with the run, independent of later repo edits.
    inputs = run / 'inputs'
    inputs.mkdir(parents=True, exist_ok=True)
    scene_file = loop.REPO / 'factory/scenes/hero.json'
    scene = loop.load(scene_file)
    if scene.get('background'):
        shutil.copyfile(scene_file.parent / scene['background'], inputs / 'hero-background.png')
        scene['background'] = 'hero-background.png'
    loop.save(inputs / 'hero.json', scene)
    candidate_schema = schema.obj({'patch': {'type': 'object'}, 'why': schema.STRING})
    slots = [{'slot': '1', 'incumbent': identity(baseline),
              'incumbent_candidate': {'patch': {}}, 'candidate_schema': candidate_schema}]
    return slots, (source / 'brief.md').read_text(), {}


def proposer_prompt(record, count):
    return (f'Propose one to {count} different patches for slot 1, with a one-line why each. '
            'Use nested group objects, for example {"figure":{"headSize":0.18}}. '
            'Every patch applies to this baseline, including in later rounds.\nBaseline:\n' +
            json.dumps(record['figure']['baseline'], sort_keys=True) + '\nField contract:\n' +
            json.dumps(record['figure']['fields'], sort_keys=True))


def render(spec, scene, out):
    out.mkdir(parents=True, exist_ok=True)
    loop.save(out / 'spec.json', spec)
    with (out / 'render.log').open('w') as log:
        result = subprocess.run([sys.executable, str(loop.REPO / 'tools/factory/render.py'),
                                 str(out / 'spec.json'), str(scene), str(out)],
                                stdout=log, stderr=subprocess.STDOUT)
    return result.returncode


def craft(candidate, record, scene, out):
    """Return failures, identity and artifacts; a failed render can never supply jury images."""
    fields, baseline = record['figure']['fields'], record['figure']['baseline']
    patch = candidate.get('patch', {})
    failures = problems(patch, fields)
    if failures:
        return failures, identity(patch), {}
    spec = apply(baseline, patch, fields)
    name = identity(spec)
    folder = out / name
    code = render(spec, scene, folder)
    try:
        checks = loop.load(folder / 'checks.json')
        if not isinstance(checks, list) or not checks or any(not isinstance(c, dict) for c in checks):
            raise ValueError('expected a nonempty check array')
        names = [c.get('name') for c in checks]
        if not all(isinstance(n, str) for n in names) or len(set(names)) != len(names):
            raise ValueError('expected unique check names')
        failures += [f'checks.json: missing {n}' for n in sorted(CHECKS - set(names))]
        failures += [f'checks.json: {c["name"]} failed' for c in checks if c.get('pass') is not True]
    except (ValueError, OSError, TypeError) as error:
        failures.append(f'checks.json: {error}')
    if code and not failures:
        failures.append(f'render.py: exit {code}; see {folder / "render.log"}')
    images = [str(folder / 'sheets' / f'{sheet}.png') for sheet in SHEETS]
    if not failures:
        failures += [f'render.py: missing {Path(p).name}' for p in images if not Path(p).is_file()]
    return failures, name, {'images': images if not failures else [],
                            'checks': str(folder / 'checks.json')}


def blind_sheets(ballot, candidates, out):
    """Keep native pixels; add only a letter header and strip PNG metadata/source names."""
    from PIL import Image, ImageDraw
    by_name = {c['name']: c for c in candidates}
    images, lines = [], []
    for letter, name in ballot.items():
        lines.append(f'[{letter}] contact, at-size light, at-size dark, silhouette')
        for kind, path in zip(SHEETS, by_name[name]['images']):
            with Image.open(path) as original:
                sheet = Image.new('RGB', (original.width, original.height + 48), '#f4f1ea')
                sheet.paste(original.convert('RGB'), (0, 48))
            ImageDraw.Draw(sheet).text((12, 8), f'{letter} · {kind}',
                                       font=renderers.font(24), fill='#2a2622')
            images.append(str(renderers.write(sheet, out / f'{letter}-{kind}.png')))
    return '\n'.join(lines), images
