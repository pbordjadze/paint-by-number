"""Exact arithmetic for the making-of show's discrete decisions: where the crew stands and which
pixel a seed lands on.

Everything here is integer arithmetic or IEEE double arithmetic made of `+ - * /` and `sqrt` in a
fixed order, so Sources/MakingOf (ExactMath.swift, Labeling.swift, ...) gets the same bits on any
platform and the tests compare with `==`. What is deliberately not used: `**` and `pow`, `cbrt`,
`hypot`, `np.percentile`, `np.linspace`, `np.sum` (pairwise) and `rng.choice`, whose last bits differ
between libraries. A decision that turns on a comparison (a weighted pick, a spacing test, an
argmin) is made only from these, so it can never flip between the factory and the app.

Needs numpy.
"""

import numpy as np

# The sRGB transfer curve decoded, for each byte: the true value of
# `c / 12.92` (c <= 0.04045) or `((c + 0.055) / 1.055) ** 2.4` at c = i / 255, to 60 digits and then
# rounded once to a double, so no library's `pow` is in it. ExactMath.swift holds the same literals.
SRGB_LINEAR = (
    0.0, 0.0003035269835488375, 0.000607053967097675,
    0.0009105809506465125, 0.00121410793419535, 0.0015176349177441874,
    0.001821161901293025, 0.0021246888848418626, 0.0024282158683907,
    0.0027317428519395373, 0.003035269835488375, 0.0033465357638991586,
    0.003676507324047435, 0.004024717018496304, 0.0043914420374102925,
    0.0047769534806937275, 0.005181516702338385, 0.005605391624202721,
    0.006048833022857052, 0.006512090792594472, 0.006995410187265385,
    0.00749903204322617, 0.008023192985384993, 0.008568125618069302,
    0.009134058702220785, 0.009721217320237844, 0.010329823029626936,
    0.01096009400648824, 0.011612245179743881, 0.012286488356915867,
    0.012983032342173007, 0.013702083047289683, 0.014443843596092541,
    0.015208514422912706, 0.015996293365509628, 0.016807375752887377,
    0.017641954488384078, 0.01850022012837969, 0.019382360956935723,
    0.02028856305665239, 0.021219010376003555, 0.022173884793387375,
    0.023153366178110403, 0.02415763244850475, 0.025186859627361623,
    0.02624122189484989, 0.02732089163907489, 0.028426039504420787,
    0.029556834437808797, 0.03071344373299362, 0.03189603307301152,
    0.03310476657088505, 0.03433980680868216, 0.03560131487502032,
    0.03688945040110002, 0.03820437159534648, 0.03954623527673283,
    0.04091519690685317, 0.042311410620809654, 0.04373502925697345,
    0.04518620438567554, 0.04666508633688008, 0.048171824226889405,
    0.04970656598412722, 0.051269458374043224, 0.05286064702318025,
    0.054480276442442355, 0.05612849004960008, 0.05780543019106721,
    0.059511238162981185, 0.061246054231617594, 0.06301001765316766,
    0.06480326669290576, 0.06662593864377288, 0.06847816984440015,
    0.07036009569659588, 0.07227185068231748, 0.07421356838014961,
    0.07618538148130781, 0.07818742180518633, 0.08021982031446831,
    0.0822827071298148, 0.08437621154414877, 0.08650046203654974,
    0.08865558628577294, 0.09084171118340768, 0.09305896284668742,
    0.09530746663096466, 0.09758734714186242, 0.09989872824711389,
    0.10224173308810128, 0.10461648409110416, 0.10702310297826759,
    0.10946171077829933, 0.11193242783690557, 0.11443537382697372,
    0.11697066775851081, 0.1195384279883456, 0.12213877222960184,
    0.12477181756095046, 0.12743768043564743, 0.13013647669036427,
    0.13286832155381792, 0.13563332965520564, 0.13843161503245183,
    0.14126329114027164, 0.14412847085805772, 0.14702726649759498,
    0.14995978981060853, 0.15292615199615014, 0.15592646370782734,
    0.15896083506088035, 0.162029375639111, 0.1651321945016676,
    0.1682694001896907, 0.17144110073282254, 0.17464740365558498,
    0.17788841598362912, 0.18116424424986013, 0.1844749945004409,
    0.18782077230067779, 0.19120168274079136, 0.1946178304415757,
    0.1980693195599488, 0.20155625379439707, 0.2050787363903169,
    0.20863687014525567, 0.2122307574140551, 0.21586050011389915,
    0.21952619972926918, 0.22322795731680842, 0.22696587351009834,
    0.23074004852434896, 0.23455058216100508, 0.23839757381227095,
    0.24228112246555472, 0.2462013267078354, 0.2501582847299533,
    0.2541520943308267, 0.25818285292159576, 0.262250657529696,
    0.2663556048028623, 0.27049779101306576, 0.27467731206038454,
    0.27889426347681034, 0.28314874042999194, 0.2874408377269174,
    0.29177064981753587, 0.29613827079832095, 0.3005437944157764,
    0.3049873140698861, 0.30946892281750843, 0.3139887133757175,
    0.31854677812509175, 0.3231432091129507, 0.32777809805654207,
    0.3324515363461792, 0.33716361504833026, 0.34191442490866075,
    0.3467040563550295, 0.3515325995004392, 0.3564001441459434,
    0.36130677978350945, 0.3662525955988394, 0.37123768047414896,
    0.3762621229909062, 0.38132601143253, 0.3864294337870489,
    0.3915724777497231, 0.3967552307256268, 0.4019777798321956,
    0.40724021190173665, 0.4125426134839036, 0.41788507084813725,
    0.4232676699860715, 0.42869049661390657, 0.4341536361747488,
    0.43965717384091874, 0.44520119451622775, 0.45078578283822335,
    0.4564110231804045, 0.46207699965440685, 0.4677837961121588,
    0.4735314961480093, 0.47932018310082664, 0.4851499400560704,
    0.49102084984783545, 0.49693299506087035, 0.5028864580325684,
    0.5088813208549335, 0.5149176653765213, 0.5209955732043541,
    0.527115125705813, 0.533276404010505, 0.539479489012107,
    0.5457244613701866, 0.5520114015119999, 0.5583403896342677,
    0.5647115057049289, 0.5711248294648729, 0.5775804404296505,
    0.584078417891164, 0.5906188409193368, 0.5972017883637631,
    0.6038273388553375, 0.6104955708078647, 0.6172065624196509,
    0.6239603916750759, 0.6307571363461467, 0.6375968739940324,
    0.644479681970582, 0.6514056374198239, 0.6583748172794482,
    0.6653872982822719, 0.6724431569576873, 0.6795424696330937,
    0.6866853124353132, 0.6938717612919898, 0.7011018919329731,
    0.7083757798916867, 0.7156935005064805, 0.7230551289219689,
    0.7304607400903533, 0.7379104087727307, 0.7454042095403872,
    0.7529422167760778, 0.7605245046752922, 0.7681511472475069,
    0.7758222183174234, 0.7835377915261932, 0.79129794033263,
    0.7991027380144087, 0.8069522576692514, 0.8148465722161011,
    0.8227857543962833, 0.8307698767746545, 0.8387990117407399,
    0.8468732315098577, 0.8549926081242336, 0.863157213454102,
    0.8713671191987971, 0.8796223968878317, 0.8879231178819664,
    0.8962693533742666, 0.9046611743911491, 0.9130986517934189,
    0.9215818562772945, 0.9301108583754234, 0.9386857284578878,
    0.9473065367331996, 0.955973353249286, 0.9646862478944651,
    0.9734452903984123, 0.982250550333117, 0.9911020971138297,
    1.0,
)

