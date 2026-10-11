"""Validate job identifiers and contain all job artifacts, including through symlinks."""
from pathlib import Path
import re


def slug(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9]+(?:[-_][A-Za-z0-9]+)*', value):
        raise ValueError('ID must be a nonempty safe slug')
    return value


def round_number(value):
    if type(value) is not int or value < 1:
        raise ValueError('round must be a positive integer')
    return value


def validate_job(job):
    if not isinstance(job, dict) or not {'id', 'round', 'attempt'} <= job.keys():
        raise ValueError('job must include id, round and attempt')
    slug(job['id'])
    round_number(job['round'])
    if type(job['attempt']) is not int or job['attempt'] not in (0, 1):
        raise ValueError('attempt must be 0 or 1')


def contained(root, *parts):
    """Resolve against a trusted root; refuse every symlink below it before any write.

    The root's own ancestors may be links (macOS's /tmp and /var are), so they aren't checked."""
    root = Path(root).resolve()
    path = root
    for part in parts:
        part = Path(part)
        if part.is_absolute() or '..' in part.parts:
            raise ValueError('artifact path must stay within its directory')
        for component in part.parts:
            path = path / component
            if path.is_symlink():
                raise ValueError(f'symlinked artifact path: {path}')
    resolved = path.resolve()
    if resolved != root and root not in resolved.parents:
        raise ValueError('artifact path escaped its directory')
    return resolved


def job_path(root, job, kind):
    validate_job(job)
    slug(kind)
    n, jid, attempt = job['round'], job['id'], job['attempt']
    if kind == 'scratch':
        return contained(root, f'{n:03}', f'{jid}-{attempt}')
    suffix = '.retry' if kind == 'replies' and attempt else f'-{attempt}' if kind in ('costs', 'rejections') else ''
    return contained(root, kind, f'{n:03}', f'{jid}{suffix}.json')


def legacy_path(root, role, jid, n=None):
    if role not in ('proposals', 'verdicts'):
        raise ValueError('role must be proposals or verdicts')
    slug(jid)
    parts = ('rounds', f'{round_number(n):03}', role) if n is not None else (role,)
    return contained(root, *parts, f'{jid}.json')
