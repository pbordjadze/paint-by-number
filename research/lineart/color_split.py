"""C1: split pbn's regions by the lines.

pbn's color segmentation (raster.ppm) is kept; every region is cut wherever a wall crosses it
(regions are 4-connected same-color components of non-wall pixels). Then:

1. Snap: color edges running within ~2 px of a wall leave strips between edge and wall; they go
   to the color across the edge (on the same side of the wall), so the edge lands on the line.
2. Merge: fragments too small for their number (room outside the ink below
   LabelSizing.minimumRadius(digits:)) join a neighbour in the same enclosed area, never across
   a wall.
3. Cells: a fragment alone in its enclosed area (the drawing closed a cell too small for a
   number) joins a same-paint region across the line, or is absorbed if it is all ink, or
   stays with a minimum-size number (see ``finish``).
4. Wall pixels go to the nearest region (the ink covers them).
"""

from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np
from scipy import ndimage as ndi

from color_common import (FOUR, Option, Picture, assign_walls, components, digit_count, merge_small, min_radius,
                          rooms, snap_thin_near_walls)

ABSORB_ROOM = 1.0
JOIN_DE = 0.06


@dataclass
class Regions:
    lab: np.ndarray          # HxW int32, every pixel labelled (walls assigned)
    color: np.ndarray        # palette index per region
    open_lab: np.ndarray     # labels before wall assignment (-1 on walls and absorbed cells)
    absorbed: np.ndarray     # HxW bool: enclosed cells too small to show any paint beside the ink
    tiny: list               # regions still too small for their number (kept, minimum-size number)
    cells: dict = field(default_factory=dict)   # what happened to cells too small for a number


def finish(lab: np.ndarray, col: np.ndarray, pic: Picture, opt: Option, slack: float = 0.0,
           salient_de: float = np.inf, join_de: float = JOIN_DE) -> Regions:
    """Shared tail of C1 and C2: merge small fragments, settle cells too small for a number,
    assign walls.

    A cell the drawing closes too small for its number (a region alone in its enclosed area)
    joins the region across the line whose paint is within ``join_de`` of its own (in practice
    the same paint: the line cut through one color) — ink stays on top, the cell just has no
    number of its own. Otherwise, if not even a 2-px spot of it shows beside the ink, it goes to
    the nearest region like a wall pixel ("absorbed"); else it stays with a minimum-size number.
    """
    pal = pic.palette_lab
    res = merge_small(lab, col, pal, opt.ink, slack, salient_de)
    lab, col = res.lab, res.color
    n = len(col)
    absorbed = np.zeros(lab.shape, bool)
    target = np.arange(n)

    def resolve(k):
        while target[k] != k:
            k = target[k]
        return k

    joined, hopeless = 0, []
    if res.tiny:
        room, _, _ = rooms(lab, n, opt.ink)
        # cells that hold their number but not C2's extra room stay as they are
        res.tiny = [k for k in res.tiny if room[k] < min_radius(digit_count(col[k] + 1))]
    if res.tiny:
        slices = ndi.find_objects(lab + 1, max_label=n)
        h, w = lab.shape
        ring_k = np.ones((5, 5), np.uint8)
        for k in sorted(res.tiny, key=lambda k: (float(room[k]), k)):
            sl = slices[k]
            y0, y1 = max(sl[0].start - 3, 0), min(sl[0].stop + 3, h)
            x0, x1 = max(sl[1].start - 3, 0), min(sl[1].stop + 3, w)
            sub = lab[y0:y1, x0:x1]
            m = sub == k
            ring = cv2.dilate(m.astype(np.uint8), ring_k).astype(bool) & ~m & (sub >= 0)
            nbrs = sorted({resolve(int(v)) for v in np.unique(sub[ring])} - {k})
            if nbrs:
                de = [float(np.linalg.norm(pal[col[v]] - pal[col[k]])) for v in nbrs]
                j = int(np.argmin(de))
                if de[j] <= join_de:
                    target[k] = nbrs[j]
                    joined += 1
                    continue
            if room[k] < ABSORB_ROOM:
                hopeless.append(k)
        lut = np.array([resolve(k) for k in range(n)])
        lab = np.where(lab >= 0, lut[np.maximum(lab, 0)], -1)
        absorbed = np.isin(lab, hopeless)       # with any cell that joined a hopeless one
        lab[absorbed] = -1
        used = np.unique(lab[lab >= 0])
        remap = -np.ones(n, np.int64)
        remap[used] = np.arange(len(used))
        lab = np.where(lab >= 0, remap[np.maximum(lab, 0)], -1).astype(np.int32)
        col = col[used]
    full = assign_walls(lab)
    room, _, _ = rooms(full, len(col), opt.ink)
    tiny = [k for k in range(len(col)) if room[k] < min_radius(digit_count(col[k] + 1))]
    cells = {"tooSmall": len(res.tiny), "joinedAcrossLine": joined,
             "absorbed": int(ndi.label(absorbed, structure=FOUR)[1]) if absorbed.any() else 0, "kept": len(tiny)}
    return Regions(full, col, lab, absorbed, tiny, cells)


def split(pic: Picture, opt: Option, snap_band: float = 2.5) -> Regions:
    color = np.where(opt.walls, -1, pic.raster).astype(np.int16)
    if snap_band > 0:
        color = snap_thin_near_walls(color, opt.walls, radius=2, band=snap_band)
    lab, col = components(color)
    return finish(lab, col, pic, opt)
