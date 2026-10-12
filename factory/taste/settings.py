"""Validated piece.toml settings, frozen in each new run's rules.json."""
import math
import re
import tomllib
from pathlib import Path


def read(path):
    with Path(path).open('rb') as stream:
        data = tomllib.load(stream)
    validate(data)
    return data


def validate(data):
    allowed = {'piece', 'rounds', 'jury_size', 'proposers', 'candidates_each', 'scoring',
               'veto_policy', 'guarantee', 'rules_version', 'caps', 'plants', 'roles'}
    if set(data) - allowed:
        raise ValueError(f'unknown piece settings: {sorted(set(data) - allowed)}')
    piece = data['piece']
    if set(piece) - {'id', 'adapter', 'context'} or not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', piece['id']):
        raise ValueError('piece needs a lowercase, hyphenated id')
    if piece.get('adapter', 'generic') not in ('generic', 'panel-name', 'color-names', 'figure'):
        raise ValueError('unknown piece adapter')
    for field in ('rounds', 'jury_size', 'proposers', 'candidates_each'):
        if type(data[field]) is not int or data[field] < 1:
            raise ValueError(f'{field} must be a positive integer')
    if data['scoring'] not in ('borda', 'approval', 'copeland'):
        raise ValueError('unknown scoring method')
    if data['veto_policy'] not in ('quote', 'free', 'off'):
        raise ValueError('unknown veto policy')
    if type(data['guarantee']) is not bool or type(data['rules_version']) is not int or data['rules_version'] not in (1, 2):
        raise ValueError('invalid guarantee or rules version')
    if 'context' in piece and (not isinstance(piece['context'], list) or not piece['context'] or
                               not all(isinstance(text, str) for text in piece['context'])):
        raise ValueError('piece.context must be a nonempty array of strings')
    # Omitted caps are off; validation must not add defaults to frozen settings.
    caps = data.get('caps', {})
    if set(caps) - {'georgian', 'lead', 'trail'}:
        raise ValueError('unknown caps')
    if 'georgian' in caps and type(caps['georgian']) is not bool:
        raise ValueError('georgian cap must be boolean')
    for field in ('lead', 'trail'):
        if field in caps and (type(caps[field]) is not int or caps[field] < 0):
            raise ValueError(f'{field} cap must be a nonnegative integer')
    for role in ('proposer', 'juror', 'writer'):
        config = data['roles'][role]
        if set(config) != {'model', 'effort', 'enabled'} or not all(
                isinstance(config[k], str) and config[k].strip() for k in ('model', 'effort')):
            raise ValueError(f'{role} needs model, effort and enabled')
        if type(config['enabled']) is not bool:
            raise ValueError(f'{role}.enabled must be boolean')
    if set(data['roles']) != {'proposer', 'juror', 'writer'}:
        raise ValueError('unknown agent role')
    if not all(data['roles'][r]['enabled'] for r in ('proposer', 'juror')):
        raise ValueError('proposer and juror roles must be enabled')
    for plant in data.get('plants', []):
        if set(plant) != {'slot', 'name', 'quality'} or plant['quality'] not in ('good', 'bad'):
            raise ValueError('plants need slot, name and good/bad quality')
        if not isinstance(plant['slot'], str) or not isinstance(plant['name'], str) or not plant['name'].strip():
            raise ValueError('plant slot and name must be nonempty strings')


def factors(data):
    """Reject NaN, negatives and misspelled factor sections before they shape a draw."""
    if set(data) - {'jurors', 'sources', 'evidence'}:
        raise ValueError('calibration needs jurors and sources')
    for section in ('jurors', 'sources'):
        for value in data.get(section, {}).values():
            if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
                raise ValueError('calibration factors must be finite and nonnegative')
    return data
