"""JSON Schema constructors and validator for the kit's deliberately small schema subset.

Only type, properties, required, additionalProperties, items, min/maxItems, uniqueItems,
minLength, minimum/maximum, enum and oneOf are supported. Unknown keywords fail closed.
"""
import math


def obj(properties):
    return {'type': 'object', 'properties': properties, 'required': list(properties),
            'additionalProperties': False}


def array(items, count=None, unique=False):
    result = {'type': 'array', 'items': items}
    if count is not None:
        result.update(minItems=count, maxItems=count)
    if unique:
        result['uniqueItems'] = True
    return result


STRING = {'type': 'string', 'minLength': 1}
CANDIDATE = obj({'name': STRING, 'why': STRING})

KEYWORDS = {'type', 'properties', 'required', 'additionalProperties', 'items', 'minItems',
            'maxItems', 'uniqueItems', 'minLength', 'enum', 'minimum', 'maximum', 'oneOf'}


def check(rule):
    if not isinstance(rule, dict) or set(rule) - KEYWORDS:
        raise ValueError('unsupported schema keyword')
    types = rule.get('type', [])
    types = types if isinstance(types, list) else [types]
    if any(t not in ('object', 'array', 'string', 'null', 'boolean', 'integer', 'number') for t in types):
        raise ValueError('unsupported schema type')
    if 'additionalProperties' in rule and rule['additionalProperties'] is not False:
        raise ValueError('additionalProperties must be false or omitted')
    for child in rule.get('properties', {}).values():
        check(child)
    if 'items' in rule:
        check(rule['items'])
    if 'oneOf' in rule:
        if not isinstance(rule['oneOf'], list) or not rule['oneOf']:
            raise ValueError('oneOf must contain schemas')
        for child in rule['oneOf']:
            check(child)


def validate(value, schema, path='$'):
    if set(schema) - KEYWORDS:
        raise ValueError('unsupported schema keyword')
    types = {'object': (dict,), 'array': (list,), 'string': (str,), 'null': (type(None),),
             'boolean': (bool,), 'integer': (int,), 'number': (int, float)}
    expected = schema.get('type')
    choices = expected if isinstance(expected, list) else [expected]
    if expected is not None and not any(type(value) in types[t] for t in choices):
        return [f'{path}: expected {expected}']
    errors = []
    if 'oneOf' in schema:
        alternatives = [validate(value, child, path) for child in schema['oneOf']]
        if sum(not errors for errors in alternatives) != 1:
            errors.append(f'{path}: expected exactly one allowed variant')
            # Show the matching move variant's field errors when its tag is known.
            matched = [child for child in schema['oneOf'] if isinstance(value, dict) and
                       value.get('do') in child.get('properties', {}).get('do', {}).get('enum', [])]
            if len(matched) == 1:
                errors += validate(value, matched[0], path)
    if type(value) in (int, float):
        if (type(value) is float and not math.isfinite(value)) or not schema.get('minimum', -float('inf')) <= value <= schema.get('maximum', float('inf')):
            errors.append(f'{path}: number outside allowed range')
    if 'enum' in schema and value not in schema['enum']:
        errors.append(f'{path}: not one of {schema["enum"]}')
    if isinstance(value, dict):
        props = schema.get('properties', {})
        for key in schema.get('required', []):
            if key not in value:
                errors.append(f'{path}.{key}: missing')
        for key, item in value.items():
            if key in props:
                errors += validate(item, props[key], f'{path}.{key}')
            elif schema.get('additionalProperties') is False:
                errors.append(f'{path}.{key}: unexpected')
    if isinstance(value, list):
        if not schema.get('minItems', 0) <= len(value) <= schema.get('maxItems', float('inf')):
            errors.append(f'{path}: wrong item count')
        if schema.get('uniqueItems') and any(v in value[:i] for i, v in enumerate(value)):
            errors.append(f'{path}: repeated item')
        for i, item in enumerate(value):
            errors += validate(item, schema.get('items', {}), f'{path}[{i}]')
    if isinstance(value, str) and len(value.strip()) < schema.get('minLength', 0):
        errors.append(f'{path}: empty string')
    return errors
