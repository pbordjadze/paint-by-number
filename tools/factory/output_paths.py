"""Output validation shared by the portable factory review tools."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def outside_repo(path, repository=ROOT):
    original = Path(path).absolute()
    # Check before resolving so dangling links and links to another external directory fail too.
    for component in (original, *original.parents):
        if component.is_symlink():
            raise ValueError(f'symlinked output path: {component}')
    output = original.resolve()
    for repo in (ROOT, Path(repository).resolve()):
        if output == repo or repo in output.parents:
            raise ValueError('output must be outside the repository')
    if output.is_dir():
        for child in output.rglob('*'):
            if child.is_symlink():
                raise ValueError(f'symlinked output child: {child}')
    return output


def clean_frames(folder, extensions=('png', 'svg')):
    """Only numbered frames belong to the renderer; keep other files in shared output dirs."""
    folder = outside_repo(folder)
    if folder.exists():
        for path in folder.iterdir():
            if path.is_file() and re.fullmatch(r'[0-9]{4,}\.(?:' + '|'.join(extensions) + ')', path.name):
                path.unlink()
