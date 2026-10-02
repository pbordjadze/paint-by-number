"""Shared cleanup: a raw line response map -> weighted vector strokes, walls and ink.

Every family's raw map (float in [0, 1], 1 = line, at working resolution) goes through the
same steps, so families compete on the lines they find, not on cleanup:

1. Threshold and thin. The 3 px frame is cleared (the canvas edge is not a line; Kodak
   frames have a dark rim). Centerlines come from ridge non-maximum suppression: a pixel
   is kept when the (sigma 0.8) response is not smaller than both neighbours across the
   line (the Hessian's most negative eigenvector, RIDGE_SIGMA) and curves down there, so a
   soft 10 px HED line and a crisp 2 px one both give their centerline and nearby lines do
   not merge; ridges hugging the frame (within FRAME_PARALLEL px, parallel to it) are
   dropped. Hysteresis on the ridge pixels: above `low`, 8-connected to one above `high`,
   both scaled by importance (x0.7 on the subject, up to x1.24 where it is lowest: more
   detail on the subject) and by clutter: where a first pass finds lines packed denser
   than the level's `clutter` density (CLUTTER_WINDOW box), thresholds rise by up to
   CLUTTER_GAIN, except on strong photo edges (gradient CLUTTER_PROTECT), so a weave, rocks
   or foliage keep only their strongest lines. Fills: where the response stays above the
   family's `fill_level` over more than 2 * FILL_HALF_WIDTH px (speckle closed, cores of at
   least FILL_CORE_AREA px, so a junction of thick lines is not one), the area is replaced
   by its outline, the way a draughtsman outlines a dark shape (XDoG's black masses). A
   closing seals one-pixel ridge breaks; `skeletonize` thins to 1 px.
2. Trace into a graph: nodes are endpoints and junction clusters, edges the 1 px chains
   between them (loops without nodes are closed edges). Bubbles (two edges between the same
   nodes, perimeter < BUBBLE px) are popped; spurs (an endpoint edge shorter than `spur` px
   hanging off a junction) pruned; texture meshes suppressed (short edges, < `mesh_len`,
   where centerlines are denser than `mesh_density` in a MESH_WINDOW box, unless the photo
   edge is very strong); gaps bridged: from each free endpoint along its tangent (cone 35
   degrees, up to `gap` px) to another endpoint (which must face back, within 60 degrees)
   or onto another line (a T-junction), best bridges first. Components shorter than
   `frag` x (1.6 - importance) x (1.3 - 0.8 contrast) px are dropped (short strokes live on
   the subject and on strong edges: an eye survives where a speck of texture does not).
   Free ends heading into the frame within FRAME_EXTEND px are continued to it, so contours
   that leave the picture seal against the canvas edge.
3. Edges are joined through junctions into strokes (at each junction the best-aligned pairs
   of branches continue each other, within 45 degrees), smoothed (Gaussian along the chain,
   sigma SMOOTH_SIGMA px, ends pinned so strokes keep meeting at junctions) and simplified
   (Douglas-Peucker, SIMPLIFY_EPS px) into dense polylines that render as curves.
4. Each stroke gets a contrast (mean OKLab deltaE between the photo 2.5 px either side of
   it) and an importance (mean of the importance proxy along it, see
   lines_common.importance_map). Width variants (working px):
     weighted  W_MIN..W_MAX by contrast, scaled 0.7..1.0 by importance and 0.85..1.0 by
               length (long contours read as silhouettes);
     tapered   weighted, thinned towards the ends over min(30 px, length / 2.5) (to 12%
               at free ends, 50% where the stroke meets another) and swelling +-25% with
               the local contrast along it, like brush pressure;
     uniform   UNIFORM_WIDTH everywhere.
   Ink color: near-black INK, or "colored": per point, the paint of raster.ppm on the
   darker side of the stroke, darkened in OKLab (L * 0.55, at most 0.38; chroma * 1.1),
   smoothed along the stroke.
5. Walls: the smoothed centerlines rasterized as 8-connected 1 px lines (Bresenham between
   consecutive points, plus links to every junction point the stroke passed through), so a
   4-connected flood fill cannot cross a stroke and strokes that meet stay sealed.

Detail levels (sparse, medium, rich) change `spur`, `gap`, `frag`, `mesh_*` and `clutter`
(DETAIL, shared by every family) and the family's hysteresis thresholds (run_lines.FAMILIES,
calibrated per family because each detector has its own response scale).
"""

import math

import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree
from skimage.draw import line as draw_line
from skimage.morphology import remove_small_holes, skeletonize

import lines_common as lc

FRAME = 3
FILL_HALF_WIDTH = 8.0
HOLE_AREA = 60
FILL_CORE_AREA = 80
BUBBLE = 36.0
FRAME_PARALLEL = 12
FRAME_EXTEND = 14.0
RIDGE_SIGMA = 1.5
SMOOTH_SIGMA = 2.0
SIMPLIFY_EPS = 0.25
W_MIN, W_MAX = 0.75, 2.1
UNIFORM_WIDTH = 1.1
CONTRAST_REF = 0.22
SIDE_OFFSET = 2.5
FRAGMENT_METRIC = 24.0  # strokes shorter than this count as fragments in metrics

DETAIL = {
    "sparse": dict(spur=14, gap=10, frag=56, mesh_density=0.085, mesh_len=40, clutter=0.05),
    "medium": dict(spur=10, gap=9, frag=36, mesh_density=0.11, mesh_len=28, clutter=0.07),
    "rich": dict(spur=7, gap=8, frag=18, mesh_density=0.14, mesh_len=20, clutter=0.10),
}
FRAG_CONTRAST_REF = 0.10
MESH_WINDOW = 25
CLUTTER_WINDOW = 31
CLUTTER_GAIN = 1.0
CLUTTER_PROTECT = 0.12
MESH_PROTECT = 0.12  # photo OKLab gradient (deltaE / px) that keeps a short edge in a mesh

