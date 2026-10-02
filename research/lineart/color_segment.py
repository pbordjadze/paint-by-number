"""C2: segment inside each enclosed area.

1. Enclosed areas: 4-connected components of non-wall pixels (an open stroke's free end lets an
   area wrap around it).
2. The photo is smoothed in OKLab with a domain-transform filter that never crosses a wall, so
   texture goes and each area's colors stay its own.
3. Data term: ΔE from each pixel to each palette color, half from the smoothed photo, half from
   the color pbn's raster gave it (pbn's assignment is stable on soft transitions where the
   photo alone would pick a foreign color, e.g. a blue-gray halo around a highlight).
4. Each area picks a few of the palette colors pbn uses in it, greedily: the color that best
   represents it, then more while one pays off (the pixels it takes improve by ``tau_px`` ΔE
   on average over at least ``min_take`` pixels, or by ``salient_gain`` over at least
   ``salient_take`` pixels: an eye, a highlight; at most one color per ``area_per_color``
   pixels). An area holding a gradient keeps a few tonal steps; an object of its own color
   inside an unclosed area still gets its color.
5. Pixels take the cheapest allowed color with a Potts smoothness term (red-black ICM).
6. Same tail as C1: strips between a color edge and a nearby wall are snapped onto the wall,
   fragments too small merge into a neighbour in the same area (C2 asks ``min_room_slack``
   more room than the number needs, so regions are fewer and bigger, except salient ones that
   differ from their neighbour by more than ``salient_de``), cells too small for a number are
   settled, walls go to the nearest region.
"""

from __future__ import annotations

import numpy as np

from color_common import Option, Picture, components, domain_transform, enclosed_areas, snap_thin_near_walls
from color_split import Regions, finish


def smooth_photo(pic: Picture, walls: np.ndarray, sigma_s: float, sigma_r: float) -> np.ndarray:
    lab = pic.photo_lab
    return domain_transform(lab, lab, walls, sigma_s, sigma_r)


def palette_distances(img_lab: np.ndarray, palette_lab: np.ndarray) -> np.ndarray:
    h, w, _ = img_lab.shape
    flat = img_lab.reshape(-1, 3)
    d = np.empty((flat.shape[0], len(palette_lab)), np.float32)
    for c, p in enumerate(palette_lab):
        d[:, c] = np.sqrt(((flat - p) ** 2).sum(1))
    return d


def present_colors(raster: np.ndarray, areas: np.ndarray, n_areas: int, ncol: int, share: float,
                   min_px: int) -> np.ndarray:
    """present[area, color]: palette colors pbn's raster uses for a real part of the area (a
    share of it or ``min_px`` pixels); an area where none qualifies keeps every color it has."""
    key = areas.ravel().astype(np.int64) * ncol + raster.ravel()
    cnt = np.bincount(key, minlength=(n_areas + 1) * ncol).reshape(n_areas + 1, ncol)
    size = cnt.sum(1, keepdims=True)
    present = cnt >= np.minimum(np.maximum(share * size, min_px), np.maximum(size, 1))
    none = ~present.any(1)
    present[none] = cnt[none] > 0
    return present


