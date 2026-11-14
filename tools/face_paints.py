#!/usr/bin/env python3
"""The paints on a face, beside the photo's colours there (painting-company row 344).

    tools/face_paints.py RUN/<id>/<before|after> X Y W H

`RUN` is an output directory of `tools/kit_eval.py run` (pbn's `raster.ppm`, the painted areas,
and `working.ppm`, the photo at the working size); X Y W H is the face's box, normalized to the
photo, origin top-left (a scene's `faces` entry). For each paint covering at least 1 % of the
box, most of the box first: its share of the box, the share of the paint's own area that lies in
the box (under 1: the face shares it with something else), the paint in OKLab (lightness, chroma,
hue in degrees), and the photo's mean colour under it inside the box and outside. A face's paint
whose photo colours inside and outside differ is what `FacePaints.split` separates.

Requires numpy and Pillow.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kit_eval import oklab

d = sys.argv[1]; x, y, w, h = map(float, sys.argv[2:6])
r = np.asarray(Image.open(d + '/raster.ppm').convert('RGB')); p = np.asarray(Image.open(d + '/working.ppm').convert('RGB'))
H, W = r.shape[:2]
box = np.zeros((H, W), bool); box[int(y*H):int((y+h)*H), int(x*W):int((x+w)*W)] = True
key = (r[..., 0].astype(int) << 16) | (r[..., 1].astype(int) << 8) | r[..., 2]
lab = oklab(p)
def lch(v):
    return "L%.2f C%.3f h%3.0f" % (v[0], np.hypot(v[1], v[2]), np.degrees(np.arctan2(v[2], v[1])) % 360)
rows = []
for k in np.unique(key):
    m = key == k; inb = m & box
    if inb.sum() < 0.01 * box.sum(): continue
    c = np.array([[[(k >> 16) & 255, (k >> 8) & 255, k & 255]]], dtype=np.uint8)
    out = m & ~box
    rows.append((inb.sum() / box.sum(), "#%06x box %.2f  of paint %.2f | paint %s | photo in box %s | outside %s" % (
        k, inb.sum() / box.sum(), inb.sum() / m.sum(), lch(oklab(c)[0, 0]), lch(lab[inb].mean(0)), lch(lab[out].mean(0)) if out.any() else "-")))
for _, s in sorted(rows, reverse=True): print(s)