_OFFS = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]


# ---------------------------------------------------------------- 1. threshold and thin

def ridges(r, sigma=RIDGE_SIGMA):
    """Pixels on a ridge of the response: not smaller than both neighbours across the line
    (the Hessian's most negative eigenvector), where the response curves down across it.
    This is the thinning for soft, wide responses (HED's 10 px lines) as much as for crisp
    ones: their centerline, whatever their width, and no merging of nearby lines."""
    rs = ndimage.gaussian_filter(r, 0.8, mode="nearest")
    hxx = ndimage.gaussian_filter(r, sigma, order=(0, 2), mode="nearest")
    hyy = ndimage.gaussian_filter(r, sigma, order=(2, 0), mode="nearest")
    hxy = ndimage.gaussian_filter(r, sigma, order=(1, 1), mode="nearest")
    disc = np.sqrt((hxx - hyy) ** 2 + 4 * hxy * hxy)
    lam = 0.5 * (hxx + hyy - disc)  # the most negative eigenvalue
    # its eigenvector: (hxy, lam - hxx) or (lam - hyy, hxy)
    vx = np.where(np.abs(hxx - lam) < np.abs(hyy - lam), lam - hyy, hxy)
    vy = np.where(np.abs(hxx - lam) < np.abs(hyy - lam), hxy, lam - hxx)
    n = np.hypot(vx, vy)
    vx = np.where(n > 1e-12, vx / np.maximum(n, 1e-12), 1.0)
    vy = np.where(n > 1e-12, vy / np.maximum(n, 1e-12), 0.0)
    h, w = r.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = ndimage.map_coordinates(rs, [yy + vy, xx + vx], order=1, mode="nearest")
    b = ndimage.map_coordinates(rs, [yy - vy, xx - vx], order=1, mode="nearest")
    ridge = (rs >= a) & (rs >= b) & (lam < 0)
    # a line hugging the frame (a dark rim, a vignette) is not part of the drawing
    m = FRAME_PARALLEL
    side = np.zeros_like(ridge)
    side[:, :m] = side[:, -m:] = True
    ridge &= ~(side & (np.abs(vx) > 0.8))
    side[:] = False
    side[:m, :] = side[-m:, :] = True
    ridge &= ~(side & (np.abs(vy) > 0.8))
    return ridge, rs


def _hysteresis(cand, seeds):
    lab, n = ndimage.label(cand, structure=np.ones((3, 3), bool))
    keep = np.zeros(n + 1, bool)
    keep[np.unique(lab[seeds])] = True
    keep[0] = False
    return keep[lab]


def binarize(raw, importance, high, low, fill_level=None, clutter_density=None, grad=None):
    r = raw.astype(np.float32).copy()
    r[:FRAME, :] = 0
    r[-FRAME:, :] = 0
    r[:, :FRAME] = 0
    r[:, -FRAME:] = 0
    scale = (1.3 - 0.6 * importance).astype(np.float32)
    ridge, rs = ridges(r)
    if clutter_density:
        # where a first pass finds lines packed denser than `clutter_density` (texture),
        # thresholds rise by up to CLUTTER_GAIN: only the strongest lines of a weave, a
        # rock face or foliage survive
        first = _hysteresis(ridge & (rs > low * scale), ridge & (rs > high * scale))
        dens = ndimage.uniform_filter(first.astype(np.float32), CLUTTER_WINDOW, mode="constant")
        clutter = np.clip(dens / clutter_density - 1.0, 0, 1)
        clutter = ndimage.gaussian_filter(clutter, CLUTTER_WINDOW / 4, mode="nearest")
        if grad is not None:  # a strong photo edge (an eyelid, a silhouette) is not texture
            clutter = clutter * (1.0 - np.clip(grad / CLUTTER_PROTECT, 0, 1))
        scale = scale * (1.0 + CLUTTER_GAIN * clutter)
    cand = ridge & (rs > low * scale)
    lines = _hysteresis(cand, cand & (rs > high * scale))
    # fills -> outlines: parts of the response above `fill_level` (the family's sparse `high`,
    # the same at every detail level, so a soft wide line never turns into a fill as the
    # thresholds drop) wider than 2 * FILL_HALF_WIDTH (after closing the speckle of porous
    # dark areas) are areas, not lines
    tmask = r > (high if fill_level is None else fill_level) * scale
    solid = ndimage.binary_closing(tmask, structure=np.ones((3, 3), bool), iterations=2)
    solid = remove_small_holes(solid, max_size=HOLE_AREA)
    core = ndimage.distance_transform_edt(solid) > FILL_HALF_WIDTH
    # a junction of thick lines is locally deep too; a fill has a large core
    lab, n = ndimage.label(core)
    if n:
        sizes = ndimage.sum(core, lab, np.arange(1, n + 1))
        core = np.isin(lab, np.flatnonzero(sizes >= FILL_CORE_AREA) + 1)
    if core.any():
        fill = ndimage.binary_dilation(core, iterations=int(FILL_HALF_WIDTH)) & solid
        fill = ndimage.binary_fill_holes(fill)
        outline = fill & ~ndimage.binary_erosion(fill, structure=np.ones((3, 3), bool))
        frame = np.zeros_like(fill)
        m = FRAME + 2
        frame[:m, :] = frame[-m:, :] = True
        frame[:, :m] = frame[:, -m:] = True
        outline &= ~frame
        lines = (lines & ~fill) | outline
    # close one-pixel breaks of the ridge (junctions, corners) before thinning
    lines = ndimage.binary_closing(lines, structure=np.ones((3, 3), bool)) | lines
    return lines


