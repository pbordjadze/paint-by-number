#!/usr/bin/env python3
"""Hashes of everything the field show (making_of_fields.FieldShow) makes of the small fixture, whole
and cropped to an odd size: its seeds and picks, every field at every pixel, the fuses, the lines and
the numbers' moments, and every frame and composite picture a twentieth of a second apart.

  python3 tools/factory/making_of_hashes.py > before.txt      # then change the code
  python3 tools/factory/making_of_hashes.py | diff before.txt -

Run it before and after a change that must not move a frame: the same lines mean the same show, bit
for bit, on this machine (the fields go through exp, log and pow, so another numpy or C library may
print other hashes). FieldShowTests.digest is the Swift side's. Needs numpy and Pillow."""

import hashlib
import json
import os
import shutil
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import making_of_fields as fields  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SMALL = os.path.join(ROOT, 'Tests', 'MakingOfTests', 'Fixtures', 'show-small')
SPEC = os.path.join(ROOT, 'App', 'PaintByNumber', 'Resources', 'making-of.json')
PICTURES = ('working-image.ppm', 'structure.pgm', 'smoothed.ppm', 'palette.ppm', 'simplified.ppm')
ODD = (215, 143)
SEED = 7


def digest(*parts):
    """One hash of arrays (their float64 or integer bytes) and plain values (their repr)."""
    h = hashlib.sha256()
    for part in parts:
        if isinstance(part, np.ndarray):
            h.update(str(part.dtype).encode() + str(part.shape).encode() + np.ascontiguousarray(part).tobytes())
        else:
            h.update(repr(part).encode())
    return h.hexdigest()[:20]


def plain(value):
    """A frame's value with its arrays as lists of exact reprs, so the whole of it hashes."""
    if isinstance(value, dict):
        return {k: plain(v) for k, v in sorted(value.items())}
    if isinstance(value, np.ndarray):
        return [float(v).hex() for v in value.ravel()]
    if isinstance(value, (list, tuple)):
        return [plain(v) for v in value]
    if isinstance(value, (float, np.floating)):
        return float(value).hex()
    if isinstance(value, np.generic):
        return value.item()
    return value


def report(name, show):
    print(f'{name} size {show.size} duration {show.duration!r} line width {show.line_width!r}')
    print(f'{name} seeds {digest(plain(show.seeds))} spread {digest(show.spread)} picks {digest(plain(show.picks))}')
    for key, plane in show.times.items():
        print(f'{name} times.{key} {digest(plane)}')
    print(f'{name} fuses {digest(*show.fuses)} numbers {digest(plain(show.number_times))}')
    print(f'{name} strokes ' + digest(*[part for s in show.strokes
                                        for part in (s.index, float(s.t0).hex(), float(s.dur).hex(), np.asarray(s.jagged),
                                                     np.asarray(s.smooth), np.asarray(s.relax))]))
    frames, pictures = hashlib.sha256(), hashlib.sha256()
    for i in range(int(show.duration * 20) + 2):
        frame = show.frame(i / 20)
        frames.update(json.dumps(plain(frame), sort_keys=True).encode())
        pictures.update(np.ascontiguousarray(show.composite(frame)).tobytes())
        if i % 40 == 20:
            print(f'{name} t = {i / 20:5.2f} frames so far {frames.hexdigest()[:20]} pictures so far {pictures.hexdigest()[:20]}')
    print(f'{name} frames {frames.hexdigest()[:20]} pictures {pictures.hexdigest()[:20]}')


def main():
    with open(SPEC, encoding='utf-8') as f:
        spec = json.load(f)
    report('small', fields.FieldShow(SMALL, os.path.join(SMALL, 'template.svg'), spec, SEED))
    with tempfile.TemporaryDirectory() as folder:
        for name in PICTURES:
            Image.open(os.path.join(SMALL, name)).crop((0, 0) + ODD).save(os.path.join(folder, name))
        shutil.copy(os.path.join(SMALL, 'template.svg'), folder)
        report('odd', fields.FieldShow(folder, os.path.join(folder, 'template.svg'), spec, SEED))
    report('seed 8', fields.FieldShow(SMALL, os.path.join(SMALL, 'template.svg'), spec, 8))


if __name__ == '__main__':
    main()