def choose_colors(dist: np.ndarray, areas: np.ndarray, n_areas: int, present: np.ndarray, tau_px: float,
                  tau_area: float, min_take: int, max_colors: int, area_per_color: int,
                  salient_take: int = 40, salient_gain: float = 0.08, sample: int = 40000) -> np.ndarray:
    """allowed[area, color]: the palette subset each enclosed area paints with, drawn from the
    colors ``present`` there (big areas are judged on every k-th pixel, at most ``sample``)."""
    ncol = dist.shape[1]
    allowed = np.zeros((n_areas + 1, ncol), bool)
    flat = areas.ravel()
    order = np.argsort(flat, kind="stable")
    counts = np.bincount(flat, minlength=n_areas + 1)
    starts = np.concatenate([[0], np.cumsum(counts)])
    for a in range(1, n_areas + 1):
        idx = order[starts[a]:starts[a + 1]]
        if len(idx) == 0:
            continue
        n_all = len(idx)
        step = -(-n_all // sample)
        idx = idx[::step]
        da = dist[idx]
        first = int(np.argmin(np.where(present[a], da.sum(0), np.inf)))
        allowed[a, first] = True
        cur = da[:, first].copy()
        n = len(idx)
        min_take_s = min_take / step
        salient_take_s = salient_take / step
        for _ in range(min(ncol, max_colors, 1 + n_all // area_per_color) - 1):
            better = np.minimum(cur[:, None], da)
            gain = cur.sum() - better.sum(0)
            take = (da < cur[:, None]).sum(0)
            ordinary = (take >= min_take_s) & (gain >= tau_px * np.maximum(take, 1))
            salient = (take >= salient_take_s) & (gain >= salient_gain * np.maximum(take, 1))
            ok = (ordinary | salient) & (gain >= tau_area * n) & present[a] & ~allowed[a]
            if not ok.any():
                break
            c = int(np.argmax(np.where(ok, gain, -1)))
            allowed[a, c] = True
            cur = better[:, c]
    return allowed


def potts(dist: np.ndarray, allowed_px: np.ndarray, walls: np.ndarray, beta: float, iterations: int) -> np.ndarray:
    """Red-black ICM over 4-neighbours (walls never count as neighbours). A pixel's best color
    is its own cheapest one or one of its neighbours' (any other color gets no smoothness
    bonus), so only those five are scored."""
    h, w = walls.shape
    ncol = dist.shape[1]
    cost = np.where(allowed_px, dist, np.inf).reshape(h, w, ncol).astype(np.float32)
    unary = np.argmin(cost, axis=2).astype(np.int16)
    lab = unary.copy()
    lab[walls] = -1
    parity = (np.add.outer(np.arange(h), np.arange(w)) & 1).astype(bool)
    for _ in range(iterations):
        for phase in (False, True):
            sel = (parity == phase) & ~walls
            pad = np.pad(lab, 1, constant_values=-1)
            nb = np.stack([pad[:-2, 1:-1], pad[2:, 1:-1], pad[1:-1, :-2], pad[1:-1, 2:]], -1)   # HxWx4
            cand = np.concatenate([unary[..., None], nb], -1)                                     # HxWx5
            same = (cand[..., :, None] == nb[..., None, :]).sum(-1)
            e = np.take_along_axis(cost, np.maximum(cand, 0).astype(np.int64), 2) - beta * same
            e = np.where(cand >= 0, e, np.inf)
            pick = np.take_along_axis(cand, np.argmin(e, axis=2)[..., None], 2)[..., 0]
            lab = np.where(sel, pick, lab).astype(np.int16)
    return lab


def segment(pic: Picture, opt: Option, sigma_s: float = 10.0, sigma_r: float = 0.06, raster_weight: float = 0.5,
            present_share: float = 0.002, present_px: int = 60, tau_px: float = 0.03, tau_area: float = 0.0,
            min_take: int = 300, max_colors: int = 40, area_per_color: int = 6000, beta: float = 0.02,
            iterations: int = 6, snap_band: float = 2.5, min_room_slack: float = 1.5,
            salient_de: float = 0.12) -> Regions:
    walls = opt.walls
    areas, n_areas = enclosed_areas(walls)
    smooth = smooth_photo(pic, walls, sigma_s, sigma_r)
    pal = pic.palette_lab
    dist = palette_distances(smooth, pal)
    if raster_weight > 0:
        pd = np.sqrt(((pal[:, None] - pal[None]) ** 2).sum(-1)).astype(np.float32)
        dist = (1 - raster_weight) * dist + raster_weight * pd[pic.raster.ravel()]
    present = present_colors(pic.raster, areas, n_areas, len(pal), present_share, present_px)
    allowed = choose_colors(dist, areas, n_areas, present, tau_px, tau_area, min_take, max_colors,
                            area_per_color)
    allowed_px = allowed[areas.ravel()]
    color = potts(dist, allowed_px, walls, beta, iterations)
    if snap_band > 0:
        color = snap_thin_near_walls(color, walls, radius=2, band=snap_band)
    lab, col = components(color)
    return finish(lab, col, pic, opt, min_room_slack, salient_de)
