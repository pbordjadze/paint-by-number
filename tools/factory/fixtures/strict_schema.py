"""Independent strict-output checker for the schemas accepted by our fake API.

Deliberately conservative: bounds and lengths belong to the kit's full validator.
https://developers.openai.com/api/docs/guides/structured-outputs#supported-schemas
"""


def check_strict(rule, path='$'):
    allowed = {'type', 'enum', 'properties', 'required', 'additionalProperties', 'items', 'anyOf'}
    assert isinstance(rule, dict), path
    assert not set(rule) - allowed, f'{path}: unsupported keywords {set(rule) - allowed}'
    if path == '$':
        assert rule.get('type') == 'object' and 'anyOf' not in rule, 'root must be an object'
    types = rule.get('type', [])
    types = types if isinstance(types, list) else [types]
    assert types or 'anyOf' in rule, f'{path}: missing type'
    assert set(types) <= {'object', 'array', 'string', 'null', 'boolean', 'integer', 'number'}, path
    if 'enum' in rule:
        assert isinstance(rule['enum'], list) and rule['enum'], f'{path}: empty enum'
    if 'object' in types:
        assert rule.get('additionalProperties') is False, f'{path}: object must be closed'
        props, required = rule.get('properties'), rule.get('required')
        assert isinstance(props, dict) and isinstance(required, list), path
        assert len(required) == len(set(required)) and set(required) == set(props), f'{path}: all fields required'
        for key, child in props.items():
            check_strict(child, f'{path}.{key}')
    if 'array' in types:
        assert 'items' in rule, f'{path}: missing items'
        check_strict(rule['items'], f'{path}[]')
    if 'anyOf' in rule:
        assert isinstance(rule['anyOf'], list) and rule['anyOf'], path
        for index, child in enumerate(rule['anyOf']):
            check_strict(child, f'{path}.anyOf[{index}]')