_LINEAR = np.array(SRGB_LINEAR)

# Newton steps for the cube root. From 1.0 the iteration needs about 16 to settle for the smallest
# value a byte colour can have (1.5e-5), so 32 leave no input unsettled.
CBRT_STEPS = 32


def half_even(x):
    """`x` rounded to the nearest integer, halves to the even one (Python's `round`)."""
    return round(x)


def quantize(x, places):
    """`x` to `places` decimals as `half_even(x * 10^places) / 10^places`: the plan file's precision,
    written so that the Swift port reproduces it (Python's `round(x, n)` has no short equivalent)."""
    scale = float(10 ** places)
    return half_even(x * scale) / scale


def cbrt(x):
    """The cube root of non-negative doubles (a scalar or an array) by a fixed number of Newton steps
    from 1.0: the same operations in the same order wherever it runs. 0 stays 0."""
    x = np.asarray(x, dtype=np.float64)
    y = np.ones_like(x)
    for _ in range(CBRT_STEPS):
        y = (y + y + x / (y * y)) / 3
    return np.where(x > 0, y, 0.0)


def oklab(rgb):
    """OKLab of byte colours (`(..., 3)` uint8), in doubles: L, a, b with the chroma axes left
    unstretched. Same constants as `oklab` in making_of_layers.py."""
    lin = _LINEAR[np.asarray(rgb, dtype=np.int64)]
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return np.stack([0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s], axis=-1)