def thin(mask):
    return skeletonize(mask)


# ---------------------------------------------------------------- 2. graph

class Graph:
    """Nodes: id -> [x, y]; edges: id -> dict(pts=(N,2) float array, a, b) (a, b node ids or
    None for a closed edge)."""

    def __init__(self):
        self.nodes = {}
        self.edges = {}
        self.inc = {}  # node -> list of (edge id, end) with end 0 = pts[0], 1 = pts[-1]
        self._next_node = 0
        self._next_edge = 0

    def add_node(self, pos):
        i = self._next_node
        self._next_node += 1
        self.nodes[i] = np.asarray(pos, float)
        self.inc[i] = []
        return i

    def add_edge(self, pts, a, b):
        i = self._next_edge
        self._next_edge += 1
        self.edges[i] = dict(pts=np.asarray(pts, float), a=a, b=b)
        if a is not None:
            self.inc[a].append((i, 0))
            self.inc[b].append((i, 1))
        return i

    def remove_edge(self, i):
        e = self.edges.pop(i)
        if e["a"] is not None:
            self.inc[e["a"]] = [t for t in self.inc[e["a"]] if t[0] != i]
            self.inc[e["b"]] = [t for t in self.inc[e["b"]] if t[0] != i]
        return e

    def remove_node_if_isolated(self, n):
        if n in self.inc and not self.inc[n]:
            del self.inc[n]
            del self.nodes[n]

    def degree(self, n):
        return len(self.inc[n])

    def oriented(self, i, from_node_end):
        """Points of edge i starting at its end `from_node_end` (0 or 1)."""
        p = self.edges[i]["pts"]
        return p if from_node_end == 0 else p[::-1]

    def merge_degree2(self):
        changed = True
        while changed:
            changed = False
            for n in sorted(self.inc):
                if n not in self.inc or self.degree(n) != 2:
                    continue
                (e1, end1), (e2, end2) = self.inc[n]
                if e1 == e2:  # a loop hanging on n alone: becomes a closed edge
                    e = self.remove_edge(e1)
                    self.add_edge(e["pts"][:-1], None, None)
                    self.remove_node_if_isolated(n)
                    changed = True
                    continue
                p1 = self.oriented(e1, 1 - end1)  # ends at n
                p2 = self.oriented(e2, end2)      # starts at n
                o1 = self.edges[e1]["a"] if end1 == 1 else self.edges[e1]["b"]
                o2 = self.edges[e2]["b"] if end2 == 0 else self.edges[e2]["a"]
                self.remove_edge(e1)
                self.remove_edge(e2)
                self.remove_node_if_isolated(n)
                self.add_edge(np.vstack([p1, p2[1:]]), o1, o2)
                changed = True


def edge_length(pts, closed=False):
    d = np.diff(pts, axis=0)
    L = float(np.sum(np.hypot(d[:, 0], d[:, 1])))
    if closed and len(pts) > 1:
        L += float(np.hypot(*(pts[0] - pts[-1])))
    return L


