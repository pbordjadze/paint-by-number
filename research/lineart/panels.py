"""Stage 2 panels, all at 2x working size:

- ``plan``: the painting plan. Paper, faint dotted guides on region boundaries that are not
  lines, ink on top, numbers (palette index + 1) in a serif at each region's pole of
  inaccessibility, sized by LabelSizing like the app; big regions get extra numbers spread like
  pbn's Vectorizer.addExtraLabels.
- ``finished``: flat paint blurred across unlined boundaries only (domain-transform filter whose
  steps never enter a wall pixel; a guide between neighbouring tones costs nothing to cross,
  bigger color jumps progressively more), ink on top.
- ``flat_paint``: the paint unblurred, ink on top (what C1/C2 actually produce).

Region boundaries come from pbn's pixel raster; ``smooth_colors_2x`` rounds their staircases
off at 2x so the panels compare fairly with pbn's smoothed vector template.
- ``current_template`` / ``current_painted``: pbn's template.svg / painted.svg rendered with
  resvg (tools/svg2png.mjs; node and @resvg/resvg-js from $PANEL_NODE_DIR).
"""

from __future__ import annotations

import math
import os
import subprocess

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

from color_common import (PAPER, Option, Picture, digit_count, domain_transform, font_size, min_radius,
                          oklab_to_srgb8, rooms)

SCRATCH = "/tmp/claude-0/-home-user-paint-by-number/861bb375-0f52-519e-91ca-dcf515297999/scratchpad"
FONT_PATH = os.environ.get("PANEL_FONT", os.path.join(SCRATCH, "fonts", "SourceSerif4-Regular.ttf"))
FALLBACK_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"
NODE = os.environ.get("PANEL_NODE", "/opt/node22/bin/node")
NODE_DIR = os.environ.get("PANEL_NODE_DIR", os.path.join(SCRATCH, "node"))

NUMBER_COLOR = (112, 104, 118)
GUIDE_COLOR = (112, 104, 118)
GUIDE_ALPHA = 0.55
GUIDE_SPACING = 2.2       # working px between dots (4.4 px at 2x)
GUIDE_DOT_RADIUS = 0.8    # 2x px


_font_cache: dict = {}


def font(size_px: float) -> ImageFont.FreeTypeFont:
    path = FONT_PATH if os.path.exists(FONT_PATH) else FALLBACK_FONT
    key = (path, round(size_px * 2) / 2)
    f = _font_cache.get(key)
    if f is None:
        f = ImageFont.truetype(path, size=key[1])
        _font_cache[key] = f
    return f


def up2(a: np.ndarray) -> np.ndarray:
    return np.repeat(np.repeat(a, 2, axis=0), 2, axis=1)


def over(base: np.ndarray, rgba: np.ndarray) -> np.ndarray:
    a = rgba[..., 3:4].astype(np.float32) / 255.0
    return (base.astype(np.float32) * (1 - a) + rgba[..., :3].astype(np.float32) * a)


# ---------------------------------------------------------------------------------------------
# Labels


