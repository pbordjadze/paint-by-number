"""Shared pieces of stage 2 (color inside the lines): IO, OKLab, region bookkeeping.

Conventions (shared with stage 1's contract):
- Everything is at pbn's working resolution unless a name says ``2x``.
- ``walls`` is a bool map of stroke centerlines (8-connected, 1 px). Color regions are
  4-connected components of non-wall pixels, so an open stroke is a wall along its length and a
  region may wrap around its free end.
- A "color image" is an int16 map of palette indices with -1 on walls.
- Numbers are palette index + 1, as pbn numbers them.
"""

from __future__ import annotations

import heapq
import json
import math
import os
from dataclasses import dataclass, field

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

# LabelSizing (Sources/PaintCore/Model/Template.swift), canvas units = working pixels.
DIGIT_ADVANCE = 0.6
DIGIT_HEIGHT = 0.72
LABEL_FILL = 0.85
MIN_LABEL_RADIUS = 2.12

PAPER = (0xF4, 0xEF, 0xE6)
FOUR = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], dtype=bool)


def digit_count(number: int) -> int:
    return len(str(max(int(number), 1)))


def run_diagonal(digits: int) -> float:
    w = DIGIT_ADVANCE * max(digits, 1)
    return math.hypot(w, DIGIT_HEIGHT)


def min_radius(digits: int) -> float:
    """LabelSizing.minimumRadius(digits:)."""
    return MIN_LABEL_RADIUS * run_diagonal(digits) / run_diagonal(1)


def font_size(radius: float, digits: int, maximum: float = math.inf) -> float:
    """LabelSizing.fontSize(radius:digits:maximum:) in canvas units (em size)."""
    fitted = 2 * radius * LABEL_FILL / run_diagonal(digits)
    floor = 2 * MIN_LABEL_RADIUS * LABEL_FILL / run_diagonal(1)
    return max(min(fitted, maximum), floor)


# ---------------------------------------------------------------------------------------------
# Color science


def srgb_to_oklab(rgb: np.ndarray) -> np.ndarray:
    """uint8 or 0..1 float sRGB (..., 3) -> OKLab float32 (..., 3)."""
    c = rgb.astype(np.float64)
    if rgb.dtype == np.uint8:
        c = c / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = np.cbrt(l), np.cbrt(m), np.cbrt(s)
    out = np.stack([
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    ], axis=-1)
    return out.astype(np.float32)