def trace(skel):
    """Skeleton (bool HxW) -> Graph."""
    H, W = skel.shape
    pad = np.zeros((H + 2, W + 2), bool)
    pad[1:-1, 1:-1] = skel
    Wp = W + 2
    flat = pad.ravel()
    deg = ndimage.convolve(pad.astype(np.uint8), np.ones((3, 3), np.uint8), mode="constant") - 1
    deg = np.where(pad, deg, 0)
    node_mask = pad & (deg != 2)
    node_mask &= deg > 0
    flat[(pad & (deg == 0)).ravel()] = False  # isolated pixels
    lab, nlab = ndimage.label(node_mask, structure=np.ones((3, 3), bool))
    labf = lab.ravel()
    g = Graph()
    cluster_node = {}
    if nlab:
        idx = np.arange(1, nlab + 1)
        cy = ndimage.mean(np.indices(pad.shape)[0], lab, idx)
        cx = ndimage.mean(np.indices(pad.shape)[1], lab, idx)
        for k in range(nlab):
            cluster_node[k + 1] = g.add_node((cx[k] - 1, cy[k] - 1))
    deltas = [dy * Wp + dx for dy, dx in _OFFS]
    nodef = node_mask.ravel()
    visited = np.zeros(flat.size, bool)

    def xy(i):
        return (i % Wp - 1, i // Wp - 1)

    node_pixels = np.flatnonzero(nodef)
    for p in node_pixels:
        for d in deltas:
            q = p + d
            if not flat[q] or nodef[q] or visited[q]:
                continue
            path = [p, q]
            prev, cur = p, q
            while not nodef[cur]:
                visited[cur] = True
                nxt = -1
                for d2 in deltas:
                    r = cur + d2
                    if flat[r] and r != prev and not (visited[r] and not nodef[r]):
                        nxt = r
                        break
                if nxt < 0:
                    break
                prev, cur = cur, nxt
                path.append(cur)
            if not nodef[cur]:
                continue  # malformed chain: drop
            a, b = cluster_node[labf[p]], cluster_node[labf[cur]]
            pts = np.array([xy(i) for i in path], float)
            pts[0] = g.nodes[a]
            pts[-1] = g.nodes[b]
            g.add_edge(pts, a, b)
    # loops with no node
    rest = np.flatnonzero(flat & ~nodef & ~visited)
    for s in rest:
        if visited[s]:
            continue
        path = [s]
        visited[s] = True
        prev, cur = -1, s
        while True:
            nxt = -1
            for d2 in deltas:
                r = cur + d2
                if flat[r] and r != prev and not visited[r]:
                    nxt = r
                    break
            if nxt < 0:
                break
            visited[nxt] = True
            path.append(nxt)
            prev, cur = cur, nxt
        if len(path) >= 3:
            g.add_edge(np.array([xy(i) for i in path], float), None, None)
    return g


def prune_spurs(g, spur_len, rounds=2):
    for _ in range(rounds):
        removed = False
        for i in sorted(g.edges):
            if i not in g.edges:
                continue
            e = g.edges[i]
            if e["a"] is None:
                continue
            if e["a"] == e["b"]:  # a small loop hanging on a junction: a knot, not a line
                if edge_length(e["pts"]) < 2 * spur_len:
                    a = e["a"]
                    g.remove_edge(i)
                    g.remove_node_if_isolated(a)
                    removed = True
                continue
            da, db = g.degree(e["a"]), g.degree(e["b"])
            if (da == 1 and db >= 3) or (db == 1 and da >= 3):
                if edge_length(e["pts"]) < spur_len:
                    a, b = e["a"], e["b"]
                    g.remove_edge(i)
                    g.remove_node_if_isolated(a)
                    g.remove_node_if_isolated(b)
                    removed = True
        g.merge_degree2()
        if not removed:
            break


def pop_bubbles(g, perimeter=BUBBLE):
    """Two short edges joining the same two nodes enclose a bubble (a knot of the thinning,
    not a shape): keep the shorter one."""
    changed = True
    while changed:
        changed = False
        by_pair = {}
        for i in sorted(g.edges):
            e = g.edges[i]
            if e["a"] is None or e["a"] == e["b"]:
                continue
            by_pair.setdefault((min(e["a"], e["b"]), max(e["a"], e["b"])), []).append(i)
        for pair, ids in sorted(by_pair.items()):
            if len(ids) < 2:
                continue
            lens = sorted((edge_length(g.edges[i]["pts"]), i) for i in ids)
            if lens[0][0] + lens[1][0] < perimeter:
                g.remove_edge(lens[1][1])
                changed = True
        if changed:
            g.merge_degree2()


def suppress_texture(g, shape, density, short_len, grad=None):
    """Texture, not structure: short edges where the centerlines are dense (a weave, foliage,
    rocks, fur) form a mesh of small cells. Edges shorter than `short_len` (closed ones
    2 x) whose surroundings (MESH_WINDOW px box) are more than `density` centerline pixels
    are dropped, unless the photo edge under them is very strong (MESH_PROTECT); what is left
    of the mesh then goes as spurs and fragments. An illustrator outlines the hat and leaves
    the weave to the paint."""
    h, w = shape
    m = np.zeros(shape, np.float32)
    for e in g.edges.values():
        x = np.clip(np.rint(e["pts"][:, 0]).astype(int), 0, w - 1)
        y = np.clip(np.rint(e["pts"][:, 1]).astype(int), 0, h - 1)
        m[y, x] = 1
    dens = ndimage.uniform_filter(m, MESH_WINDOW, mode="constant")
    drop = []
    for i in sorted(g.edges):
        e = g.edges[i]
        closed = e["a"] is None
        L = edge_length(e["pts"], closed)
        if L >= (2 * short_len if closed or e["a"] == e["b"] else short_len):
            continue
        if float(np.mean(_sample(dens, e["pts"]))) <= density:
            continue
        if grad is not None and float(np.mean(_sample(grad, e["pts"]))) >= MESH_PROTECT:
            continue
        drop.append(i)
    for i in drop:
        e = g.remove_edge(i)
        if e["a"] is not None:
            g.remove_node_if_isolated(e["a"])
            g.remove_node_if_isolated(e["b"])
    g.merge_degree2()
    return len(drop)


def _components(g):
    parent = {n: n for n in g.nodes}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for e in g.edges.values():
        if e["a"] is not None:
            ra, rb = find(e["a"]), find(e["b"])
            if ra != rb:
                parent[max(ra, rb)] = min(ra, rb)
    comps = {}
    for i in sorted(g.edges):
        e = g.edges[i]
        key = ("loop", i) if e["a"] is None else ("c", find(e["a"]))
        comps.setdefault(key, []).append(i)
    return list(comps.values())


def _sample(img, pts):
    h, w = img.shape[:2]
    x = np.clip(np.rint(pts[:, 0]).astype(int), 0, w - 1)
    y = np.clip(np.rint(pts[:, 1]).astype(int), 0, h - 1)
    return img[y, x]


def prune_fragments(g, frag_len, importance, grad=None):
    """Drop components shorter than frag_len x (1.6 - importance) x (1.3 - 0.8 contrast):
    short strokes survive on the subject and where the photo edge is strong (an eye, a
    nostril), with contrast = mean photo gradient along the component / FRAG_CONTRAST_REF."""
    for comp in _components(g):
        L = 0.0
        pts = []
        for i in comp:
            e = g.edges[i]
            L += edge_length(e["pts"], closed=e["a"] is None)
            pts.append(e["pts"])
        allp = np.vstack(pts)
        imp = float(np.mean(_sample(importance, allp)))
        c = 0.5 if grad is None else min(1.0, float(np.mean(_sample(grad, allp))) / FRAG_CONTRAST_REF)
        if L < frag_len * (1.6 - imp) * (1.3 - 0.8 * c):
            for i in comp:
                e = g.remove_edge(i)
                if e["a"] is not None:
                    g.remove_node_if_isolated(e["a"])
                    g.remove_node_if_isolated(e["b"])


def _end_tangent(pts, reach=8.0):
    """Unit direction pointing out of the polyline at pts[0]."""
    acc = 0.0
    k = 1
    while k < len(pts) - 1 and acc < reach:
        acc += float(np.hypot(*(pts[k] - pts[k - 1])))
        k += 1
    v = pts[0] - pts[min(k, len(pts) - 1)]
    n = np.hypot(*v)
    return v / n if n > 1e-9 else np.array([0.0, 0.0])


def bridge_gaps(g, gap_len, cone_deg=35.0, back_deg=60.0):
    cos_cone = math.cos(math.radians(cone_deg))
    cos_back = math.cos(math.radians(back_deg))
    ends = []  # (node, edge, end)
    for n in sorted(g.inc):
        if g.degree(n) == 1:
            e, end = g.inc[n][0]
            ends.append((n, e, end))
    if not ends:
        return 0
    eids, idxs, coords = [], [], []
    for i in sorted(g.edges):
        p = g.edges[i]["pts"]
        eids.append(np.full(len(p), i))
        idxs.append(np.arange(len(p)))
        coords.append(p)
    eids = np.concatenate(eids)
    idxs = np.concatenate(idxs)
    coords = np.vstack(coords)
    tree = cKDTree(coords)
    end_of = {n: (e, end) for n, e, end in ends}
    proposals = []
    for n, e, end in ends:
        pts = g.oriented(e, end)
        t = _end_tangent(pts)
        if not t.any():
            continue
        p0 = g.nodes[n]
        L = len(g.edges[e]["pts"])
        best = None
        for j in tree.query_ball_point(p0, gap_len):
            te, ti = int(eids[j]), int(idxs[j])
            if te == e:
                along = ti if end == 0 else (L - 1 - ti)
                if along < 3 * gap_len:
                    continue
            v = coords[j] - p0
            dist = float(np.hypot(*v))
            if dist < 1.5:
                continue
            c = float(np.dot(v, t)) / dist
            if c < cos_cone:
                continue
            tl = len(g.edges[te]["pts"])
            target_node = None
            if ti == 0:
                target_node = g.edges[te]["a"]
            elif ti == tl - 1:
                target_node = g.edges[te]["b"]
            score = dist * (1 + 2 * (1 - c))
            if target_node is not None and target_node in end_of and target_node != n:
                oe, oend = end_of[target_node]
                ot = _end_tangent(g.oriented(oe, oend))
                if float(np.dot(ot, -v)) / dist < cos_back:
                    continue
                score *= 0.6  # prefer joining two loose ends
            if best is None or score < best[0]:
                best = (score, te, ti, target_node)
        if best is not None:
            proposals.append((best[0], n, best[1], best[2], best[3]))
    proposals.sort(key=lambda t: (t[0], t[1]))
    used = set()
    splits = {}  # original edge id -> list of (orig index, new node)
    orig_pts = {i: g.edges[i]["pts"] for i in g.edges}
    done = 0
    for score, n, te, ti, tnode in proposals:
        if n in used or n not in g.inc or g.degree(n) != 1:
            continue
        if tnode is not None and tnode in end_of:
            if tnode in used or tnode not in g.inc or g.degree(tnode) != 1:
                continue
            target = tnode
            used.add(tnode)
        elif tnode is not None:
            if tnode not in g.inc:
                continue
            target = tnode
        else:
            target = _split_at(g, te, ti, orig_pts, splits)
            if target is None:
                continue
        p0, p1 = g.nodes[n], g.nodes[target]
        steps = max(2, int(math.ceil(np.hypot(*(p1 - p0)))) + 1)
        seg = np.linspace(p0, p1, steps)
        g.add_edge(seg, n, target)
        used.add(n)
        done += 1
    g.merge_degree2()
    return done


def extend_to_frame(g, w, h, reach=FRAME_EXTEND, cone_deg=50.0):
    """Free ends that run into the frame are continued straight to it, so a contour leaving
    the picture seals against the canvas edge (regions cannot slip round its end)."""
    cos_cone = math.cos(math.radians(cone_deg))
    g.frame_nodes = getattr(g, "frame_nodes", set())
    for n in sorted(g.inc):
        if g.degree(n) != 1 or n in g.frame_nodes:
            continue
        e, end = g.inc[n][0]
        t = _end_tangent(g.oriented(e, end))
        p = g.nodes[n]
        best = None
        for normal, dist, fix in (((-1, 0), p[0], ("x", 0.0)), ((1, 0), w - 1 - p[0], ("x", w - 1.0)),
                                  ((0, -1), p[1], ("y", 0.0)), ((0, 1), h - 1 - p[1], ("y", h - 1.0))):
            c = t[0] * normal[0] + t[1] * normal[1]
            if dist > reach or c < cos_cone:
                continue
            travel = dist / c
            if best is None or travel < best[0]:
                best = (travel, fix)
        if best is None:
            continue
        q = p + t * best[0]
        if best[1][0] == "x":
            q[0] = best[1][1]
        else:
            q[1] = best[1][1]
        q = np.clip(q, [0, 0], [w - 1, h - 1])
        if np.hypot(*(q - p)) < 0.5:
            g.frame_nodes.add(n)
            continue
        m = g.add_node(q)
        g.frame_nodes.add(m)
        steps = max(2, int(math.ceil(np.hypot(*(q - p)))) + 1)
        g.add_edge(np.linspace(p, q, steps), n, m)
    g.merge_degree2()


def _split_at(g, orig_edge, orig_index, orig_pts, splits):
    """Split the current edge holding original point (orig_edge, orig_index); new node id."""
    target_xy = orig_pts[orig_edge][orig_index]
    # find the current edge containing that point: the original edge, or pieces of it
    candidates = [orig_edge] + splits.get(orig_edge, [])
    for ce in candidates:
        if ce not in g.edges:
            continue
        p = g.edges[ce]["pts"]
        hit = np.flatnonzero((p[:, 0] == target_xy[0]) & (p[:, 1] == target_xy[1]))
        if hit.size == 0:
            continue
        k = int(hit[0])
        e = g.edges[ce]
        if e["a"] is None:
            # closed edge: reopen at k with a node there
            node = g.add_node(p[k])
            ring = np.vstack([p[k:], p[:k + 1]])
            g.remove_edge(ce)
            new = g.add_edge(ring, node, node)
            splits.setdefault(orig_edge, []).append(new)
            return node
        if k == 0:
            return e["a"]
        if k == len(p) - 1:
            return e["b"]
        node = g.add_node(p[k])
        a, b = e["a"], e["b"]
        g.remove_edge(ce)
        l = g.add_edge(p[:k + 1], a, node)
        r = g.add_edge(p[k:], node, b)
        splits.setdefault(orig_edge, []).extend([l, r])
        return node
    return None


# ---------------------------------------------------------------- 3. strokes

def _gauss_smooth(pts, sigma, closed, pin_ends=True):
    n = len(pts)
    if n < 3 or sigma <= 0:
        return pts.copy()
    r = int(math.ceil(3 * sigma))
    k = np.exp(-np.arange(-r, r + 1) ** 2 / (2 * sigma * sigma))
    k /= k.sum()
    if closed:
        ext = np.vstack([pts[-r:], pts, pts[:r]]) if n > r else np.vstack([pts] * (2 * r // n + 3))
        if n > r:
            out = np.stack([np.convolve(ext[:, c], k, mode="valid") for c in range(2)], 1)
            return out
        return pts.copy()
    m = min(r, n - 1)
    head = 2 * pts[0] - pts[m:0:-1]
    tail = 2 * pts[-1] - pts[-2:-m - 2:-1]
    ext = np.vstack([head, pts, tail])
    kk = k if m == r else np.exp(-np.arange(-m, m + 1) ** 2 / (2 * sigma * sigma))
    kk = kk / kk.sum()
    out = np.stack([np.convolve(ext[:, c], kk, mode="valid") for c in range(2)], 1)
    if pin_ends:
        out[0], out[-1] = pts[0], pts[-1]
    return out


def _rdp(pts, eps):
    n = len(pts)
    if n < 3:
        return np.arange(n)
    keep = np.zeros(n, bool)
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a, b = pts[i], pts[j]
        ab = b - a
        L = np.hypot(*ab)
        seg = pts[i + 1:j] - a
        if L < 1e-9:
            d = np.hypot(seg[:, 0], seg[:, 1])
        else:
            d = np.abs(seg[:, 0] * ab[1] - seg[:, 1] * ab[0]) / L
        k = int(np.argmax(d))
        if d[k] > eps:
            m = i + 1 + k
            keep[m] = True
            stack.append((i, m))
            stack.append((m, j))
    return np.flatnonzero(keep)


def build_strokes(g, join_deg=45.0):
    """Join edges through junctions into strokes. Returns list of dict(pts, closed,
    free=(bool, bool), junctions=[(index, node)])."""
    cos_join = math.cos(math.radians(join_deg))
    link = {}  # (edge, end) -> (edge, end)
    for n in sorted(g.inc):
        inc = g.inc[n]
        if len(inc) < 3:
            continue
        tans = [_end_tangent(g.oriented(e, end)) for e, end in inc]
        pairs = []
        for i in range(len(inc)):
            for j in range(i + 1, len(inc)):
                if inc[i][0] == inc[j][0]:
                    continue
                c = -float(np.dot(tans[i], tans[j]))
                if c >= cos_join:
                    pairs.append((-c, i, j))
        pairs.sort()
        paired = set()
        for _, i, j in pairs:
            if i in paired or j in paired:
                continue
            paired.update((i, j))
            link[inc[i]] = inc[j]
            link[inc[j]] = inc[i]
    strokes = []
    seen = set()

    def node_at(e, end):
        return g.edges[e]["a"] if end == 0 else g.edges[e]["b"]

    def walk(e, end):
        """Start at edge e entering from its end `end`; follow links."""
        chain = []
        juncs = []
        cur_e, cur_end = e, end
        closed = False
        while True:
            seen.add(cur_e)
            pts = g.oriented(cur_e, cur_end)
            if chain:
                juncs.append((sum(len(c) for c in chain) - len(chain) + 1 - 1, node_at(cur_e, cur_end)))
            chain.append(pts)
            out_end = 1 - cur_end
            nxt = link.get((cur_e, out_end))
            if nxt is None:
                break
            if nxt[0] in seen:
                if nxt[0] == e and nxt[1] == end:
                    closed = True
                break
            cur_e, cur_end = nxt
        pts = chain[0]
        for c in chain[1:]:
            pts = np.vstack([pts, c[1:]])
        last_node = node_at(cur_e, 1 - cur_end)
        return pts, closed, juncs, last_node

    for i in sorted(g.edges):
        if i in seen:
            continue
        e = g.edges[i]
        if e["a"] is None:
            seen.add(i)
            strokes.append(dict(pts=e["pts"], closed=True, free=(False, False), junctions=[],
                                end_nodes=(None, None)))
            continue
    # open strokes start at unlinked ends
    for i in sorted(g.edges):
        if i in seen:
            continue
        for end in (0, 1):
            if (i, end) not in link:
                pts, closed, juncs, last = walk(i, end)
                first = node_at(i, end)
                fr = getattr(g, "frame_nodes", set())
                strokes.append(dict(pts=pts, closed=False,
                                    free=(g.degree(first) == 1 and first not in fr,
                                          g.degree(last) == 1 and last not in fr),
                                    junctions=juncs, end_nodes=(first, last)))
                break
    # what is left is made of cycles through junctions
    for i in sorted(g.edges):
        if i in seen:
            continue
        pts, closed, juncs, last = walk(i, 0)
        first = node_at(i, 0)
        if closed:
            pts = pts[:-1]
            juncs.append((0, first))
        strokes.append(dict(pts=pts, closed=closed, free=(False, False), junctions=juncs,
                            end_nodes=(first, last)))
    return strokes


def finish_strokes(g, strokes):
    """Smooth, record junction points for walls, simplify."""
    out = []
    for s in strokes:
        pts = s["pts"]
        if len(pts) < 2:
            continue
        dense = _gauss_smooth(pts, SMOOTH_SIGMA, s["closed"])
        links = []
        for idx, node in s["junctions"]:
            idx = min(max(idx, 0), len(dense) - 1)
            links.append((dense[idx], g.nodes[node]))
        for k, node in zip((0, -1), s.get("end_nodes", (None, None))):
            if node is not None and not s["closed"]:
                links.append((dense[k], g.nodes[node]))
        keep = _rdp(dense, SIMPLIFY_EPS) if not s["closed"] else _rdp_closed(dense, SIMPLIFY_EPS)
        out.append(dict(dense=dense, pts=dense[keep], closed=s["closed"], free=s["free"],
                        links=links, length=edge_length(dense, s["closed"])))
    return out


def _rdp_closed(pts, eps):
    if len(pts) < 4:
        return np.arange(len(pts))
    far = int(np.argmax(np.hypot(*(pts - pts[0]).T)))
    a = _rdp(pts[:far + 1], eps)
    b = _rdp(np.vstack([pts[far:], pts[:1]]), eps) + far
    idx = np.concatenate([a, b[1:-1]])
    return np.unique(idx)


# ---------------------------------------------------------------- 4. weights and colors

def _normals(pts, closed):
    if closed:
        d = np.roll(pts, -1, 0) - np.roll(pts, 1, 0)
    else:
        d = np.gradient(pts, axis=0) if len(pts) > 1 else np.array([[1.0, 0.0]])
    n = np.hypot(d[:, 0], d[:, 1])[:, None]
    d = d / np.maximum(n, 1e-9)
    return np.stack([-d[:, 1], d[:, 0]], 1)


def _bilinear(img, pts):
    h, w = img.shape[:2]
    x = np.clip(pts[:, 0], 0, w - 1.001)
    y = np.clip(pts[:, 1], 0, h - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    if img.ndim == 3:
        fx, fy = fx[:, None], fy[:, None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def _arclen(pts):
    d = np.hypot(*np.diff(pts, axis=0).T) if len(pts) > 1 else np.zeros(0)
    return np.concatenate([[0.0], np.cumsum(d)])


def weigh(strokes, lab_smooth, importance, raster_lab=None):
    for s in strokes:
        p = s["pts"]
        nrm = _normals(p, s["closed"])
        a = _bilinear(lab_smooth, p + SIDE_OFFSET * nrm)
        b = _bilinear(lab_smooth, p - SIDE_OFFSET * nrm)
        de = np.linalg.norm(a - b, axis=1)
        s["contrast"] = float(np.mean(de))
        s["importance"] = float(np.mean(_bilinear(importance, p)))
        c = min(1.0, s["contrast"] / CONTRAST_REF) ** 0.7
        lf = 0.85 + 0.15 * min(1.0, s["length"] / 150.0)
        w = (W_MIN + (W_MAX - W_MIN) * c) * (0.7 + 0.3 * s["importance"]) * lf
        s["w"] = float(w)
        s["width"] = np.full(len(p), w)
        # taper: thinned towards the ends like a brush stroke, and swelling where the edge
        # under it is stronger (per-point contrast, smoothed along the stroke, +-25%)
        t = _arclen(p)
        L = t[-1] if len(t) else 0.0
        local = de.copy()
        if len(local) > 5:
            local = ndimage.gaussian_filter1d(local, 3.0, mode="wrap" if s["closed"] else "nearest")
        press = np.clip(0.75 + 0.25 * local / max(float(np.mean(local)), 1e-6), 0.6, 1.25)
        if s["closed"]:
            s["width_tapered"] = w * press
        else:
            ramp = max(2.0, min(30.0, L / 2.5))
            def prof(d, free):
                lo = 0.12 if free else 0.5
                return lo + (1 - lo) * np.clip(d / ramp, 0, 1) ** 0.6
            s["width_tapered"] = w * press * prof(t, s["free"][0]) * prof(L - t, s["free"][1])
        s["width_uniform"] = np.full(len(p), UNIFORM_WIDTH)
        if raster_lab is not None:
            ra = _sample(raster_lab, p + SIDE_OFFSET * nrm)
            rb = _sample(raster_lab, p - SIDE_OFFSET * nrm)
            dark = np.where((ra[:, 0] <= rb[:, 0])[:, None], ra, rb)
            k = np.ones(9) / 9.0
            if len(dark) > 9:
                mode = "wrap" if s["closed"] else "nearest"
                dark = np.stack([ndimage.convolve1d(dark[:, c], k, mode=mode) for c in range(3)], 1)
            L_ = np.minimum(dark[:, 0] * 0.55, 0.38)
            col = np.stack([L_, dark[:, 1] * 1.1, dark[:, 2] * 1.1], 1)
            s["color"] = lc.oklab_to_rgb8(col)
    return strokes


# ---------------------------------------------------------------- 5. walls and ink

def walls(strokes, w, h):
    m = np.zeros((h, w), np.uint8)

    def seg(p, q):
        x0, y0 = int(round(p[0])), int(round(p[1]))
        x1, y1 = int(round(q[0])), int(round(q[1]))
        rr, cc = draw_line(y0, x0, y1, x1)
        ok = (rr >= 0) & (rr < h) & (cc >= 0) & (cc < w)
        m[rr[ok], cc[ok]] = 255

    for s in strokes:
        d = s["dense"]
        for i in range(len(d) - 1):
            seg(d[i], d[i + 1])
        if s["closed"]:
            seg(d[-1], d[0])
        for p, q in s["links"]:
            seg(p, q)
        if len(d) == 1:
            seg(d[0], d[0])
    return m


def render(strokes, w, h, width_key="width", color_key=None, scale=2):
    """Anti-aliased ink (variable-width capsules) -> RGBA uint8 at scale x working size."""
    W, H = w * scale, h * scale
    alpha = np.zeros((H, W), np.float32)
    rgb = np.zeros((H, W, 3), np.float32)
    rgb[:] = np.array(lc.INK, np.float32)
    for s in strokes:
        p = s["pts"] * scale + (scale - 1) / 2.0  # pixel centers: working (x,y) -> 2x
        r = s[width_key] * scale / 2.0
        col = s.get(color_key) if color_key else None
        n = len(p)
        segs = [(i, i + 1) for i in range(n - 1)]
        if s["closed"] and n > 2:
            segs.append((n - 1, 0))
        if n == 1:
            segs = [(0, 0)]
        for i, j in segs:
            a, b = p[i], p[j]
            ra, rb = r[i], r[j]
            rm = max(ra, rb) + 1.0
            x0 = max(int(math.floor(min(a[0], b[0]) - rm)), 0)
            x1 = min(int(math.ceil(max(a[0], b[0]) + rm)) + 1, W)
            y0 = max(int(math.floor(min(a[1], b[1]) - rm)), 0)
            y1 = min(int(math.ceil(max(a[1], b[1]) + rm)) + 1, H)
            if x0 >= x1 or y0 >= y1:
                continue
            yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
            ab = b - a
            L2 = float(ab @ ab)
            if L2 < 1e-12:
                t = np.zeros_like(xx)
            else:
                t = np.clip(((xx - a[0]) * ab[0] + (yy - a[1]) * ab[1]) / L2, 0, 1)
            dx = xx - (a[0] + t * ab[0])
            dy = yy - (a[1] + t * ab[1])
            dist = np.sqrt(dx * dx + dy * dy)
            rad = ra + t * (rb - ra)
            cov = np.clip(rad - dist + 0.5, 0, 1)
            box = alpha[y0:y1, x0:x1]
            if col is not None:
                better = cov > box
                if better.any():
                    c = (col[i].astype(np.float32) * (1 - t[..., None]) + col[j].astype(np.float32) * t[..., None])
                    rgb[y0:y1, x0:x1][better] = c[better]
            np.maximum(box, cov, out=box)
    out = np.zeros((H, W, 4), np.uint8)
    out[..., :3] = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(np.rint(alpha * 255), 0, 255).astype(np.uint8)
    return out


def on_paper(rgba):
    a = rgba[..., 3:4].astype(np.float32) / 255.0
    paper = np.array(lc.PAPER, np.float32)
    out = paper * (1 - a) + rgba[..., :3].astype(np.float32) * a
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- driver for one map

def extract(raw, importance, high, low, detail, fill_level=None, grad=None):
    """raw map -> (graph, strokes before weighting). `grad`: the photo's OKLab gradient
    magnitude (lines_common.oklab_gradient, sigma 1), protects strong edges from the
    texture suppression."""
    d = DETAIL[detail]
    mask = binarize(raw, importance, high, low, fill_level, d.get("clutter"), grad)
    skel = thin(mask)
    g = trace(skel)
    g.merge_degree2()
    pop_bubbles(g)
    prune_spurs(g, d["spur"])
    for _ in range(2):
        suppress_texture(g, raw.shape, d["mesh_density"], d["mesh_len"], grad)
        prune_spurs(g, d["spur"], rounds=1)
    prune_fragments(g, 4.0, np.zeros_like(importance) + 0.6)  # specks
    bridge_gaps(g, d["gap"])
    prune_spurs(g, d["spur"], rounds=1)
    prune_fragments(g, d["frag"], importance, grad)
    g.merge_degree2()
    extend_to_frame(g, raw.shape[1], raw.shape[0])
    strokes = finish_strokes(g, build_strokes(g))
    return g, strokes


def to_json(strokes, w, h):
    out = []
    for s in strokes:
        item = {
            "points": [[round(float(x), 2), round(float(y), 2)] for x, y in s["pts"]],
            "closed": bool(s["closed"]),
            "width": [round(float(v), 3) for v in s["width"]],
            "width_tapered": [round(float(v), 3) for v in s["width_tapered"]],
            "contrast": round(s["contrast"], 4),
            "importance": round(s["importance"], 4),
            "free_ends": [bool(s["free"][0]), bool(s["free"][1])],
        }
        if "color" in s:
            item["color"] = ["%02x%02x%02x" % tuple(int(v) for v in c) for c in s["color"]]
        out.append(item)
    return {"width": int(w), "height": int(h), "strokes": out}
