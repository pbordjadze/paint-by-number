"""Layered cells: one fixed set of cells, every cell bounded by a line, every line bounding
cells; each line carries a layer that decides how strongly it draws at a given zoom.

Layers (strongest first):
  top    closed outlines of objects, full strength at every zoom: HED at sparse thresholds,
         its gaps closed by pbn's strongest colour boundaries (lines_boundaries at sparse
         thresholds: a piece joining two top lines, up to BRIDGE_MAX px), and the subject's
         silhouette (subject.py, BiRefNet: crisp mask edges only, and only
         when the mask holds 0.5-70 % of the picture); strokes inside an eye box (eyes.py) or
         a face (YuNet) are promoted here, and each eye gets the outline of its darkest
         paint (the iris / pupil) as a closed top line.
  mid    HED detail (rich thresholds, medium cleanup) not already in top.
  inner  TEED texture (medium) not already above (`hed-layers`: HED at low thresholds).
  color  boundaries between two cells where no drawing line runs (banded skies, shading).

Pipeline per picture and variant:
 1. Lines per layer, each lower layer deduplicated against the ones above (a point within
    DEDUP px of a higher line is that line; leftover runs reconnect to it, short ones go).
 2. Free ends are extended along their tangent (cone CLOSE_CONE) to the nearest line, pbn
    colour boundary or frame within CLOSE_REACH[layer] px, so open strokes close cells.
 3. Cells = C1 (color_split): pbn's regions split by all drawing lines, snap, small-fragment
    merge inside each enclosed area, cells too small for a number join a same-paint region
    across the line (or vanish when all ink). Then no cell stays below its number's size:
    the rest merge into their most similar neighbour, except cells inside an eye box.
    `merged-color` then merges neighbouring cells of one enclosed area whose paints are
    within MERGE_STEPS palette steps (the larger cell keeps its paint). `joined` instead
    joins neighbouring cells with the same paint unless a top line separates them; its mid,
    inner and colour lines stay drawn, so they may run inside a cell (join_same_paint).
 4. Lines are trimmed to where they bound two different cells (no line inside a cell), and
    the cell boundaries no drawing line covers are traced as `color` lines.
 5. Numbers: LabelSizing at each cell's pole (plus pbn-style extras over big cells), with the
    zoom at which the digits are LEGIBLE_CSS px tall on a PHONE_CSS px wide phone that shows
    the whole picture at 1x.

Outputs per picture and variant (see results_layers.md): lines.svg, flat.jpg, finished.jpg,
z1.jpg / z2.jpg / z4.jpg, metrics.json; per picture photo.jpg, today_*.jpg; manifest.json.

    python layers.py <pic> [<pic> ...] [--variants recommended,no-closure,...] [--jobs 2]
    python layers.py --manifest
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from types import SimpleNamespace

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from scipy.spatial import cKDTree
from skimage import measure, morphology

import color_common as cc
import lines_boundaries
import lines_common as lc
import panels
import strokes as st
from color_split import finish

HERE = os.path.dirname(os.path.abspath(__file__))
SCRATCH = os.environ.get("S", os.getcwd())
ROOT = os.path.join(SCRATCH, "lineart")
INPUTS = os.path.join(ROOT, "inputs")
STAGE1 = os.path.join(ROOT, "out")
OUT = os.path.join(ROOT, "layers")
FONT = os.path.join(SCRATCH, "fonts", "SourceSerif4-Regular.ttf")
NODE = os.environ.get("PANEL_NODE", "/opt/node22/bin/node")
NODE_DIR = os.path.join(SCRATCH, "node")

LAYERS = ["top", "mid", "inner", "color"]
PAPER = "#F4EFE6"
INK = "#2B2530"
NUMBER_INK = "#706876"
PHONE_CSS = 390.0          # a phone 390 CSS px wide shows the whole picture at 1x
LEGIBLE_CSS = 8.0          # digits (LabelSizing's 0.72 em) this tall on screen are legible
RENDER_WIDTH = 1080        # static renders: a 390 CSS px phone at ~2.8 device px per CSS px
CSS_WIDTH = {"top": 1.4, "mid": 1.0, "inner": 0.75, "color": 0.6}   # line width at 1x, CSS px
DARK_LIGHT, DARK_HEAVY = 0.8, 0.3   # OKLab L of a line's darker side: x0.75 weight at 0.8, x1.25 at 0.3

# Detector settings: (cached raw map, high, low, cleanup detail, fill level).
SOURCES = {
    "hed_top": ("learned_hed", 0.85, 0.50, "sparse", 0.85),
    "hed_mid": ("learned_hed", 0.50, 0.25, "medium", 0.85),
    "hed_inner": ("learned_hed", 0.30, 0.15, "rich", 0.85),
    "teed_inner": ("learned_teed", 0.60, 0.35, "medium", 0.80),
    "pbn_strong": ("boundaries", 0.45, 0.25, "sparse", 0.45),
}
VARIANTS = {
    "recommended": dict(label="Recommended", top=["hed_top", "pbn_strong", "silhouette"], mid=["hed_mid"],
                        inner=["teed_inner"], merge_color=False),
    "no-closure": dict(label="No closure", top=["hed_top"], mid=["hed_mid"], inner=["teed_inner"],
                       merge_color=False),
    "hed-layers": dict(label="HED only", top=["hed_top", "pbn_strong", "silhouette"], mid=["hed_mid"],
                       inner=["hed_inner"], merge_color=False),
    "merged-color": dict(label="Merged colours", top=["hed_top", "pbn_strong", "silhouette"], mid=["hed_mid"],
                         inner=["teed_inner"], merge_color=True),
    "joined": dict(label="Joined same paint", top=["hed_top", "pbn_strong", "silhouette"], mid=["hed_mid"],
                   inner=["teed_inner"], merge_color=False, join_across=("mid", "inner", "color")),
}
DEDUP = 3.5
DEDUP_BY = {"silhouette": 5.0}   # the mask's edge sits a few px off HED's line on fur
BRIDGE_END = 6.0           # ... and starts this close to a free end of a top line
BRIDGE_MAX = 50.0          # pbn's strong boundaries join the top only as gap closers this long
MIN_RUN = 10.0
CLOSE_REACH = {"top": 16.0, "mid": 12.0, "inner": 10.0}
CLOSE_CONE = 40.0
TRIM_NEAR = 2.2            # a line point bounds cells when a cell boundary is this close
TRIM_MIN = 4.0             # runs (kept or dropped) shorter than this follow their neighbours
COLOR_CLEAR = 3.0          # cell boundaries this close to a drawn line belong to that line
SUBJECT_SHARE = (0.005, 0.70)
SUBJECT_CRISP = 0.05       # mask gradient (per px) along a silhouette edge that counts as crisp
SUBJECT_SIDE_PX = 7.0      # ... and the photo must differ across it (OKLab, sigma 3, +-7 px)
SUBJECT_SIDE_DE = 0.015
EYE_GROW = 1.25
EYE_ALMOND = 0.20          # the eye: paint this much darker (OKLab L) than the eye box's rim
EYE_PUPIL = 0.35           # the pupil: darker still
EYE_ELLIPSE = 1.1          # the eye is clipped to the ellipse inscribed in its box, grown this much
MERGE_STEPS = 2.0
JOIN_BLOCK = 4             # `joined`: a top line along this many px of a shared border keeps cells apart
# Finished view: stage 2's line-respecting blur, wider: colour boundaries up to
# FINISH_FREE_STEPS palette steps blend freely (every object edge is a drawn line, a hard
# barrier, so colour boundaries are only bands and shading), FINISH_SIGMA working px where
# cells are big (stage 2: 1.2 steps, 24 px, which left a banded sky's steps visible).
FINISH_FREE_STEPS = 1.6
FINISH_SIGMA = 40.0

# Render presets: per layer opacity and width multiplier at zoom 1, 2, 4 (log-linear between,
# clamped outside). The drawn width of a path in working px is its stroke-width (or its group's
# data-base when "weighted" is false) times the multiplier; on screen that is
# width x multiplier x zoom x 390 / W CSS px.
PRESETS = {
    "fade": {"label": "Fade by opacity, weighted", "weighted": True,
             "top": {"opacity": [1.0, 1.0, 1.0], "width": [1.0, 0.6, 0.36]},
             "mid": {"opacity": [0.55, 1.0, 1.0], "width": [1.0, 0.6, 0.36]},
             "inner": {"opacity": [0.25, 0.6, 1.0], "width": [1.0, 0.6, 0.36]},
             "color": {"opacity": [0.15, 0.3, 0.5], "width": [1.0, 0.6, 0.36]}},
    "grow": {"label": "Fade by width, weighted", "weighted": True,
             "top": {"opacity": [1.0, 1.0, 1.0], "width": [1.0, 0.6, 0.36]},
             "mid": {"opacity": [0.85, 1.0, 1.0], "width": [0.45, 0.6, 0.36]},
             "inner": {"opacity": [0.7, 0.85, 1.0], "width": [0.3, 0.3, 0.36]},
             "color": {"opacity": [0.45, 0.5, 0.6], "width": [0.35, 0.3, 0.3]}},
    "fade-uniform": {"label": "Fade by opacity, uniform weight", "weighted": False,
                     "top": {"opacity": [1.0, 1.0, 1.0], "width": [1.0, 0.6, 0.36]},
                     "mid": {"opacity": [0.55, 1.0, 1.0], "width": [1.0, 0.6, 0.36]},
                     "inner": {"opacity": [0.25, 0.6, 1.0], "width": [1.0, 0.6, 0.36]},
                     "color": {"opacity": [0.15, 0.3, 0.5], "width": [1.0, 0.6, 0.36]}},
}
DEFAULT_PRESET = "fade"

TITLES = {
    "santa-fe-freight": "Santa Fe Freight", "hawksbill-turtle": "Hawksbill Turtle", "red-fox": "Red Fox",
    "great-wave": "The Great Wave", "milkmaid": "The Milkmaid", "wheat-field": "Wheat Field with Cypresses",
    "cezanne-apples": "Cézanne's Apples", "delicate-arch": "Delicate Arch", "lassen-lupine": "Lassen Lupine",
}
ORDER = ["santa-fe-freight", "hawksbill-turtle", "red-fox", "great-wave", "milkmaid", "wheat-field",
         "cezanne-apples", "delicate-arch", "lassen-lupine"]
# Zoom crops: centres (working px) of the 2x and 4x details; rects are W/z x H/z.
CROPS = {
    "red-fox": {"z2": (1020, 560), "z4": (1020, 585)},
    "hawksbill-turtle": {"z2": (1000, 560), "z4": (905, 490)},
    "santa-fe-freight": {"z2": (560, 430), "z4": (520, 400)},
    "great-wave": {"z2": (660, 392), "z4": (785, 314)},
    "milkmaid": {"z2": (850, 620), "z4": (850, 430)},
    "wheat-field": {"z2": (1150, 420), "z4": (1290, 420)},
    "cezanne-apples": {"z2": (1200, 600), "z4": (1015, 610)},
    "delicate-arch": {"z2": (548, 498), "z4": (450, 330)},
    "lassen-lupine": {"z2": (650, 560), "z4": (640, 660)},
}


# ---------------------------------------------------------------------------------------------
# Lines


@dataclass
class Line:
    pts: np.ndarray                 # (N, 2) dense polyline, working px, pixel centres at integers
    closed: bool
    layer: str
    source: str
    free: tuple = (False, False)    # open ends not attached to anything
    links: list = field(default_factory=list)   # (index, qx, qy): wall-only seals to junctions
    w: float = 1.0                  # weight factor (stroke-width = layer base x w)


def arclen(p: np.ndarray) -> np.ndarray:
    if len(p) < 2:
        return np.zeros(len(p))
    return np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(p, axis=0).T))])


def length(L: Line) -> float:
    a = arclen(L.pts)
    extra = float(np.hypot(*(L.pts[0] - L.pts[-1]))) if L.closed and len(L.pts) > 1 else 0.0
    return float(a[-1]) + extra


def runs(mask: np.ndarray) -> list:
    """Inclusive (start, end) index pairs of the True runs of a 1-d bool array."""
    if not mask.any():
        return []
    d = np.diff(np.concatenate([[0], mask.astype(np.int8), [0]]))
    s = np.flatnonzero(d == 1)
    e = np.flatnonzero(d == -1) - 1
    return list(zip(s.tolist(), e.tolist()))


def _sub_links(L: Line, i0: int, i1: int) -> list:
    return [(i - i0, qx, qy) for i, qx, qy in L.links if i0 <= i <= i1]


def from_strokes(strokes, layer, source) -> list:
    out = []
    for s in strokes:
        d = s["dense"]
        if len(d) < 2:
            continue
        links = []
        for p, q in s["links"]:
            i = int(np.argmin(np.hypot(*(d - p).T)))
            if np.hypot(*(np.asarray(q) - d[i])) > 0.3:
                links.append((i, float(q[0]), float(q[1])))
        out.append(Line(d.copy(), bool(s["closed"]), layer, source, tuple(s["free"]), links))
    return out


def pixels(L: Line) -> tuple[np.ndarray, np.ndarray]:
    """8-connected raster pixels (x, y) of a line (and its links), with the index of the dense
    point each pixel starts from."""
    p = np.rint(L.pts).astype(np.int64)
    idx0 = np.arange(len(p))
    if L.closed and len(p) > 2:
        p = np.vstack([p, p[:1]])
        idx0 = np.concatenate([idx0, [0]])
    parts, parts_i = [], []
    if len(p) == 1:
        parts.append(p); parts_i.append(idx0)
    else:
        n = np.maximum(np.abs(np.diff(p, axis=0)).max(1), 1)
        seg = np.repeat(np.arange(len(n)), n)
        k = np.arange(int(n.sum())) - np.repeat(np.cumsum(n) - n, n)
        t = (k / n[seg])[:, None]
        q = np.rint(p[seg] + (p[seg + 1] - p[seg]) * t).astype(np.int64)
        parts.append(np.vstack([q, p[-1:]])); parts_i.append(np.concatenate([idx0[seg], idx0[-1:]]))
    for i, qx, qy in L.links:
        a = np.rint(L.pts[i]).astype(np.int64)
        b = np.array([int(round(qx)), int(round(qy))])
        n = max(int(np.abs(b - a).max()), 1)
        t = (np.arange(n + 1) / n)[:, None]
        parts.append(np.rint(a + (b - a) * t).astype(np.int64)); parts_i.append(np.full(n + 1, i))
    return np.vstack(parts), np.concatenate(parts_i)


def rasterize(lines: list, h: int, w: int, owner: bool = False):
    m = np.zeros((h, w), bool)
    own = np.full((h, w), -1, np.int32) if owner else None
    for k, L in enumerate(lines):
        q, _ = pixels(L)
        ok = (q[:, 0] >= 0) & (q[:, 0] < w) & (q[:, 1] >= 0) & (q[:, 1] < h)
        q = q[ok]
        m[q[:, 1], q[:, 0]] = True
        if owner:
            own[q[:, 1], q[:, 0]] = k
    return (m, own) if owner else m


def sample(img: np.ndarray, pts: np.ndarray) -> np.ndarray:
    h, w = img.shape[:2]
    x = np.clip(np.rint(pts[:, 0]).astype(int), 0, w - 1)
    y = np.clip(np.rint(pts[:, 1]).astype(int), 0, h - 1)
    return img[y, x]


def split_by(L: Line, inside: np.ndarray) -> tuple[list, list]:
    """Pieces of a line inside / outside a mask; neighbouring pieces share their cut point."""
    m = sample(inside, L.pts).astype(bool)
    if m.all():
        return [L], []
    if not m.any():
        return [], [L]
    pts = L.pts
    links = L.links
    if L.closed:
        s = int(np.argmax(m != m[0])) if (m != m[0]).any() else 0
        pts = np.roll(pts, -s, axis=0)
        links = [((i - s) % len(L.pts), qx, qy) for i, qx, qy in links]
        m = np.roll(m, -s)
        pts = np.vstack([pts, pts[:1]])
        m = np.concatenate([m, m[:1]])
    tmp = Line(pts, False, L.layer, L.source, L.free, links, L.w)
    ins, outs = [], []
    n = len(pts)
    for flag, bucket in ((True, ins), (False, outs)):
        for i0, i1 in runs(m == flag):
            a, b = max(i0 - 1, 0), min(i1 + 1, n - 1)
            free = (L.free[0] if a == 0 and not L.closed else False, L.free[1] if b == n - 1 and not L.closed else False)
            if b - a >= 1:
                bucket.append(Line(pts[a:b + 1].copy(), False, L.layer, L.source, free, _sub_links(tmp, a, b), L.w))
    return ins, outs


def dedupe(lines: list, occupied: np.ndarray, dist: float = DEDUP, bridges_only: float | None = None) -> list:
    """Drops the parts of ``lines`` within ``dist`` of ``occupied`` (a higher layer's pixels);
    leftover runs reconnect to the occupied pixel nearest their cut ends. With
    ``bridges_only`` only runs joining two occupied lines, at most that long, are kept."""
    if not occupied.any():
        return list(lines)
    dt, ind = ndi.distance_transform_edt(~occupied, return_indices=True)
    out = []
    for L in lines:
        red = sample(dt, L.pts) <= dist
        if not red.any():
            out.append(L)
            continue
        if red.all():
            continue
        pts, links, closed = L.pts, L.links, L.closed
        if closed:
            s = int(np.argmax(red))
            pts = np.roll(pts, -s, axis=0)
            links = [((i - s) % len(L.pts), qx, qy) for i, qx, qy in links]
            red = np.roll(red, -s)
        tmp = Line(pts, False, L.layer, L.source, L.free, links, L.w)
        n = len(pts)
        for i0, i1 in runs(~red):
            seg = pts[i0:i1 + 1]
            lk = _sub_links(tmp, i0, i1)
            cut0, cut1 = closed or i0 > 0, closed or i1 < n - 1
            con = [False, False]
            for end in (0, 1):
                if not (cut0 if end == 0 else cut1):
                    continue
                p = seg[0] if end == 0 else seg[-1]
                y, x = int(np.clip(round(p[1]), 0, dt.shape[0] - 1)), int(np.clip(round(p[0]), 0, dt.shape[1] - 1))
                q = np.array([ind[1][y, x], ind[0][y, x]], float)
                if np.hypot(*(q - p)) <= dist + 2.0:
                    con[end] = True
                    if end == 0:
                        seg = np.vstack([q, seg])
                        lk = [(i + 1, qx, qy) for i, qx, qy in lk]
                    else:
                        seg = np.vstack([seg, q])
            Ls = float(arclen(seg)[-1])
            if Ls < MIN_RUN and not (con[0] and con[1] and Ls >= 4.0):
                continue
            if bridges_only is not None and not (con[0] and con[1] and Ls <= bridges_only):
                continue
            free = ((L.free[0] if not cut0 else not con[0]) if not closed else not con[0],
                    (L.free[1] if not cut1 else not con[1]) if not closed else not con[1])
            out.append(Line(seg, False, L.layer, L.source, free, lk, L.w))
    return out


def close_free_ends(lines: list, color_edges: np.ndarray, h: int, w: int) -> int:
    """Extends free ends along their tangent to the nearest line, pbn colour boundary or frame
    within CLOSE_REACH[layer] px (cone CLOSE_CONE): an open stroke then closes cells."""
    occ, own = rasterize(lines, h, w, owner=True)
    ys, xs = np.nonzero(occ | color_edges)
    tid = np.where(occ[ys, xs], own[ys, xs], -2)
    fx = [np.arange(w), np.arange(w), np.zeros(h, int), np.full(h, w - 1)]
    fy = [np.zeros(w, int), np.full(w, h - 1), np.arange(h), np.arange(h)]
    xs = np.concatenate([xs] + fx)
    ys = np.concatenate([ys] + fy)
    tid = np.concatenate([tid, np.full(2 * w + 2 * h, -3)])
    tree = cKDTree(np.stack([xs, ys], 1).astype(float))
    cos_cone = math.cos(math.radians(CLOSE_CONE))
    # arc position of each owner pixel, to let a curl close on itself but not on its own end
    arcpos = {}
    done = 0
    for k, L in enumerate(lines):
        if L.closed or not any(L.free):
            continue
        reach = CLOSE_REACH.get(L.layer, 10.0)
        a = arclen(L.pts)
        for end in (0, 1):
            if not L.free[end]:
                continue
            pts = L.pts if end == 0 else L.pts[::-1]
            t = st._end_tangent(pts)
            if not t.any():
                continue
            p = pts[0]
            best = None
            for j in tree.query_ball_point(p, reach):
                q = np.array([xs[j], ys[j]], float)
                v = q - p
                d = float(np.hypot(*v))
                if d < 1.5:
                    continue
                c = float(v @ t) / d
                if c < cos_cone:
                    continue
                if tid[j] == k:
                    if k not in arcpos:
                        arcpos[k] = cKDTree(L.pts)
                    i = arcpos[k].query(q)[1]
                    along = a[i] if end == 0 else a[-1] - a[i]
                    if along < 3 * reach:
                        continue
                score = d * (1 + 2 * (1 - c)) * (1.15 if tid[j] == -2 else 1.0)
                if best is None or score < best[0]:
                    best = (score, q)
            if best is None:
                continue
            q = best[1]
            n = max(int(math.ceil(np.hypot(*(q - p)))), 1)
            ext = p + (q - p) * (np.arange(1, n + 1) / n)[:, None]
            if end == 0:
                L.pts = np.vstack([ext[::-1], L.pts])
                L.links = [(i + n, qx, qy) for i, qx, qy in L.links]
                a = arclen(L.pts)
            else:
                L.pts = np.vstack([L.pts, ext])
            L.free = (False, L.free[1]) if end == 0 else (L.free[0], False)
            done += 1
    return done


# ---------------------------------------------------------------------------------------------
# Picture inputs and line sources


def load_inputs(pic_name: str) -> SimpleNamespace:
    pdir = os.path.join(INPUTS, pic_name)
    sdir = os.path.join(STAGE1, pic_name)
    pic = cc.load_picture(pdir)
    lpic = lc.load_picture(pdir)
    h, w = pic.height, pic.width
    imp = np.asarray(Image.open(os.path.join(sdir, "importance.png")).convert("L"), np.float32) / 255.0
    faces = json.load(open(os.path.join(sdir, "importance.json"))).get("faces", [])
    lab = lc.rgb8_to_oklab(lpic["working"])
    lab_smooth = np.stack([ndi.gaussian_filter(lab[..., c], 1.0, mode="nearest") for c in range(3)], 2)
    grad = lc.oklab_gradient(lab, 1.0)
    odir = os.path.join(OUT, pic_name)
    os.makedirs(odir, exist_ok=True)
    sub_png = os.path.join(odir, "_subject.png")
    import subject
    prob = subject.load_or_compute(pdir, sub_png)
    eyes_json = os.path.join(odir, "_eyes.json")
    import eyes as eyes_mod
    share = float((prob > 0.5).mean())
    eye_boxes = eyes_mod.load_or_compute(pdir, prob, eyes_json) if SUBJECT_SHARE[0] < share < SUBJECT_SHARE[1] else []
    r = pic.raster
    edges = np.zeros((h, w), bool)
    dr, dd = r[:, :-1] != r[:, 1:], r[:-1, :] != r[1:, :]
    edges[:, :-1] |= dr; edges[:, 1:] |= dr; edges[:-1, :] |= dd; edges[1:, :] |= dd
    return SimpleNamespace(name=pic_name, dir=pdir, sdir=sdir, odir=odir, pic=pic, lpic=lpic, h=h, w=w,
                           imp=imp, faces=faces, lab=lab, lab_smooth=lab_smooth, grad=grad, prob=prob,
                           eyes=eye_boxes, color_edges=edges)


def build_sources(I) -> dict:
    out = {}
    for name, (fam, high, low, detail, fill) in SOURCES.items():
        t0 = time.time()
        if fam == "boundaries":
            raw = lines_boundaries.response(I.lpic)
        else:
            raw = np.load(os.path.join(I.sdir, "_cache", fam + ".npy"))
        _, strokes = st.extract(raw, I.imp, high, low, detail, fill, I.grad)
        out[name] = from_strokes(strokes, "top", name)
        out[name + "_seconds"] = round(time.time() - t0, 2)
    t0 = time.time()
    out["silhouette"], out["silhouette_info"] = silhouette_lines(I)
    out["silhouette_seconds"] = round(time.time() - t0, 2)
    out["eye_outlines"], out["eye_interior"] = eye_outlines(I)
    return out


def silhouette_lines(I) -> tuple[list, dict]:
    """Crisp edges of the subject mask: contours of the (holes-filled, specks-removed) mask at
    0.5, kept where the model is sure (mask gradient >= SUBJECT_CRISP), where the photo differs
    across the edge (SUBJECT_SIDE_DE) and away from the frame."""
    h, w = I.h, I.w
    m = I.prob > 0.5
    share = float(m.mean())
    info = {"model": "onnx-community/BiRefNet-ONNX (MIT)", "share": round(share, 3), "used": False}
    if not (SUBJECT_SHARE[0] < share < SUBJECT_SHARE[1]):
        return [], info
    m = morphology.remove_small_objects(m, max_size=int(0.001 * h * w))
    m = morphology.remove_small_holes(m, max_size=150)
    sm = ndi.gaussian_filter(m.astype(np.float32), 1.5)
    g = ndi.gaussian_gradient_magnitude(I.prob.astype(np.float32), 1.5)
    lab3 = np.stack([ndi.gaussian_filter(I.lab[..., c], 3.0) for c in range(3)], 2)
    out = []
    total, crisp_len = 0.0, 0.0
    for c in measure.find_contours(sm, 0.5):
        pts = c[:, ::-1].astype(float)
        closed = bool(np.allclose(pts[0], pts[-1]))
        if closed:
            pts = pts[:-1]
        if len(pts) < 8:
            continue
        a = arclen(pts)
        total += a[-1]
        gs = ndi.gaussian_filter1d(sample(g, pts), 3.0, mode="wrap" if closed else "nearest")
        ok = (gs >= SUBJECT_CRISP) & (pts[:, 0] > 3) & (pts[:, 0] < w - 4) & (pts[:, 1] > 3) & (pts[:, 1] < h - 4)
        # the mask may also end where nothing in the picture does (the Great Wave's mask cuts
        # through open sky): drop long stretches where the photo is the same colour on both sides
        # at a wide scale (white fur on snow still differs by 0.047 there; the sky cut by < 0.012)
        nrm = st._normals(pts, closed)
        side = np.linalg.norm(st._bilinear(lab3, pts + SUBJECT_SIDE_PX * nrm) - st._bilinear(lab3, pts - SUBJECT_SIDE_PX * nrm), axis=1)
        side = ndi.gaussian_filter1d(side, 8.0, mode="wrap" if closed else "nearest")
        for i0, i1 in runs(side < SUBJECT_SIDE_DE):
            if a[i1] - a[i0] >= 30:
                ok[i0:i1 + 1] = False
        if ok.all() and closed:
            out.append(Line(pts, True, "top", "silhouette"))
            crisp_len += a[-1]
            continue
        if closed:
            s = int(np.argmin(ok)) if not ok.all() else 0
            pts, ok = np.roll(pts, -s, axis=0), np.roll(ok, -s)
        for i0, i1 in runs(ok):
            seg = pts[i0:i1 + 1]
            Ls = float(arclen(seg)[-1])
            if Ls >= 20:
                near_frame = lambda p: min(p[0], p[1], w - 1 - p[0], h - 1 - p[1]) < 6
                out.append(Line(seg.copy(), False, "top", "silhouette", (not near_frame(seg[0]), not near_frame(seg[-1]))))
                crisp_len += Ls
    info.update(used=bool(out), crispShare=round(crisp_len / max(total, 1), 3))
    return out, info


def eye_regions(I) -> list:
    """Per eye box: the almond (paint darker than the box's rim by EYE_ALMOND inside the
    ellipse inscribed in the box, the component nearest the box centre, holes filled,
    smoothed) and the pupil (darker by EYE_PUPIL inside
    it), as bool masks of the full picture (pupil None when it is not distinct)."""
    out = []
    L = I.pic.palette_lab[:, 0][I.pic.raster]
    for score, (x0, y0, x1, y1) in I.eyes:
        cx, cy, bw, bh = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) * EYE_GROW, (y1 - y0) * EYE_GROW
        X0, Y0 = max(int(cx - bw / 2), 0), max(int(cy - bh / 2), 0)
        X1, Y1 = min(int(math.ceil(cx + bw / 2)), I.w), min(int(math.ceil(cy + bh / 2)), I.h)
        sub = L[Y0:Y1, X0:X1]
        ring = float(np.median(np.concatenate([sub[0], sub[-1], sub[:, 0], sub[:, -1]])))
        yy, xx = np.mgrid[Y0:Y1, X0:X1]

        def nearest(mask):
            lab_, n = ndi.label(mask, structure=np.ones((3, 3), bool))
            best, best_s = 0, -1.0
            for k in range(1, n + 1):
                mk = lab_ == k
                d = math.hypot(float(xx[mk].mean()) - cx, float(yy[mk].mean()) - cy) / max(bw, bh)
                s = float(mk.sum()) * math.exp(-4 * d)
                if s > best_s:
                    best, best_s = k, s
            return (lab_ == best) if best else None

        def smooth(mk):
            mk = ndi.binary_fill_holes(ndi.binary_closing(np.pad(mk, 2), iterations=1))[2:-2, 2:-2]
            return ndi.gaussian_filter(mk.astype(np.float32), 1.0) > 0.5

        # dark paint usually runs on past the eye (eyeliner, a fox's tear line, a lid's
        # shadow); clipped to the ellipse inscribed in the eye's box it keeps an eye's shape
        rx, ry = (x1 - x0) / 2 * EYE_ELLIPSE, (y1 - y0) / 2 * EYE_ELLIPSE
        ellipse = ((xx + 0.5 - cx) / rx) ** 2 + ((yy + 0.5 - cy) / ry) ** 2 <= 1
        almond = nearest((sub < ring - EYE_ALMOND) & ellipse)
        if almond is None or almond.sum() < 12:
            continue
        almond = smooth(almond) & ellipse
        pupil = nearest((sub < ring - EYE_PUPIL) & almond)
        if pupil is not None:
            pupil = smooth(pupil) & almond
            if not (8 <= pupil.sum() <= 0.75 * almond.sum()):
                pupil = None
        full = lambda mk: np.pad(mk, ((Y0, I.h - Y1), (X0, I.w - X1))) if mk is not None else None
        out.append((full(almond), full(pupil)))
    return out


def mask_outline(mk: np.ndarray, source: str) -> list:
    sm = ndi.gaussian_filter(np.pad(mk, 2).astype(np.float32), 0.8)
    out = []
    for c in measure.find_contours(sm, 0.5):
        pts = c[:, ::-1] - 2
        if np.allclose(pts[0], pts[-1]):
            pts = pts[:-1]
        if len(pts) >= 6:
            out.append(Line(pts.astype(float), True, "top", source))
    return out


def eye_outlines(I) -> tuple[list, np.ndarray]:
    """Closed top lines around each eye's almond and pupil, and the almonds' interiors (other
    strokes there are cleared: an eye is drawn as an outline and a pupil, nothing else)."""
    lines, interior = [], np.zeros((I.h, I.w), bool)
    for almond, pupil in eye_regions(I):
        lines += mask_outline(almond, "eye")
        if pupil is not None:
            lines += mask_outline(pupil, "eye")
        interior |= ndi.binary_erosion(almond, iterations=1)
    return lines, interior


def eye_mask(I, grow: float = EYE_GROW) -> np.ndarray:
    m = np.zeros((I.h, I.w), bool)
    for score, (x0, y0, x1, y1) in I.eyes:
        cx, cy, bw, bh = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) * grow, (y1 - y0) * grow
        m[max(int(cy - bh / 2), 0):int(math.ceil(cy + bh / 2)), max(int(cx - bw / 2), 0):int(math.ceil(cx + bw / 2))] = True
    return m


def face_mask(I) -> np.ndarray:
    m = np.zeros((I.h, I.w), bool)
    if not I.faces:
        return m
    yy, xx = np.mgrid[0:I.h, 0:I.w]
    for x, y, fw, fh in I.faces:
        cx, cy = x + fw / 2, y + fh / 2
        m |= ((xx - cx) / (0.6 * fw)) ** 2 + ((yy - cy) / (0.65 * fh)) ** 2 <= 1
    return m


# ---------------------------------------------------------------------------------------------
# Assembly


def assemble(I, src: dict, spec: dict) -> tuple[list, dict]:
    def copies(name):
        out = []
        for L in src[name]:
            C = Line(L.pts.copy(), L.closed, L.layer, L.source, L.free, list(L.links), L.w)
            # an eye is its outline and pupil: other strokes inside the almond go
            out += split_by(C, ~src["eye_interior"])[0] if src["eye_interior"].any() else [C]
        return out

    pools = {"top": [], "mid": [], "inner": []}
    for layer in ("mid", "inner"):
        for name in spec[layer]:
            for L in copies(name):
                L.layer = layer
                pools[layer].append(L)
    # strokes on a face (YuNet) are drawn at full strength: HED's detail there joins the top
    face_m = face_mask(I)
    promoted = []
    if face_m.any():
        keep = []
        for L in pools["mid"]:
            ins, outs = split_by(L, face_m)
            for P in ins:
                P.layer, P.source = "top", "face:" + P.source
            promoted += ins
            keep += outs
        pools["mid"] = keep
    stats = {"promoted": len(promoted)}
    accepted = {"top": [], "mid": [], "inner": []}
    occ = np.zeros((I.h, I.w), bool)
    batches = [("eye", src["eye_outlines"])] + [(n, copies(n)) for n in spec["top"]] + [("promoted", promoted)]
    for name, batch in batches:
        for L in batch:
            L.layer = "top"
        kept = dedupe(batch, occ, DEDUP_BY.get(name, DEDUP), BRIDGE_MAX if name == "pbn_strong" else None)
        if name == "pbn_strong":
            # a gap closer starts at a free end of a top line (not a near-copy of a line)
            ends = [L.pts[0] for L in accepted["top"] if not L.closed and L.free[0]]
            ends += [L.pts[-1] for L in accepted["top"] if not L.closed and L.free[1]]
            if ends:
                tree = cKDTree(np.array(ends))
                kept = [L for L in kept if min(tree.query(L.pts[0])[0], tree.query(L.pts[-1])[0]) <= BRIDGE_END]
            else:
                kept = []
        accepted["top"] += kept
        occ |= rasterize(kept, I.h, I.w)
    for layer in ("mid", "inner"):
        kept = dedupe(pools[layer], occ, DEDUP)
        accepted[layer] = kept
        occ |= rasterize(kept, I.h, I.w)
    lines = accepted["top"] + accepted["mid"] + accepted["inner"]
    stats["extended"] = close_free_ends(lines, I.color_edges, I.h, I.w)
    stats["candidateLength"] = {k: round(sum(length(L) for L in v), 1) for k, v in accepted.items()}
    by_src = {}
    for L in accepted["top"]:
        by_src[L.source] = by_src.get(L.source, 0.0) + length(L)
    stats["topLengthBySource"] = {k: round(v, 1) for k, v in sorted(by_src.items())}
    return lines, stats


# ---------------------------------------------------------------------------------------------
# Cells


def make_cells(I, walls: np.ndarray, merge_color: bool) -> tuple[SimpleNamespace, dict]:
    pic = I.pic
    ink = ndi.binary_dilation(walls, structure=np.ones((3, 3), bool))
    color = np.where(walls, -1, pic.raster).astype(np.int16)
    color = cc.snap_thin_near_walls(color, walls, radius=2, band=2.5)
    lab, col = cc.components(color)
    reg = finish(lab, col, pic, SimpleNamespace(ink=ink, walls=walls))
    stats = dict(reg.cells)
    lab, color, open_lab = reg.lab.copy(), reg.color.copy(), reg.open_lab.copy()
    pal = pic.palette_lab
    eyes_m = eye_mask(I, 1.0)
    # no cell below its number's size (cells inside an eye box excepted)
    merged_tiny = 0
    for _ in range(4):
        n = len(color)
        room, _, area = cc.rooms(lab, n, ink)
        need = np.array([cc.min_radius(cc.digit_count(c + 1)) for c in color])
        inside = np.bincount(lab[eyes_m], minlength=n)[:n] if eyes_m.any() else np.zeros(n)
        protected = inside >= 0.5 * np.maximum(area, 1)
        tiny = [k for k in np.argsort(room, kind="stable").tolist() if room[k] < need[k] and not protected[k]]
        if not tiny:
            break
        adj = cc.adjacency(lab)
        target = np.arange(n)
        for k in tiny:
            nb = adj.get(k, {})
            if not nb:
                continue
            best = min(sorted(nb), key=lambda b: (float(np.linalg.norm(pal[color[b]] - pal[color[k]])), -nb[b]))
            t = best
            while target[t] != t:
                t = target[t]
            if t != k:
                target[k] = t
                merged_tiny += 1
        lut = np.array([_root(target, k) for k in range(n)])
        lab, open_lab, color = _apply_lut(lab, open_lab, color, lut)
    stats["tinyMergedAcrossLine"] = merged_tiny
    merged_close = 0
    if merge_color:
        T = MERGE_STEPS * panels.palette_step(pal)
        stats["mergeThreshold"] = round(T, 4)
        for _ in range(12):
            n = len(color)
            area = np.bincount(lab.ravel(), minlength=n)
            adj = cc.adjacency(open_lab)
            pairs = sorted((float(np.linalg.norm(pal[color[a]] - pal[color[b]])), a, b)
                           for a in adj for b in adj[a] if a < b)
            target = np.arange(n)
            did = 0
            for de, a, b in pairs:
                if de > T:
                    break
                ra, rb = _root(target, a), _root(target, b)
                if ra == rb or float(np.linalg.norm(pal[color[ra]] - pal[color[rb]])) > T:
                    continue
                big, small = (ra, rb) if area[ra] >= area[rb] else (rb, ra)
                target[small] = big
                area[big] += area[small]
                did += 1
            if not did:
                break
            merged_close += did
            lut = np.array([_root(target, k) for k in range(n)])
            lab, open_lab, color = _apply_lut(lab, open_lab, color, lut)
    stats["closeColorsMerged"] = merged_close
    return SimpleNamespace(lab=lab, color=color, open_lab=open_lab, absorbed=reg.absorbed, ink=ink), stats


def _root(target, k):
    while target[k] != k:
        k = target[k]
    return k


def _apply_lut(lab, open_lab, color, lut):
    used = np.unique(lut)
    remap = -np.ones(len(lut), np.int64)
    remap[used] = np.arange(len(used))
    full = remap[lut]
    lab = full[lab].astype(np.int32)
    open_lab = np.where(open_lab >= 0, full[np.maximum(open_lab, 0)], -1).astype(np.int32)
    return lab, open_lab, color[used]


def join_same_paint(I, cells, lines: list, join_across) -> tuple[SimpleNamespace, dict]:
    """`joined`: neighbouring cells with the same paint become one cell (one number) unless a
    line of a layer outside ``join_across`` separates them (for `joined`: a top line). A pair
    counts as separated when such a line runs along JOIN_BLOCK px or more of its shared border
    (anything shorter is a junction); joins go longest shared border first and never unite two groups holding a
    separated pair, so no outline ever ends up inside a cell. The lines are kept as they are:
    where a cell was joined, its mid, inner or colour line now runs inside it."""
    lab, color = cells.lab, cells.color
    n = len(color)
    block = rasterize([L for L in lines if L.layer not in join_across], I.h, I.w)
    near = ndi.distance_transform_edt(~block) <= 1.5 if block.any() else np.zeros_like(block)
    keys, flags = [], []
    for a, b, na, nb in ((lab[:, :-1], lab[:, 1:], near[:, :-1], near[:, 1:]),
                         (lab[:-1, :], lab[1:, :], near[:-1, :], near[1:, :])):
        m = a != b
        lo, hi = np.minimum(a[m], b[m]).astype(np.int64), np.maximum(a[m], b[m]).astype(np.int64)
        keys.append(lo * n + hi)
        flags.append(na[m] | nb[m])
    keys, flags = np.concatenate(keys), np.concatenate(flags)
    uk, total = np.unique(keys, return_counts=True)
    blocked = np.zeros(len(uk), np.int64)
    bk, bc = np.unique(keys[flags], return_counts=True)
    blocked[np.searchsorted(uk, bk)] = bc
    lo, hi = uk // n, uk % n
    same = color[lo] == color[hi]
    sep = same & (blocked >= JOIN_BLOCK)
    parent = np.arange(n)
    apart = {k: set() for k in range(n)}
    for a, b in zip(lo[sep].tolist(), hi[sep].tolist()):
        apart[a].add(b)
        apart[b].add(a)
    order = np.argsort(-total[same & ~sep], kind="stable")
    cand = list(zip(lo[same & ~sep][order].tolist(), hi[same & ~sep][order].tolist()))
    joins = 0
    for a, b in cand:
        ra, rb = _root(parent, a), _root(parent, b)
        if ra == rb or any(_root(parent, x) == rb for x in apart[ra]):
            continue
        if len(apart[rb]) > len(apart[ra]):
            ra, rb = rb, ra
        parent[rb] = ra
        apart[ra] |= apart[rb]
        joins += 1
    lut = np.array([_root(parent, k) for k in range(n)])
    used = np.unique(lut)
    remap = -np.ones(n, np.int64)
    remap[used] = np.arange(len(used))
    full = remap[lut]
    out = SimpleNamespace(lab=full[lab].astype(np.int32), color=color[used], ink=cells.ink,
                          absorbed=cells.absorbed,
                          open_lab=np.where(cells.open_lab >= 0, full[np.maximum(cells.open_lab, 0)], -1))
    return out, {"pairsJoined": joins, "regionsBefore": int(n), "separatedSamePaintPairs": int(sep.sum())}


def inside_cells(lines: list, cells) -> dict:
    """Length of line, per layer, whose two sides lie in the same cell (a line inside a cell)."""
    out = {k: 0.0 for k in LAYERS}
    for L in lines:
        if len(L.pts) < 2:
            continue
        nrm = st._normals(L.pts, L.closed)
        a = sample(cells.lab, L.pts + 1.5 * nrm)
        b = sample(cells.lab, L.pts - 1.5 * nrm)
        out[L.layer] += length(L) * float(np.mean(a == b))
    return {k: round(v, 1) for k, v in out.items()}


# ---------------------------------------------------------------------------------------------
# Trimming and colour lines


def boundary_pixels(lab: np.ndarray) -> np.ndarray:
    b = np.zeros(lab.shape, bool)
    dr, dd = lab[:, :-1] != lab[:, 1:], lab[:-1, :] != lab[1:, :]
    b[:, :-1] |= dr; b[:, 1:] |= dr; b[:-1, :] |= dd; b[1:, :] |= dd
    return b


def clean_runs(keep: np.ndarray, a: np.ndarray, closed: bool) -> np.ndarray:
    keep = keep.copy()
    for flag, minlen in ((False, TRIM_MIN), (True, TRIM_MIN)):
        for i0, i1 in runs(keep == flag):
            interior = closed or (i0 > 0 and i1 < len(keep) - 1)
            if a[i1] - a[i0] < minlen and (interior or flag):
                keep[i0:i1 + 1] = not flag
    return keep


def trim(lines: list, lab: np.ndarray) -> tuple[list, dict]:
    """Keeps only the parts of lines that run along a cell boundary."""
    dt = ndi.distance_transform_edt(~boundary_pixels(lab))
    out = []
    before = {k: 0.0 for k in LAYERS}
    after = {k: 0.0 for k in LAYERS}
    for L in lines:
        a = arclen(L.pts)
        before[L.layer] += length(L)
        keep = clean_runs(sample(dt, L.pts) <= TRIM_NEAR, a, L.closed)
        if keep.all():
            out.append(L)
            after[L.layer] += length(L)
            continue
        pts, links = L.pts, L.links
        if L.closed:
            s = int(np.argmin(keep))
            pts = np.roll(pts, -s, axis=0)
            links = [((i - s) % len(L.pts), qx, qy) for i, qx, qy in links]
            keep = np.roll(keep, -s)
        tmp = Line(pts, False, L.layer, L.source, L.free, links, L.w)
        for i0, i1 in runs(keep):
            if i1 <= i0:
                continue
            P = Line(pts[i0:i1 + 1].copy(), False, L.layer, L.source, (True, True), _sub_links(tmp, i0, i1), L.w)
            out.append(P)
            after[L.layer] += length(P)
    return out, {"before": before, "after": after}


def color_lines(lab: np.ndarray, drawn: np.ndarray) -> list:
    """Cell boundaries no drawn line covers, traced at 2x and smoothed."""
    lab2 = panels.up2(lab)
    b = np.zeros(lab2.shape, bool)
    b[:, :-1] |= lab2[:, :-1] != lab2[:, 1:]
    b[:-1, :] |= lab2[:-1, :] != lab2[1:, :]
    near = ndi.distance_transform_edt(~panels.up2(drawn)) <= 2 * COLOR_CLEAR
    b &= ~near
    if not b.any():
        return []
    skel = morphology.skeletonize(b)
    g = st.trace(skel)
    g.merge_degree2()
    st.prune_spurs(g, 3, rounds=1)
    out = []
    for s in st.build_strokes(g):
        p = s["pts"]
        if len(p) < 2 and not s["closed"]:
            continue
        d = st._gauss_smooth(p.astype(float), 3.0, s["closed"]) / 2.0
        if length(Line(d, s["closed"], "color", "color")) < 1.5:
            continue
        out.append(Line(d, bool(s["closed"]), "color", "cells", tuple(s["free"])))
    # reattach ends to the drawn lines they stop short of
    if drawn.any() and out:
        dt, ind = ndi.distance_transform_edt(~drawn, return_indices=True)
        for L in out:
            if L.closed:
                continue
            for end in (0, 1):
                p = L.pts[0] if end == 0 else L.pts[-1]
                y = int(np.clip(round(p[1]), 0, lab.shape[0] - 1)); x = int(np.clip(round(p[0]), 0, lab.shape[1] - 1))
                if dt[y, x] <= COLOR_CLEAR + 2.0:
                    q = np.array([ind[1][y, x], ind[0][y, x]], float)
                    L.pts = np.vstack([q, L.pts]) if end == 0 else np.vstack([L.pts, q])
    return out


def weigh(L: Line, I, cells=None) -> float:
    pts = L.pts
    if len(pts) < 2:
        return 0.8
    nrm = st._normals(pts, L.closed)
    if L.layer == "color" and cells is not None:
        ca = sample(cells.lab, pts + 1.5 * nrm)
        cb = sample(cells.lab, pts - 1.5 * nrm)
        pal = I.pic.palette_lab
        de = float(np.median(np.linalg.norm(pal[cells.color[ca]] - pal[cells.color[cb]], axis=1)))
        return float(np.clip(0.5 + 0.7 * min(1.0, de / 0.15), 0.5, 1.2))
    a = st._bilinear(I.lab_smooth, pts + st.SIDE_OFFSET * nrm)
    b = st._bilinear(I.lab_smooth, pts - st.SIDE_OFFSET * nrm)
    contrast = float(np.mean(np.linalg.norm(a - b, axis=1)))
    imp = float(np.mean(st._bilinear(I.imp, pts)))
    c = min(1.0, contrast / st.CONTRAST_REF) ** 0.7
    lf = 0.85 + 0.15 * min(1.0, length(L) / 150.0)
    # an inker's rule: the line around a dark mass is heavier than one between two light tones
    # (the cypress against the sky vs the edges between Van Gogh's clouds)
    dark = float(np.mean(np.minimum(a[:, 0], b[:, 0])))
    df = 0.75 + 0.5 * float(np.clip((DARK_LIGHT - dark) / (DARK_LIGHT - DARK_HEAVY), 0, 1))
    wv = (st.W_MIN + (st.W_MAX - st.W_MIN) * c) * (0.7 + 0.3 * imp) * lf * df / 1.6
    if L.source in ("silhouette", "eye"):
        wv = max(wv, 0.9)
    elif L.layer == "top":
        wv = max(wv, 0.75)      # an outline reads at 1x even where its edge is soft
    return float(np.clip(wv, 0.5, 1.3))


# ---------------------------------------------------------------------------------------------
# Numbers


def numbers(cells, w: int, h: int) -> list:
    labels = panels.labels_for(cells.lab, cells.color, cells.ink, max(h, w))
    out = []
    maximum = max(h, w) / 64
    css_per_px = PHONE_CSS / w
    for x, y, r, k in labels:
        text = str(int(cells.color[k]) + 1)
        fs = cc.font_size(r, len(text), maximum)
        minzoom = LEGIBLE_CSS / (fs * cc.DIGIT_HEIGHT * css_per_px)
        out.append(dict(x=float(x), y=float(y), fs=float(fs), text=text, minzoom=float(minzoom), cell=int(k)))
    return out


# ---------------------------------------------------------------------------------------------
# SVG


def fmt(v: float) -> str:
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


def path_d(L: Line, eps: float = 0.3) -> str:
    p = L.pts + 0.5     # pixel centres -> SVG user units (pixel i spans [i, i + 1])
    keep = st._rdp_closed(p, eps) if L.closed else st._rdp(p, eps)
    q = p[keep]
    parts = ["M" + fmt(q[0, 0]) + " " + fmt(q[0, 1])]
    parts += ["L" + fmt(x) + " " + fmt(y) for x, y in q[1:]]
    if len(q) == 1:
        parts.append("L" + fmt(q[0, 0] + 0.01) + " " + fmt(q[0, 1]))
    return "".join(parts) + ("Z" if L.closed else "")


def interp(vals, z: float) -> float:
    t = math.log2(max(min(z, 4.0), 1.0))
    i = min(int(t), 1)
    return vals[i] + (vals[i + 1] - vals[i]) * (t - i)


def svg_text(lines_by_layer: dict, nums: list, W: int, H: int, base: dict, viewbox=None, background=None,
             zoom=None, preset=None, layers=LAYERS, show_numbers=True, colors=None) -> str:
    vb = viewbox or (0, 0, W, H)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{fmt(vb[0])} {fmt(vb[1])} {fmt(vb[2])} {fmt(vb[3])}" '
           f'width="{fmt(vb[2])}" height="{fmt(vb[3])}">']
    if background:
        out.append(f'<rect x="{fmt(vb[0])}" y="{fmt(vb[1])}" width="{fmt(vb[2])}" height="{fmt(vb[3])}" fill="{background}"/>')
    for layer in ["color", "inner", "mid", "top"]:
        if layer not in layers:
            continue
        ink = colors[layer] if colors else INK
        attrs = f'id="{layer}" fill="none" stroke="{ink}" stroke-linecap="round" stroke-linejoin="round" data-base="{base[layer]:.3f}"'
        mult = 1.0
        if zoom is not None:
            op = interp(preset[layer]["opacity"], zoom)
            mult = interp(preset[layer]["width"], zoom)
            attrs += f' opacity="{op:.3f}"'
        out.append(f"<g {attrs}>")
        for L, d in lines_by_layer.get(layer, []):
            wv = L.w if (preset is None or preset.get("weighted", True)) else 1.0
            sw = base[layer] * wv * mult
            out.append(f'<path d="{d}" stroke-width="{sw:.2f}" data-w="{L.w:.2f}"/>')
        out.append("</g>")
    if show_numbers:
        out.append(f'<g id="numbers" font-family="Source Serif 4, New York, serif" fill="{NUMBER_INK}" text-anchor="middle">')
        for n in nums:
            if zoom is not None and n["minzoom"] > zoom:
                continue
            if viewbox and not (vb[0] - 20 < n["x"] < vb[0] + vb[2] + 20 and vb[1] - 20 < n["y"] < vb[1] + vb[3] + 20):
                continue
            baseline = n["y"] + cc.DIGIT_HEIGHT * n["fs"] / 2
            out.append(f'<text x="{fmt(n["x"])}" y="{baseline:.2f}" font-size="{n["fs"]:.2f}" '
                       f'data-minzoom="{n["minzoom"]:.2f}">{n["text"]}</text>')
        out.append("</g>")
    out.append("</svg>")
    return "\n".join(out)


def render_jobs(jobs: list, tmp_dir: str) -> None:
    script = os.path.join(NODE_DIR, "svg_render.mjs")
    src = os.path.join(HERE, "svg_render.mjs")
    if not os.path.exists(script) or open(script).read() != open(src).read():
        shutil.copy(src, script)
    jf = os.path.join(tmp_dir, f"_jobs_{os.getpid()}.json")
    for j in jobs:
        j.setdefault("font", FONT)
    json.dump(jobs, open(jf, "w"))
    subprocess.run([NODE, script, jf], check=True, cwd=NODE_DIR)
    os.remove(jf)


def crop_rect(I, z: int) -> tuple:
    cx, cy = CROPS[I.name][f"z{z}"]
    cw, ch = I.w / z, I.h / z
    x = min(max(cx - cw / 2, 0), I.w - cw)
    y = min(max(cy - ch / 2, 0), I.h - ch)
    return (round(x, 1), round(y, 1), round(cw, 1), round(ch, 1))


def save_jpg(path: str, rgb, quality: int = 85) -> None:
    im = rgb if isinstance(rgb, Image.Image) else Image.fromarray(np.clip(np.rint(rgb), 0, 255).astype(np.uint8))
    im.convert("RGB").save(path, quality=quality, optimize=True)


def png_to_jpg(png: str, jpg: str, background=(255, 255, 255)) -> None:
    im = Image.open(png)
    if im.mode == "RGBA":
        bg = Image.new("RGB", im.size, background)
        bg.paste(im, mask=im.split()[3])
        im = bg
    save_jpg(jpg, im)
    os.remove(png)


# ---------------------------------------------------------------------------------------------
# Finished and flat


def finished_and_flat(I, cells, drawn: np.ndarray):
    pic = I.pic
    paint = cells.color[cells.lab]
    c2x = panels.smooth_colors_2x(paint, drawn)
    flat_rgb = pic.palette[c2x]
    flat = pic.palette_lab[c2x]
    barrier = panels.up2(drawn)
    free_step = FINISH_FREE_STEPS * panels.palette_step(pic.palette_lab)
    wide = cc.domain_transform(flat, flat, barrier, 2 * FINISH_SIGMA, 0.07, free_step=free_step)
    near = cc.domain_transform(flat, flat, barrier, 6.0, 0.07, free_step=free_step)
    wgt = cv2.resize(panels.detail_weight(SimpleNamespace(lab=cells.lab, color=cells.color)),
                     (flat.shape[1], flat.shape[0]), interpolation=cv2.INTER_LINEAR)
    soft = near + wgt[..., None] * (wide - near)
    soft = cv2.GaussianBlur(soft, (0, 0), 0.6)
    return cc.oklab_to_srgb8(soft), flat_rgb, soft


# ---------------------------------------------------------------------------------------------
# Driver


def run_variant(I, src: dict, vname: str) -> dict:
    spec = VARIANTS[vname]
    t0 = time.time()
    vdir = os.path.join(I.odir, vname)
    os.makedirs(vdir, exist_ok=True)
    lines, astats = assemble(I, src, spec)
    walls = rasterize(lines, I.h, I.w)
    cells, cstats = make_cells(I, walls, spec["merge_color"])
    kept, tstats = trim(lines, cells.lab)
    drawn = rasterize(kept, I.h, I.w)
    clines = color_lines(cells.lab, drawn)
    allines = kept + clines
    for L in allines:
        L.w = weigh(L, I, cells)
    jstats = None
    if spec.get("join_across"):
        prejoin = cells
        cells, jstats = join_same_paint(I, prejoin, allines, spec["join_across"])
        # the alternative: mid lines also keep cells apart (join across inner and colour only)
        alt, _ = join_same_paint(I, prejoin, allines, tuple(k for k in spec["join_across"] if k != "mid"))
        jstats["regionsIfMidAlsoSplits"] = int(len(alt.color))
        jstats["lineLengthInsideCells"] = inside_cells(allines, cells)
        # the same measure before joining: sampling near junctions and line ends counts ~2 %
        jstats["lineLengthInsideCellsBeforeJoin"] = inside_cells(allines, prejoin)
    nums = numbers(cells, I.w, I.h)
    t_cells = time.time() - t0
    base = {k: CSS_WIDTH[k] * I.w / PHONE_CSS for k in LAYERS}
    by_layer = {k: [(L, path_d(L)) for L in allines if L.layer == k] for k in LAYERS}
    svg = svg_text(by_layer, nums, I.w, I.h, base)
    open(os.path.join(vdir, "lines.svg"), "w").write(svg)
    # static renders
    jobs = []
    preset = PRESETS[DEFAULT_PRESET]
    views = {1: None, 2: crop_rect(I, 2), 4: crop_rect(I, 4)}
    for z, vb in views.items():
        sp = os.path.join(vdir, f"_z{z}.svg")
        open(sp, "w").write(svg_text(by_layer, nums, I.w, I.h, base, viewbox=vb, background=PAPER, zoom=z,
                                     preset=preset))
        jobs.append(dict(svg=sp, png=os.path.join(vdir, f"_z{z}.png"), width=RENDER_WIDTH, background=PAPER))
    ink_svg = os.path.join(vdir, "_ink.svg")
    open(ink_svg, "w").write(svg_text(by_layer, nums, I.w, I.h, base, zoom=1.0, preset=preset,
                                      layers=["top", "mid", "inner"], show_numbers=False))
    jobs.append(dict(svg=ink_svg, png=os.path.join(vdir, "_ink.png"), width=2 * I.w, background=None))
    if os.environ.get("LAYERS_DEBUG"):
        dbg = {"top": "#111111", "mid": "#1f5fd6", "inner": "#1a9c3a", "color": "#f08a24"}
        look = os.path.join(OUT, "_look")
        for z, vb in ((1, None), (2, views[2]), (4, views[4])):
            sp = os.path.join(vdir, f"_dbg{z}.svg")
            open(sp, "w").write(svg_text(by_layer, nums, I.w, I.h, base, viewbox=vb, background="#ffffff",
                                         show_numbers=False, colors=dbg, zoom=z,
                                         preset={k: {"opacity": [1, 1, 1], "width": PRESETS["fade"][k]["width"]}
                                                 for k in LAYERS} | {"weighted": True}))
            jobs.append(dict(svg=sp, png=os.path.join(look, f"{I.name}-{vname}-dbg{z}.png"), width=1400 if z == 1 else RENDER_WIDTH,
                             background="#ffffff"))
    render_jobs(jobs, vdir)
    for f in os.listdir(vdir):
        if f.startswith("_dbg"):
            os.remove(os.path.join(vdir, f))
    for z in views:
        png_to_jpg(os.path.join(vdir, f"_z{z}.png"), os.path.join(vdir, f"z{z}.jpg"))
        os.remove(os.path.join(vdir, f"_z{z}.svg"))
    t_render = time.time() - t0 - t_cells
    fin, flat_rgb, soft = finished_and_flat(I, cells, drawn)
    ink = np.asarray(Image.open(os.path.join(vdir, "_ink.png")).convert("RGBA"))
    os.remove(os.path.join(vdir, "_ink.png")); os.remove(ink_svg)
    save_jpg(os.path.join(vdir, "flat.jpg"), flat_rgb)
    save_jpg(os.path.join(vdir, "finished.jpg"), panels.over(fin.astype(np.float32), ink))
    t_finish = time.time() - t0 - t_cells - t_render
    m = metrics(I, cells, cstats, astats, tstats, by_layer, nums, svg, src)
    m["seconds"] = {"linesAndCells": round(t_cells, 2), "renders": round(t_render, 2),
                    "finishedAndFlat": round(t_finish, 2),
                    "sources": {k[:-8]: v for k, v in src.items() if k.endswith("_seconds")}}
    m["variant"] = vname
    if jstats:
        m["joined"] = jstats
    json.dump(m, open(os.path.join(vdir, "metrics.json"), "w"), indent=1)
    return m


def metrics(I, cells, cstats, astats, tstats, by_layer, nums, svg, src) -> dict:
    n = len(cells.color)
    room, _, area = cc.rooms(cells.lab, n, cells.ink)
    need = np.array([cc.min_radius(cc.digit_count(c + 1)) for c in cells.color])
    rank = {"top": 3, "mid": 2, "inner": 1, "color": 0}
    strongest = np.full(n, -1)
    for layer, items in by_layer.items():
        for L, _ in items:
            if len(L.pts) < 2:
                continue
            nrm = st._normals(L.pts, L.closed)
            for sgn in (1.5, -1.5):
                ks = np.unique(sample(cells.lab, L.pts + sgn * nrm))
                strongest[ks] = np.maximum(strongest[ks], rank[layer])
    names = {3: "top", 2: "mid", 1: "inner", 0: "color", -1: "none"}
    by_strongest = {names[r]: int((strongest == r).sum()) for r in (3, 2, 1, 0, -1)}
    lens = {k: round(sum(length(L) for L, _ in v), 1) for k, v in by_layer.items()}
    tot = sum(lens.values()) or 1.0
    mz = np.array([x["minzoom"] for x in nums]) if nums else np.zeros(0)
    # cells that exist only because a line splits one paint (joined, they would be one cell)
    parent = np.arange(n)
    adj = cc.adjacency(cells.lab)
    for a_, nb in adj.items():
        for b_ in nb:
            if cells.color[a_] == cells.color[b_]:
                ra, rb = _root(parent, a_), _root(parent, b_)
                if ra != rb:
                    parent[max(ra, rb)] = min(ra, rb)
    same_paint = n - len({_root(parent, k) for k in range(n)})
    return {
        "regions": int(n),
        "todayRegions": int(I.pic.stats.get("regions", 0)),
        "regionsVsToday": round(n / max(I.pic.stats.get("regions", 1), 1), 3),
        "cellsByStrongestBoundaryLayer": by_strongest,
        "samePaintSplits": int(same_paint),
        "strokesPerLayer": {k: len(v) for k, v in by_layer.items()},
        "lineLengthPerLayer": lens,
        "lineShare": {k: round(v / tot, 3) for k, v in lens.items()},
        "drawnLengthKeptAfterTrim": {k: round(tstats["after"][k] / tstats["before"][k], 3)
                                     for k in ("top", "mid", "inner") if tstats["before"][k] > 0},
        "smallestCellRoom": round(float(room.min()), 2) if n else 0,
        "cellsBelowNumberSize": int((room < need).sum()),
        "minimumRadius": round(cc.MIN_LABEL_RADIUS, 2),
        "cells": cstats,
        "assembly": astats,
        "numbers": {"count": len(nums), "legibleAt1x": int((mz <= 1).sum()), "legibleAt2x": int((mz <= 2).sum()),
                    "legibleAt4x": int((mz <= 4).sum()), "medianMinZoom": round(float(np.median(mz)), 2) if len(mz) else None},
        "subject": src["silhouette_info"],
        "eyes": I.eyes,
        "faces": I.faces,
        "svgBytes": len(svg.encode()),
    }


def picture_files(I) -> None:
    """photo.jpg, today_template.jpg, today_painted.jpg (1600 px) and today_z2/z4.jpg."""
    photo = Image.open(os.path.join(I.dir, "working.ppm")).convert("RGB")
    photo.resize((1600, round(1600 * I.h / I.w)), Image.Resampling.LANCZOS).save(
        os.path.join(I.odir, "photo.jpg"), quality=88, optimize=True)
    jobs = []
    tsvg = open(os.path.join(I.dir, "template.svg")).read()
    for name, svgname, vb, width in (("today_template", "template.svg", None, 1600),
                                     ("today_painted", "painted.svg", None, 1600),
                                     ("today_z2", "template.svg", crop_rect(I, 2), RENDER_WIDTH),
                                     ("today_z4", "template.svg", crop_rect(I, 4), RENDER_WIDTH)):
        text = tsvg if svgname == "template.svg" else open(os.path.join(I.dir, svgname)).read()
        if vb:
            text = re.sub(r'viewBox="[^"]*" width="[^"]*" height="[^"]*"',
                          f'viewBox="{vb[0]} {vb[1]} {vb[2]} {vb[3]}" width="{vb[2]}" height="{vb[3]}"', text, count=1)
        sp = os.path.join(I.odir, f"_{name}.svg")
        open(sp, "w").write(text)
        jobs.append(dict(svg=sp, png=os.path.join(I.odir, f"_{name}.png"), width=width, background="#ffffff"))
    render_jobs(jobs, I.odir)
    for j in jobs:
        png_to_jpg(j["png"], j["png"].replace("/_", "/").replace(".png", ".jpg"))
        os.remove(j["svg"])


def run_picture(args) -> str:
    pic_name, variants = args
    t0 = time.time()
    I = load_inputs(pic_name)
    src = build_sources(I)
    picture_files(I)
    lines = []
    for v in variants:
        m = run_variant(I, src, v)
        lines.append(f"{pic_name:18s} {v:13s} regions {m['regions']:5d} (today {m['todayRegions']}) "
                     f"strokes {m['strokesPerLayer']} below {m['cellsBelowNumberSize']} "
                     f"t {m['seconds']['linesAndCells']}+{m['seconds']['renders']}+{m['seconds']['finishedAndFlat']}s")
    return "\n".join(lines) + f"\n{pic_name}: {time.time() - t0:.0f} s"


# ---------------------------------------------------------------------------------------------
# Manifest


def manifest(notes_path: str = os.path.join(HERE, "layers_notes.json")) -> dict:
    notes = json.load(open(notes_path)) if os.path.exists(notes_path) else {}
    pics = []
    for name in ORDER:
        pdir = os.path.join(OUT, name)
        if not os.path.exists(os.path.join(pdir, "photo.jpg")) or not all(
                os.path.exists(os.path.join(pdir, v, "metrics.json")) for v in VARIANTS):
            continue        # only pictures with every variant done
        pic = cc.load_picture(os.path.join(INPUTS, name))
        I = SimpleNamespace(name=name, w=pic.width, h=pic.height)
        entry = {"id": name, "title": TITLES[name], "size": [pic.width, pic.height], "photo": f"{name}/photo.jpg",
                 "today": {"template": f"{name}/today_template.jpg", "painted": f"{name}/today_painted.jpg",
                           "z2": f"{name}/today_z2.jpg", "z4": f"{name}/today_z4.jpg",
                           "regions": int(pic.stats["regions"])},
                 "crops": {"z2": list(crop_rect(I, 2)), "z4": list(crop_rect(I, 4))},
                 "note": notes.get(name, {}).get("_picture", ""), "variants": []}
        for v, spec in VARIANTS.items():
            vdir = os.path.join(pdir, v)
            mf = os.path.join(vdir, "metrics.json")
            if not os.path.exists(mf):
                continue
            m = json.load(open(mf))
            entry["variants"].append({
                "id": v, "label": spec["label"], "note": notes.get(name, {}).get(v, ""),
                "svg": f"{name}/{v}/lines.svg", "flat": f"{name}/{v}/flat.jpg", "finished": f"{name}/{v}/finished.jpg",
                "renders": {f"z{z}": f"{name}/{v}/z{z}.jpg" for z in (1, 2, 4)},
                "metrics": {k: m[k] for k in ("regions", "todayRegions", "regionsVsToday", "samePaintSplits", "strokesPerLayer",
                                              "lineShare", "cellsByStrongestBoundaryLayer", "cellsBelowNumberSize",
                                              "smallestCellRoom", "numbers", "seconds")} | (
                    {"joined": m["joined"]} if "joined" in m else {}),
            })
        pics.append(entry)
    man = {"render_presets": {k: {kk: vv for kk, vv in p.items()} for k, p in PRESETS.items()},
           "default_preset": DEFAULT_PRESET,
           "render_notes": {
               "zoom": "1 = the whole picture fits a phone 390 CSS px wide; presets give values at zoom 1, 2, 4 "
                       "(interpolate in log2(zoom), clamp outside)",
               "width": "drawn width (working px) = path stroke-width x preset width multiplier; with "
                        "weighted false use the group's data-base instead of the path's stroke-width; "
                        "on screen: width x zoom x 390 / W CSS px",
               "numbers": "text x is the centre, y the baseline; show when zoom >= data-minzoom (digits "
                          f"{LEGIBLE_CSS:g} CSS px tall); font-size in working px",
               "colors": {"paper": PAPER, "ink": INK, "numbers": NUMBER_INK}},
           "pictures": pics}
    return man


def validate(man: dict) -> list:
    problems = []
    for p in man["pictures"]:
        files = [p["photo"]] + [p["today"][k] for k in ("template", "painted", "z2", "z4")]
        for v in p["variants"]:
            files += [v["svg"], v["flat"], v["finished"]] + list(v["renders"].values())
        for f in files:
            path = os.path.join(OUT, f)
            if not os.path.exists(path):
                problems.append("missing " + f)
                continue
            try:
                if f.endswith(".svg"):
                    import xml.etree.ElementTree as ET
                    root = ET.parse(path).getroot()
                    ids = {g.get("id") for g in root.iter("{http://www.w3.org/2000/svg}g")}
                    if not {"top", "mid", "inner", "color", "numbers"} <= ids:
                        problems.append(f"{f}: groups {sorted(i for i in ids if i)}")
                    if os.path.getsize(path) > 2_500_000:
                        problems.append(f"{f}: {os.path.getsize(path)} bytes")
                else:
                    Image.open(path).load()
            except Exception as e:     # report, keep checking
                problems.append(f"{f}: {type(e).__name__}: {e}")
    return problems


def report() -> str:
    """Markdown tables of the metrics (results_layers.md)."""
    rows = ["| picture | today | recommended | no-closure | hed-layers | merged-color |", "|---|---:|---:|---:|---:|---:|"]
    detail = ["| picture | variant | cells | same-paint splits | cells by strongest boundary (top / mid / inner / color) | "
              "line length share (top / mid / inner / color) | drawn kept after trim (top / mid / inner) | "
              "numbers legible at 2x / 4x / all | svg KB | s |", "|---|---|---:|---:|---|---|---|---|---:|---:|"]
    for name in ORDER:
        ms = {}
        for v in VARIANTS:
            f = os.path.join(OUT, name, v, "metrics.json")
            if os.path.exists(f):
                ms[v] = json.load(open(f))
        if len(ms) < len(VARIANTS):
            continue
        today = ms["recommended"]["todayRegions"]
        rows.append(f"| {name} | {today} | " + " | ".join(
            f"{ms[v]['regions']} ({ms[v]['regionsVsToday']:.2f}x)" for v in VARIANTS) + " |")
        for v, m in ms.items():
            cb, ls, kt, nu = m["cellsByStrongestBoundaryLayer"], m["lineShare"], m["drawnLengthKeptAfterTrim"], m["numbers"]
            s = m["seconds"]
            detail.append(
                f"| {name} | {v} | {m['regions']} | {m['samePaintSplits']} | {cb['top']} / {cb['mid']} / {cb['inner']} / {cb['color']} | "
                f"{ls['top']:.2f} / {ls['mid']:.2f} / {ls['inner']:.2f} / {ls['color']:.2f} | "
                f"{kt.get('top', 0):.2f} / {kt.get('mid', 0):.2f} / {kt.get('inner', 0):.2f} | "
                f"{nu['legibleAt2x']} / {nu['legibleAt4x']} / {nu['count']} | {m['svgBytes'] // 1024} | "
                f"{s['linesAndCells']:.0f}+{s['renders']:.0f}+{s['finishedAndFlat']:.0f} |")
    return "\n".join(rows) + "\n\n" + "\n".join(detail)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pics", nargs="*")
    ap.add_argument("--variants", default=",".join(VARIANTS))
    ap.add_argument("--jobs", type=int, default=1)
    ap.add_argument("--manifest", action="store_true", help="write and validate manifest.json")
    ap.add_argument("--report", action="store_true", help="print the metrics as markdown tables")
    a = ap.parse_args()
    if a.report:
        print(report())
    if a.pics:
        work = [(p, a.variants.split(",")) for p in a.pics]
        if a.jobs > 1:
            from multiprocessing import Pool
            with Pool(a.jobs) as pool:
                for line in pool.imap_unordered(run_picture, work):
                    print(line, flush=True)
        else:
            for w in work:
                print(run_picture(w), flush=True)
    if a.manifest:
        man = manifest()
        json.dump(man, open(os.path.join(OUT, "manifest.json"), "w"), indent=1, ensure_ascii=False)
        probs = validate(man)
        print(f"manifest: {len(man['pictures'])} pictures, "
              f"{sum(len(p['variants']) for p in man['pictures'])} variants, problems: {probs or 'none'}")


if __name__ == "__main__":
    main()