def oklab_to_srgb8(lab: np.ndarray) -> np.ndarray:
    L, a, b = (lab[..., i].astype(np.float32) for i in range(3))
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    rgb = np.stack([
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    ], axis=-1)
    rgb = np.clip(rgb, 0, 1)
    srgb = np.where(rgb <= 0.0031308, 12.92 * rgb, 1.055 * np.power(rgb, np.float32(1 / 2.4)) - 0.055)
    return np.clip(np.round(srgb * 255), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------------------------------------
# Inputs


@dataclass
class Picture:
    name: str
    dir: str
    photo: np.ndarray            # HxWx3 uint8 (working.ppm)
    raster: np.ndarray           # HxW int16 palette index (raster.ppm)
    palette: np.ndarray          # Nx3 uint8, pbn's order
    stats: dict

    @property
    def height(self) -> int:
        return self.photo.shape[0]

    @property
    def width(self) -> int:
        return self.photo.shape[1]

    @property
    def palette_lab(self) -> np.ndarray:
        return srgb_to_oklab(self.palette)

    @property
    def photo_lab(self) -> np.ndarray:
        return srgb_to_oklab(self.photo)


def load_picture(pic_dir: str) -> Picture:
    pic_dir = os.path.abspath(pic_dir)
    stats = json.load(open(os.path.join(pic_dir, "stats.json")))
    photo = np.asarray(Image.open(os.path.join(pic_dir, "working.ppm")).convert("RGB"))
    rast = np.asarray(Image.open(os.path.join(pic_dir, "raster.ppm")).convert("RGB"))
    palette = np.array([[int(h[i:i + 2], 16) for i in (0, 2, 4)] for h in stats["palette"]], dtype=np.uint8)
    key = (rast[..., 0].astype(np.int32) << 16) | (rast[..., 1].astype(np.int32) << 8) | rast[..., 2]
    pkey = (palette[:, 0].astype(np.int32) << 16) | (palette[:, 1].astype(np.int32) << 8) | palette[:, 2]
    order = np.argsort(pkey, kind="stable")
    pos = np.searchsorted(pkey[order], key)
    pos = np.clip(pos, 0, len(pkey) - 1)
    idx = order[pos]
    if not np.all(pkey[idx] == key):
        raise ValueError(f"{pic_dir}: raster.ppm has colors outside the palette")
    return Picture(os.path.basename(pic_dir), pic_dir, photo, idx.astype(np.int16), palette, stats)


@dataclass
class Option:
    dir: str
    walls: np.ndarray            # HxW bool
    ink2x: np.ndarray            # (2H)x(2W)x4 uint8 RGBA, ink to draw on top
    ink: np.ndarray              # HxW bool, pixels whose paint the ink hides (walls included)
    ink_color: tuple = (40, 36, 44)


def ink_mask_from_2x(ink2x: np.ndarray, h: int, w: int) -> np.ndarray:
    a = ink2x[..., 3].astype(np.float32) / 255.0
    a = a[: 2 * h, : 2 * w].reshape(h, 2, w, 2).mean(axis=(1, 3))
    return a >= 0.5


def load_option(opt_dir: str, h: int, w: int, ink_name: str = "ink.png") -> Option:
    opt_dir = os.path.abspath(opt_dir)
    walls = np.asarray(Image.open(os.path.join(opt_dir, "walls.png")).convert("L")) > 127
    if walls.shape != (h, w):
        raise ValueError(f"{opt_dir}: walls.png is {walls.shape[::-1]}, expected {(w, h)}")
    path = os.path.join(opt_dir, ink_name)
    if not os.path.exists(path):
        path = os.path.join(opt_dir, "ink.png")
    if os.path.exists(path):
        ink2x = np.asarray(Image.open(path).convert("RGBA"))
        if ink2x.shape[:2] != (2 * h, 2 * w):
            ink2x = np.asarray(Image.fromarray(ink2x).resize((2 * w, 2 * h), Image.LANCZOS))
    else:
        ink2x = ink_from_walls(walls)
    ink = ink_mask_from_2x(ink2x, h, w) | walls
    solid = ink2x[..., 3] > 230
    color = tuple(int(v) for v in np.median(ink2x[solid][:, :3], axis=0)) if solid.any() else (40, 36, 44)
    return Option(opt_dir, walls, ink2x, ink, color)


def ink_from_walls(walls: np.ndarray, color=(40, 36, 44), width2x: float = 2.0) -> np.ndarray:
    """Plain ink for a wall map when an option has no ink.png (dev walls)."""
    h, w = walls.shape
    up = cv2.resize(walls.astype(np.uint8) * 255, (2 * w, 2 * h), interpolation=cv2.INTER_LINEAR)
    d = ndi.distance_transform_edt(up < 128)
    alpha = np.clip(width2x / 2 + 0.5 - d, 0, 1)
    out = np.zeros((2 * h, 2 * w, 4), np.uint8)
    out[..., :3] = color
    out[..., 3] = np.round(alpha * 255).astype(np.uint8)
    return out


# ---------------------------------------------------------------------------------------------
# Regions


def enclosed_areas(walls: np.ndarray) -> tuple[np.ndarray, int]:
    """4-connected components of non-wall pixels. Returns (labels with 0 on walls, count)."""
    lab, n = ndi.label(~walls, structure=FOUR)
    return lab.astype(np.int32), int(n)


def components(color: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """4-connected components of equal palette index (walls = -1 excluded).

    Returns (labels int32, -1 on walls, 0..R-1) and the palette index of each label.
    """
    from skimage.measure import label as sklabel
    lab = sklabel(color.astype(np.int32) + 1, background=0, connectivity=1).astype(np.int32) - 1
    n = int(lab.max()) + 1
    col = np.full(n, -1, np.int32)
    m = lab >= 0
    col[lab[m]] = color[m]
    return lab, col


def adjacency(lab: np.ndarray) -> dict:
    """Shared border lengths between 4-adjacent labels (both >= 0). {a: {b: count}}."""
    pairs = []
    for x, y in ((lab[:, :-1], lab[:, 1:]), (lab[:-1, :], lab[1:, :])):
        m = (x >= 0) & (y >= 0) & (x != y)
        a, b = x[m].astype(np.int64), y[m].astype(np.int64)
        lo, hi = np.minimum(a, b), np.maximum(a, b)
        pairs.append(lo * (1 << 31) + hi)
    if not pairs:
        return {}
    code, cnt = np.unique(np.concatenate(pairs), return_counts=True)
    adj: dict = {}
    for c, k in zip(code.tolist(), cnt.tolist()):
        a, b = c >> 31, c & ((1 << 31) - 1)
        adj.setdefault(a, {})[b] = k
        adj.setdefault(b, {})[a] = k
    return adj


def room_of_mask(mask: np.ndarray) -> tuple[float, tuple[int, int]]:
    """Inscribed radius of a bool mask (pixels; the canvas border and anything outside the
    mask bound it) and the most spacious pixel (row, col), first in raster order on ties."""
    if not mask.any():
        return 0.0, (0, 0)
    d = ndi.distance_transform_edt(np.pad(mask, 1))[1:-1, 1:-1]
    i = int(np.argmax(d))
    return float(d.flat[i]) - 0.5, divmod(i, mask.shape[1])


def rooms(lab: np.ndarray, n: int, blocked: np.ndarray | None = None):
    """Room (inscribed radius minus the half pixel to the boundary crack) and pole per label.

    ``blocked`` pixels (ink) are not part of any region's room."""
    room = np.zeros(n, np.float32)
    pole = np.zeros((n, 2), np.float32)
    area = np.zeros(n, np.int64)
    if n == 0:
        return room, pole, area
    work = lab if blocked is None else np.where(blocked, -1, lab)
    slices = ndi.find_objects(lab + 1, max_label=n)
    counts = np.bincount(lab[lab >= 0], minlength=n)
    area[:] = counts[:n]
    for k, sl in enumerate(slices):
        if sl is None:
            continue
        r, (py, px) = room_of_mask(work[sl] == k)
        room[k] = max(r, 0.0)
        pole[k] = (sl[1].start + px + 0.5, sl[0].start + py + 0.5)
    return room, pole, area


@dataclass
class MergeResult:
    lab: np.ndarray               # final labels (-1 on walls), 0..R-1
    color: np.ndarray             # palette index per label
    tiny: list = field(default_factory=list)     # labels that cannot hold a number (alone in their area)


def merge_small(lab: np.ndarray, col: np.ndarray, palette_lab: np.ndarray, ink: np.ndarray,
                slack: float = 0.0, salient_de: float = np.inf) -> MergeResult:
    """Merges every region too small for its number into a 4-adjacent neighbour (necessarily
    in the same enclosed area: walls separate areas), smallest first. The neighbour is chosen
    by shared border, discounted by color difference. Room is measured outside the ink.

    ``slack`` asks for more room than the number needs (fewer, bigger regions), except from a
    region that holds its number and differs from its chosen neighbour by more than
    ``salient_de`` (an eye, a highlight). A region left without neighbours (it fills its
    enclosed area alone) stays and is reported in ``tiny``."""
    n = len(col)
    room, _, _ = rooms(lab, n, ink)
    base = np.array([min_radius(digit_count(c + 1)) for c in col], np.float32)
    need = base + slack
    adj = adjacency(lab)
    parent = np.arange(n)
    members = {k: [k] for k in range(n)}
    slices = ndi.find_objects(lab + 1, max_label=n)
    bbox = {k: (sl[0].start, sl[0].stop, sl[1].start, sl[1].stop) for k, sl in enumerate(slices) if sl is not None}
    color = col.copy()
    heap = [(float(room[k]), k) for k in range(n) if room[k] < need[k]]
    heapq.heapify(heap)
    tiny = []
    work = np.where(ink, -1, lab)
    while heap:
        r, k = heapq.heappop(heap)
        if parent[k] != k or r != float(room[k]) or room[k] >= need[k]:
            continue
        nbrs = adj.get(k, {})
        if not nbrs:
            tiny.append(k)
            continue
        ck = palette_lab[color[k]]
        best, best_score = None, -1.0
        for b, length in sorted(nbrs.items()):
            de = float(np.linalg.norm(palette_lab[color[b]] - ck))
            score = length / (de + 0.03)
            if score > best_score:
                best, best_score = b, score
        t = best
        if room[k] >= base[k] and float(np.linalg.norm(palette_lab[color[t]] - ck)) > salient_de:
            need[k] = base[k]           # salient and numberable: keep it
            continue
        # union k into t
        parent[k] = t
        members[t].extend(members.pop(k))
        y0, y1, x0, x1 = bbox[t]
        ky0, ky1, kx0, kx1 = bbox.pop(k)
        bbox[t] = (min(y0, ky0), max(y1, ky1), min(x0, kx0), max(x1, kx1))
        for b, length in adj.pop(k).items():
            if b == t:
                continue
            nb = adj[b]
            nb.pop(k, None)
            nb[t] = nb.get(t, 0) + length
            adj[t][b] = adj[t].get(b, 0) + length
        adj[t].pop(k, None)
        if room[t] < need[t]:
            y0, y1, x0, x1 = bbox[t]
            sub = work[y0:y1, x0:x1]
            mask = np.isin(sub, members[t])
            room[t] = room_of_mask(mask)[0]
            heapq.heappush(heap, (float(room[t]), t))
    # relabel
    roots = np.array([k for k in range(n) if parent[k] == k], np.int64)
    root_of = np.arange(n)
    for k in range(n):
        p = k
        while parent[p] != p:
            p = parent[p]
        root_of[k] = p
    new_id = -np.ones(n, np.int64)
    new_id[roots] = np.arange(len(roots))
    lut = new_id[root_of]
    out = np.where(lab >= 0, lut[np.maximum(lab, 0)], -1).astype(np.int32)
    return MergeResult(out, color[roots].astype(np.int32), [int(new_id[k]) for k in tiny])


def relabel_by_color(lab: np.ndarray, color: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Recomputes connected components after edits (same-color neighbours fuse)."""
    img = np.where(lab >= 0, color[np.maximum(lab, 0)], -1).astype(np.int16)
    return components(img)


def assign_walls(lab: np.ndarray) -> np.ndarray:
    """Gives every unlabelled (-1) pixel the label of the nearest labelled pixel: the ink
    covers them, but the paint underneath must belong to some region."""
    holes = lab < 0
    if not holes.any():
        return lab.copy()
    _, (iy, ix) = ndi.distance_transform_edt(holes, return_indices=True)
    return lab[iy, ix]


def snap_thin_near_walls(color: np.ndarray, walls: np.ndarray, radius: int = 2, band: float = 2.5) -> np.ndarray:
    """Color edges running within ``band`` px of a wall leave thin strips between the edge and
    the wall. Strips (pixels outside the opening of their color by a disc of ``radius``) near a
    wall are handed to the neighbouring colors on their side of the wall, so the color edge
    lands on the wall."""
    k = 2 * radius + 1
    disc = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    opened = np.zeros(color.shape, bool)
    for c in np.unique(color[color >= 0]).tolist():
        m = (color == c).astype(np.uint8)
        opened |= cv2.morphologyEx(m, cv2.MORPH_OPEN, disc, borderType=cv2.BORDER_REPLICATE).astype(bool)
    near = ndi.distance_transform_edt(~walls) <= band
    loose = (color >= 0) & ~opened & near
    out = color.astype(np.int16).copy()
    out[loose] = -2
    out = fill_unassigned(out)
    stuck = out == -1
    stuck &= ~walls
    out[stuck] = color[stuck]       # a cell thin all over keeps its color (no neighbour to take)
    return out


def fill_unassigned(img: np.ndarray, hole: int = -2) -> np.ndarray:
    """Grows assigned values (>= 0) into ``hole`` pixels over 4-neighbours that are not walls
    (-1), one ring at a time; ties go to the most frequent neighbour value, then the lowest."""
    out = img.copy()
    h, w = out.shape
    for _ in range(64):
        holes = out == hole
        if not holes.any():
            break
        cand = []
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            sh = np.full_like(out, -1)
            ys = slice(max(dy, 0), h + min(dy, 0)); yd = slice(max(-dy, 0), h + min(-dy, 0))
            xs = slice(max(dx, 0), w + min(dx, 0)); xd = slice(max(-dx, 0), w + min(-dx, 0))
            sh[yd, xd] = out[ys, xs]
            cand.append(sh)
        cand = np.stack(cand, axis=-1)          # HxWx4
        hy, hx = np.nonzero(holes)
        cv = cand[hy, hx]                       # Kx4
        valid = cv >= 0
        anyv = valid.any(axis=1)
        if not anyv.any():
            break
        # most frequent valid neighbour value, lowest on ties
        best = np.full(len(hy), hole, np.int16)
        cnt_best = np.zeros(len(hy), np.int8)
        for j in range(4):
            v = cv[:, j]
            c = (cv == v[:, None]).sum(axis=1) * valid[:, j]
            better = (c > cnt_best) | ((c == cnt_best) & (c > 0) & (v < best))
            best = np.where(better, v, best)
            cnt_best = np.where(better, c, cnt_best)
        sel = anyv
        out[hy[sel], hx[sel]] = best[sel]
    out[out == hole] = -1
    return out


# ---------------------------------------------------------------------------------------------
# Domain-transform recursive filter (Gastal & Oliveira 2011) with walls as hard barriers.


def _rec_pass(img: np.ndarray, coeff: np.ndarray) -> None:
    """In place, along axis 1 of a (rows, cols, C) array; coeff (rows, cols-1)."""
    cols = img.shape[1]
    for x in range(1, cols):
        a = coeff[:, x - 1, None]
        img[:, x] += a * (img[:, x - 1] - img[:, x])
    for x in range(cols - 2, -1, -1):
        a = coeff[:, x, None]
        img[:, x] += a * (img[:, x + 1] - img[:, x])


def domain_transform(img: np.ndarray, guide: np.ndarray, barrier: np.ndarray, sigma_s: float,
                     sigma_r: float, iterations: int = 3, free_step: float = 0.0) -> np.ndarray:
    """Edge-aware smoothing of ``img`` (HxWxC float). Crossing between neighbours costs
    1 + sigma_s/sigma_r * max(|guide difference| - free_step, 0) pixels, so steps up to
    ``free_step`` blend as if absent; a step into or out of a ``barrier`` pixel is impossible,
    so nothing ever crosses a line."""
    out = img.astype(np.float32).copy()
    g = guide.astype(np.float32)
    dx = np.maximum(np.sqrt(((g[:, 1:] - g[:, :-1]) ** 2).sum(-1)) - free_step, 0)
    dy = np.maximum(np.sqrt(((g[1:, :] - g[:-1, :]) ** 2).sum(-1)) - free_step, 0)
    ratio = sigma_s / sigma_r
    dHx = 1 + ratio * dx
    dHy = 1 + ratio * dy
    bx = barrier[:, 1:] | barrier[:, :-1]
    by = barrier[1:, :] | barrier[:-1, :]
    n = iterations
    outT = None
    for i in range(n):
        sigma_i = sigma_s * math.sqrt(3) * 2 ** (n - i - 1) / math.sqrt(4 ** n - 1)
        a = math.exp(-math.sqrt(2) / sigma_i)
        cx = np.where(bx, 0.0, np.power(a, dHx)).astype(np.float32)
        cy = np.where(by, 0.0, np.power(a, dHy)).astype(np.float32)
        _rec_pass(out, cx)
        outT = np.ascontiguousarray(out.transpose(1, 0, 2))
        _rec_pass(outT, np.ascontiguousarray(cy.T))
        out = np.ascontiguousarray(outT.transpose(1, 0, 2))
    return out


def save_labels(path: str, lab: np.ndarray) -> None:
    assert lab.min() >= 0 and lab.max() < 65535
    cv2.imwrite(path, lab.astype(np.uint16))


def load_labels(path: str) -> np.ndarray:
    return cv2.imread(path, cv2.IMREAD_UNCHANGED).astype(np.int32)