def box_sum(a, r):
    """Sums of the integer plane `a` over the window of radius `r` around each cell, a window that
    sticks out of the plane counting the edge cell again (`np.pad(mode='edge')`): rows, then columns."""
    a = np.asarray(a, dtype=np.int64)
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode='edge'), axis=axis)
        a = np.take(c, np.arange(2 * r + 1, c.shape[axis]), axis=axis) \
            - np.take(c, np.arange(0, c.shape[axis] - 2 * r - 1), axis=axis)
    return a


def percentile(values, percent):
    """The `percent`th percentile (an integer) of integer `values`, linear between the two ranks
    around it, as numpy's default but written out: `lo + (hi - lo) * rem / 100` with the rank
    `(n - 1) * percent / 100` split into a whole part and `rem` hundredths."""
    s = np.sort(np.asarray(values, dtype=np.int64).ravel())
    lo, rem = divmod((len(s) - 1) * percent, 100)
    a, b = int(s[lo]), int(s[min(lo + 1, len(s) - 1)])
    return float(a) + float((b - a) * rem) / 100.0


def cumulative(weights):
    """Running sums of `weights` in index order, each added to the one before (never pairwise)."""
    return np.cumsum(np.asarray(weights, dtype=np.float64))


def bisect_right(cdf, v):
    """How many entries of the nondecreasing `cdf` are <= `v` (an array of `v`s gives an array):
    the index of the first entry past `v`, which has weight when `0 <= v < cdf[-1]`."""
    return np.searchsorted(cdf, v, side='right')


def color_keys(rgb):
    """One integer per byte colour, `r << 16 | g << 8 | b`; equal keys are equal colours."""
    q = np.asarray(rgb, dtype=np.int64)
    return (q[..., 0] << 16) | (q[..., 1] << 8) | q[..., 2]


def label_regions(keys):
    """Connected areas of one key (4-connected), by runs and union-find: (labels, count). Areas are
    numbered by where their first run starts, rows top to bottom and left to right within a row."""
    h, w = keys.shape
    parent = []

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    rows = []
    for y in range(h):
        row = keys[y]
        cuts = np.flatnonzero(row[1:] != row[:-1]) + 1
        starts = np.concatenate(([0], cuts))
        ends = np.concatenate((cuts, [w]))
        ids = list(range(len(parent), len(parent) + len(starts)))
        parent.extend(ids)
        rows.append((starts, ends, row[starts], ids))
        if y:
            ps, pe, pv, pid = rows[y - 1]
            i = j = 0
            while i < len(starts) and j < len(ps):
                if starts[i] < pe[j] and ps[j] < ends[i] and row[starts[i]] == pv[j]:
                    a, b = find(ids[i]), find(pid[j])
                    if a != b:
                        parent[max(a, b)] = min(a, b)
                if ends[i] < pe[j]:
                    i += 1
                else:
                    j += 1
    roots = {}
    labels = np.empty((h, w), dtype=np.int32)
    for y, (starts, ends, _, ids) in enumerate(rows):
        lab = [roots.setdefault(find(r), len(roots)) for r in ids]
        labels[y] = np.repeat(lab, ends - starts)
    return labels, len(roots)


def line_mask(width, height, strokes, half_width):
    """The pixels whose centre is within `half_width` of a stroke (polylines of `(x, y)`, in pixels
    with the origin at the picture's corner): True where a line runs. Standing in for the rasterized
    lines, so a decision never depends on a rasterizer's anti-aliasing. Plain arithmetic and no
    square root: the squared distance to the nearest point of each segment against `half_width`
    squared."""
    mask = np.zeros((height, width), dtype=bool)
    reach = half_width * half_width
    for stroke in strokes:
        for (ax, ay), (bx, by) in zip(stroke, stroke[1:]):
            x0 = max(int(np.floor(min(ax, bx) - half_width)) - 1, 0)
            x1 = min(int(np.floor(max(ax, bx) + half_width)) + 2, width)
            y0 = max(int(np.floor(min(ay, by) - half_width)) - 1, 0)
            y1 = min(int(np.floor(max(ay, by) + half_width)) + 2, height)
            if x0 >= x1 or y0 >= y1:
                continue
            px = np.arange(x0, x1, dtype=np.float64)[None, :] + 0.5
            py = np.arange(y0, y1, dtype=np.float64)[:, None] + 0.5
            vx, vy = bx - ax, by - ay
            wx, wy = px - ax, py - ay
            length2 = vx * vx + vy * vy
            if length2 > 0:
                t = np.clip((wx * vx + wy * vy) / length2, 0.0, 1.0)
            else:
                t = np.zeros_like(wx + wy)
            dx = px - (ax + t * vx)
            dy = py - (ay + t * vy)
            mask[y0:y1, x0:x1] |= dx * dx + dy * dy <= reach
    return mask