def labels_for(lab: np.ndarray, color: np.ndarray, ink: np.ndarray, long_side: int):
    """Number positions (canvas units) and free radii: the pole of every region measured
    outside the ink, plus pbn-style extra labels over big regions."""
    n = len(color)
    work = np.where(ink, -1, lab)
    slices = ndi.find_objects(lab + 1, max_label=n)
    poles, dist_crops = [], []
    for k, sl in enumerate(slices):
        if sl is None:
            poles.append(None); dist_crops.append(None)
            continue
        mask = work[sl] == k
        d = ndi.distance_transform_edt(np.pad(mask, 1))[1:-1, 1:-1] - 0.5
        if not mask.any():
            # the region is entirely under ink; put its number at its own pixels' centre
            m2 = lab[sl] == k
            ys, xs = np.nonzero(m2)
            i = len(ys) // 2
            poles.append((sl[1].start + xs[i] + 0.5, sl[0].start + ys[i] + 0.5, 0.0))
            dist_crops.append(None)
            continue
        i = int(np.argmax(d))
        py, px = divmod(i, mask.shape[1])
        poles.append((sl[1].start + px + 0.5, sl[0].start + py + 0.5, float(max(d.flat[i], 0.0))))
        dist_crops.append((sl, d, mask))
    labels = [(p[0], p[1], p[2], k) for k, p in enumerate(poles) if p is not None]
    radii = sorted(p[2] for p in poles if p is not None and p[2] >= 1)
    typical = min(max(radii[len(radii) // 2] if radii else 4, 3), 8)
    spacing = max(10 * typical, long_side / 16)
    min_r = max(1.5 * typical, 5)
    min_area = spacing * spacing * 0.5
    for k, entry in enumerate(dist_crops):
        if entry is None:
            continue
        sl, d, mask = entry
        area = int(mask.sum())
        if area < min_area or poles[k][2] < min_r:
            continue
        y0, x0 = sl[0].start, sl[1].start
        ys, xs = np.nonzero((d >= min_r) & mask)
        keep = ((ys + y0) % 2 == 0) & ((xs + x0) % 2 == 0)
        ys, xs = ys[keep], xs[keep]
        if len(ys) == 0:
            continue
        key = -np.round(d[ys, xs] * 4)
        pix = (ys + y0) * lab.shape[1] + (xs + x0)
        order = np.lexsort((pix, key))
        cap = min(64, int(area / (spacing * spacing * 0.6)))
        legible = min_radius(digit_count(color[k] + 1))
        placed = [(poles[k][0], poles[k][1])]
        extras = 0
        for j in order:
            if extras >= cap:
                break
            px, py = xs[j] + x0 + 0.5, ys[j] + y0 + 0.5
            if any((px - qx) ** 2 + (py - qy) ** 2 < spacing * spacing for qx, qy in placed):
                continue
            free = float(d[ys[j], xs[j]])
            if free < max(min_r * 0.8, legible):
                continue
            placed.append((px, py))
            labels.append((px, py, free, k))
            extras += 1
    return labels


def draw_numbers(img: Image.Image, labels, color: np.ndarray, long_side: int, scale: float = 2.0,
                 fill=NUMBER_COLOR) -> None:
    draw = ImageDraw.Draw(img)
    maximum = long_side / 64
    for x, y, r, k in labels:
        text = str(int(color[k]) + 1)
        size = font_size(r, len(text), maximum) * scale
        f = font(size)
        # centre the digits' ink box on the label point
        l, t, rr, b = f.getbbox(text, anchor="ls")
        cx, cy = x * scale, y * scale
        draw.text((cx - (l + rr) / 2, cy - (t + b) / 2), text, font=f, fill=fill, anchor="ls")


# ---------------------------------------------------------------------------------------------
# Guides


def smooth_colors_2x(color: np.ndarray, walls: np.ndarray, sigma: float = 2.5, keep_near_wall: float = 3.0):
    """Palette-index map at 2x with smooth boundaries: each pixel takes the color with the most
    Gaussian-weighted votes around it (pbn's raster boundaries are pixel staircases; the vector
    template is smooth, and the panels should be too). Next to walls the nearest-neighbour
    color is kept so no color is pulled across a line (the ink covers that strip)."""
    up = up2(color)
    best = np.full(up.shape, -1.0, np.float32)
    arg = up.copy()
    for c in np.unique(up).tolist():
        v = cv2.GaussianBlur((up == c).astype(np.float32), (0, 0), sigma)
        better = v > best
        best[better] = v[better]
        arg[better] = c
    near = ndi.distance_transform_edt(~up2(walls)) <= keep_near_wall
    return np.where(near, up, arg)


def guide_points(color2x: np.ndarray, hide: np.ndarray) -> np.ndarray:
    """Midpoints (x, y at 2x) of the cracks between two colors where nothing hides them (walls,
    ink): the unlined boundaries. Within an enclosed area two neighbouring regions always
    differ in color (equal colors would be one region), so color changes are region changes."""
    pts = []
    a, b = color2x[:, :-1], color2x[:, 1:]
    m = (a != b) & ~hide[:, :-1] & ~hide[:, 1:]
    ys, xs = np.nonzero(m)
    pts.append(np.stack([xs + 1.0, ys + 0.5], 1))
    a, b = color2x[:-1, :], color2x[1:, :]
    m = (a != b) & ~hide[:-1, :] & ~hide[1:, :]
    ys, xs = np.nonzero(m)
    pts.append(np.stack([xs + 0.5, ys + 1.0], 1))
    p = np.concatenate(pts)
    order = np.lexsort((p[:, 0], p[:, 1]))
    return p[order]


def dots_alpha(points: np.ndarray, shape2x, spacing: float, radius: float) -> np.ndarray:
    """Greedy, deterministic thinning of points (2x px) to dots at least ``spacing`` apart,
    drawn as anti-aliased discs into an alpha map."""
    cell = spacing
    grid: dict = {}
    keep = []
    s2 = spacing * spacing
    for x, y in points.tolist():
        gx, gy = int(x // cell), int(y // cell)
        ok = True
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                for qx, qy in grid.get((gx + ox, gy + oy), ()):
                    if (x - qx) ** 2 + (y - qy) ** 2 < s2:
                        ok = False
                        break
                if not ok:
                    break
            if not ok:
                break
        if ok:
            grid.setdefault((gx, gy), []).append((x, y))
            keep.append((x, y))
    h2, w2 = shape2x
    ss = 4
    acc = np.zeros((h2 * ss, w2 * ss), np.float32)
    if keep:
        k = np.array(keep) * ss
        xi = np.clip(k[:, 0].astype(int), 0, w2 * ss - 1)
        yi = np.clip(k[:, 1].astype(int), 0, h2 * ss - 1)
        acc[yi, xi] = 1
        ksz = int(math.ceil(radius * ss)) * 2 + 1
        disc = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksz, ksz))
        acc = cv2.dilate(acc, disc)
    alpha = cv2.resize(acc, (w2, h2), interpolation=cv2.INTER_AREA)
    return np.clip(alpha, 0, 1)


# ---------------------------------------------------------------------------------------------
# Panels


def region_colors(regions) -> np.ndarray:
    return regions.color[regions.lab]


def plan(pic: Picture, opt: Option, regions, color2x: np.ndarray | None = None) -> Image.Image:
    h, w = pic.height, pic.width
    if color2x is None:
        color2x = smooth_colors_2x(region_colors(regions), opt.walls | regions.absorbed)
    base = np.empty((2 * h, 2 * w, 3), np.float32)
    base[:] = PAPER
    hide = (ndi.distance_transform_edt(~up2(opt.walls | regions.absorbed)) <= 3.0) | (opt.ink2x[..., 3] > 60)
    pts = guide_points(color2x, hide)
    alpha = dots_alpha(pts, (2 * h, 2 * w), 2 * GUIDE_SPACING, GUIDE_DOT_RADIUS) * GUIDE_ALPHA
    base = base * (1 - alpha[..., None]) + np.array(GUIDE_COLOR, np.float32) * alpha[..., None]
    base = over(base, opt.ink2x)
    img = Image.fromarray(np.clip(np.round(base), 0, 255).astype(np.uint8))
    labels = labels_for(regions.lab, regions.color, opt.ink, max(h, w))
    draw_numbers(img, labels, regions.color, max(h, w))
    return img


def palette_step(palette_lab: np.ndarray) -> float:
    """Median distance from a paint to its nearest other paint (OKLab ΔE)."""
    d = np.sqrt(((palette_lab[:, None] - palette_lab[None]) ** 2).sum(-1))
    np.fill_diagonal(d, np.inf)
    return float(np.median(d.min(1)))


def detail_weight(regions, small: float = 3.0, big: float = 10.0) -> np.ndarray:
    """0 where regions are small (texture: foliage, foam), 1 where they are big (bands of a
    gradient), from each region's inscribed radius, smoothed so no seam shows (working res)."""
    room, _, _ = rooms(regions.lab, len(regions.color), None)
    r = cv2.GaussianBlur(room[regions.lab].astype(np.float32), (0, 0), 4.0)
    return np.clip((r - small) / (big - small), 0, 1)


def finished(pic: Picture, opt: Option, regions, color2x: np.ndarray | None = None, sigma_s: float = 24.0,
             sigma_small: float = 3.0, sigma_r: float = 0.07, free_steps: float = 1.2, return_lab: bool = False):
    """``sigma_s`` in working px (doubled at 2x); ``sigma_r`` in OKLab ΔE. Unlined boundaries
    between neighbouring tones (up to ``free_steps`` palette steps apart) blend freely, bigger
    jumps progressively less, lines never. Where regions are small (texture) the blur shrinks
    to ``sigma_small`` so the texture softens instead of melting into mush. With ``return_lab``
    also returns the blurred paint (OKLab, 2x, before ink)."""
    free_step = free_steps * palette_step(pic.palette_lab)
    if color2x is None:
        color2x = smooth_colors_2x(region_colors(regions), opt.walls | regions.absorbed)
    flat = pic.palette_lab[color2x]
    barrier = up2(opt.walls | regions.absorbed)
    wide = domain_transform(flat, flat, barrier, 2 * sigma_s, sigma_r, free_step=free_step)
    if sigma_small > 0:
        near = domain_transform(flat, flat, barrier, 2 * sigma_small, sigma_r, free_step=free_step)
        w = cv2.resize(detail_weight(regions), (flat.shape[1], flat.shape[0]), interpolation=cv2.INTER_LINEAR)
        soft = near + w[..., None] * (wide - near)
    else:
        soft = wide
    soft = cv2.GaussianBlur(soft, (0, 0), 0.6)
    rgb = oklab_to_srgb8(soft).astype(np.float32)
    rgb = over(rgb, opt.ink2x)
    img = Image.fromarray(np.clip(np.round(rgb), 0, 255).astype(np.uint8))
    return (img, soft) if return_lab else img


def flat_paint(pic: Picture, opt: Option, regions, color2x: np.ndarray | None = None) -> Image.Image:
    """Unblurred paint with ink on top (for comparison with ``finished``)."""
    if color2x is None:
        color2x = smooth_colors_2x(region_colors(regions), opt.walls | regions.absorbed)
    rgb = pic.palette[color2x].astype(np.float32)
    rgb = over(rgb, opt.ink2x)
    return Image.fromarray(np.clip(np.round(rgb), 0, 255).astype(np.uint8))


def render_svg(svg: str, png: str, width: int) -> None:
    script = os.path.join(NODE_DIR, "svg2png.mjs")
    subprocess.run([NODE, script, svg, png, str(width)], check=True, cwd=NODE_DIR)


def current_template(pic: Picture, out_dir: str) -> None:
    w = 2 * pic.width
    render_svg(os.path.join(pic.dir, "template.svg"), os.path.join(out_dir, "current_template.png"), w)
    render_svg(os.path.join(pic.dir, "painted.svg"), os.path.join(out_dir, "current_painted.png"), w)
