#!/usr/bin/env python3
"""Hands for "draw it from scratch": a cat, a house with a tree and a face drawn freehand on a Blank
canvas by simulated fingers, then colored with the Bucket, replayed off the device by `pbn refine`.

    tools/refine_from_scratch.py [--pbn .build/release/pbn] [--out <dir>] [--seeds 6]
                                 [--hands careful,casual,sloppy] [--subjects cat,house,face]

Maestro's swipes are straight and exact, so a simulator run can't say how a finger fares; this
can. Each subject is a list of strokes as a person draws them (a loop drawn round and closed by
eye, an ear or a roof begun and ended on a line already there), followed through a finger: points
every few screen points with a slow wobble, and each end that should land on a line or on the
loop's start missing it by a random distance, short or past (`careful` 0-4 pt, `casual` 3-9,
`sloppy` 7-15: a fingertip's miss is about 5-8). Snap on, Smoothing off (the Toolbox's defaults),
on a 13" iPad's picture (960 points wide). Then a Bucket pour into each shape, each its own color.

It scores what a newcomer would see: a shape is `closed` when its pour colored it and nothing
outside it (the pour's color covers at least 90% of the shape and leaks under 5% of the shape's
area outside it); otherwise it `leaked` (paint ran out through a gap) or was `split`. Prints a
table per hand (shapes closed out of shapes drawn, over seeds) and writes, per subject, hand and
seed, the `pbn refine` folder (`refine.json`, `after.ppm`) and a strip `<out>/<hand>.png` of every
subject's first seeds. Written for the from-scratch loop of November 3 (Refine, painting-company
row 175's sequel); run it after a change to PenAssist, Snap's reach or the editor's draw, and
compare. Needs pbn built (`tools/swift.sh build -c release --static-swift-stdlib`) and Pillow.
"""
import argparse, json, math, os, random, subprocess, sys

from PIL import Image, ImageDraw

ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--pbn", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".build", "release", "pbn"))
ap.add_argument("--out", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "refine-from-scratch"))
ap.add_argument("--seeds", type=int, default=6)
ap.add_argument("--hands", default="careful,casual,sloppy")
ap.add_argument("--subjects", default="cat,house,face")
ap.add_argument("--smoothing", type=float, default=None, help="the Pen's Smoothing, 0...1 (default off)")
opts = ap.parse_args()
PBN = os.path.abspath(opts.pbn)
OUT = os.path.abspath(opts.out)
os.makedirs(OUT, exist_ok=True)

W, H = 960.0, 720.0           # the picture on screen, points
PHOTO = os.path.join(OUT, "paper.ppm")
with open(PHOTO, "wb") as f:  # a plain light photo, 1200x900, as the practice picture's size
    f.write(b"P6 1200 900 255\n" + bytes([236, 232, 222]) * (1200 * 900))

HANDS = {"careful": (0, 4), "casual": (3, 9), "sloppy": (7, 15)}

# --- shapes, in screen points --------------------------------------------------------------

def ellipse(cx, cy, rx, ry, a0=0.0, a1=2 * math.pi, n=None):
    n = n or max(12, int(abs(a1 - a0) * max(rx, ry) / 4))
    return [(cx + rx * math.cos(a0 + (a1 - a0) * k / n), cy + ry * math.sin(a0 + (a1 - a0) * k / n)) for k in range(n + 1)]

def poly(*pts):
    out = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(2, int(math.hypot(x1 - x0, y1 - y0) / 4))
        out += [(x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n) for k in range(n)]
    out.append(pts[-1])
    return out

def inside_ellipse(cx, cy, rx, ry):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 1

def inside_poly(*pts):
    def f(x, y):
        c = False
        for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
            if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
                c = not c
        return c
    return f

# A subject: strokes (points, which ends must land on a line: "loop" closes on its start,
# "ends" lands both on earlier lines, "none" free), and shapes (name, inside test, a point to pour
# in, rgb). A shape's inside test excludes the shapes drawn on top of it.
def cat():
    head = (480, 250, 105, 92); body = (480, 500, 150, 150)
    ear_l = [(398, 196), (405, 112), (452, 162)]
    ear_r = [(508, 162), (555, 112), (562, 196)]
    eye_l = (440, 240, 16, 12); eye_r = (520, 240, 16, 12)
    nose = [(468, 280), (492, 280), (480, 295)]
    # The body starts and ends on the head's circle, below it: from the left of the chin round.
    a_l = math.radians(122); a_r = math.radians(58)
    hx, hy, hrx, hry = head
    p_l = (hx + hrx * math.cos(a_l), hy + hry * math.sin(a_l)); p_r = (hx + hrx * math.cos(a_r), hy + hry * math.sin(a_r))
    bx, by, brx, bry = body
    body_arc = [p_l] + ellipse(bx, by, brx, bry, math.radians(-118), math.radians(-62) - 2 * math.pi)[1:-1] + [p_r]
    def on_body(y):  # the point of the body's outline at height y, on its right
        return (bx + brx * math.sqrt(1 - ((y - by) / bry) ** 2), y)
    tail = [on_body(560), (690, 545), (740, 480), (735, 400), (712, 398), (712, 470), (680, 520), on_body(528)]
    strokes = [
        (ellipse(*head), "loop"), (poly(*ear_l), "ends"), (poly(*ear_r), "ends"),
        (body_arc, "ends"), (tail, "ends"),
        (ellipse(*eye_l), "loop"), (ellipse(*eye_r), "loop"), (poly(*nose, nose[0]), "loop"),
    ]
    ih = inside_ellipse(*head); ib = inside_ellipse(*body)
    ie = [inside_ellipse(*eye_l), inside_ellipse(*eye_r)]; inn = inside_poly(*nose)
    def tail_in(x, y):
        return inside_poly(*tail)(x, y) and not ib(x, y)
    shapes = [
        ("head", lambda x, y: ih(x, y) and not any(e(x, y) for e in ie) and not inn(x, y), (480, 315), (0.95, 0.6, 0.2)),
        ("left ear", lambda x, y: inside_poly(*ear_l)(x, y) and not ih(x, y), (420, 165), (0.98, 0.75, 0.75)),
        ("right ear", lambda x, y: inside_poly(*ear_r)(x, y) and not ih(x, y), (540, 165), (0.98, 0.62, 0.82)),
        ("body", lambda x, y: ib(x, y) and not ih(x, y), (480, 520), (0.85, 0.45, 0.1)),
        ("tail", tail_in, (722, 440), (0.6, 0.3, 0.05)),
        ("left eye", ie[0], (440, 240), (0.3, 0.7, 0.3)),
        ("right eye", ie[1], (520, 240), (0.2, 0.55, 0.65)),
        ("nose", inn, (480, 285), (0.9, 0.3, 0.5)),
    ]
    return strokes, shapes

def house():
    wall = [(250, 380), (530, 380), (530, 620), (250, 620)]
    roof = [(225, 380), (390, 240), (555, 380)]
    door = [(360, 620), (360, 500), (420, 500), (420, 620)]
    win = [(450, 430), (505, 430), (505, 480), (450, 480)]
    trunk = [(735, 620), (735, 470), (775, 470), (775, 620)]
    crown = (755, 400, 90, 85)
    ground = [(80, 620), (900, 620)]
    strokes = [
        (poly(*ground), "none"), (poly(wall[0], wall[1], wall[2], wall[3], wall[0]), "loop"),
        (poly(*roof), "ends"), (poly(*door), "ends"), (poly(*win, win[0]), "loop"),
        (poly(*trunk), "ends"), (ellipse(*crown, a0=math.radians(115), a1=math.radians(65) - 2 * math.pi), "ends"),
    ]
    iw = inside_poly(*wall); idoor = inside_poly(*door); iwin = inside_poly(*win)
    icr = inside_ellipse(*crown); itr = inside_poly(*trunk)
    shapes = [
        ("wall", lambda x, y: iw(x, y) and not idoor(x, y) and not iwin(x, y), (300, 450), (0.95, 0.85, 0.6)),
        ("roof", lambda x, y: inside_poly(*roof)(x, y) and y < 380, (390, 330), (0.75, 0.2, 0.15)),
        ("door", idoor, (390, 560), (0.45, 0.25, 0.1)),
        ("window", iwin, (477, 455), (0.6, 0.8, 0.95)),
        ("trunk", lambda x, y: itr(x, y) and not icr(x, y), (755, 560), (0.45, 0.3, 0.15)),
        ("crown", icr, (755, 380), (0.2, 0.6, 0.25)),
    ]
    return strokes, shapes

def face():
    head = (480, 360, 190, 230)
    eye_l = (405, 300, 32, 20); eye_r = (555, 300, 32, 20)
    nose = [(480, 330), (455, 420), (505, 420)]
    mouth_top = ellipse(480, 470, 80, 18, math.pi, 2 * math.pi)
    mouth_bot = ellipse(480, 470, 80, 40, 0, math.pi)
    hair = ellipse(480, 360, 190, 230, math.radians(200), math.radians(340))
    hair_line = [hair[0], (380, 215), (480, 190), (580, 215), hair[-1]]
    strokes = [
        (ellipse(*head), "loop"), (ellipse(*eye_l), "loop"), (ellipse(*eye_r), "loop"),
        (poly(*nose, nose[0]), "loop"), (mouth_top, "none"), (list(reversed(mouth_bot)), "ends"),
        (poly(*hair_line), "ends"),
    ]
    ih = inside_ellipse(*head); iel = inside_ellipse(*eye_l); ier = inside_ellipse(*eye_r); inn = inside_poly(*nose)
    im = lambda x, y: (y >= 470 and inside_ellipse(480, 470, 80, 40)(x, y)) or (y < 470 and inside_ellipse(480, 470, 80, 18)(x, y))
    hair_in = inside_poly(*hair_line, *reversed(hair))
    shapes = [
        ("face", lambda x, y: ih(x, y) and not (iel(x, y) or ier(x, y) or inn(x, y) or im(x, y) or hair_in(x, y)), (330, 420), (0.98, 0.82, 0.68)),
        ("hair", lambda x, y: hair_in(x, y) and ih(x, y), (480, 170), (0.35, 0.2, 0.1)),
        ("left eye", iel, (405, 300), (0.25, 0.45, 0.8)),
        ("right eye", ier, (555, 300), (0.4, 0.3, 0.75)),
        ("nose", inn, (480, 395), (0.9, 0.6, 0.5)),
        ("mouth", im, (480, 490), (0.85, 0.2, 0.25)),
    ]
    return strokes, shapes

SUBJECTS = {"cat": cat, "house": house, "face": face}

# --- the finger ------------------------------------------------------------------------------

def resample(pts, step=4.0):
    out = [pts[0]]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        d = math.hypot(x1 - x0, y1 - y0)
        n = max(1, int(d / step))
        out += [(x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n) for k in range(1, n + 1)]
    return out

def finger(pts, kind, rng, miss):
    """The stroke a finger makes of `pts`: a slow wobble, and each end meant to land on a line
    missing it by `miss` points, short of it or past it."""
    pts = resample(pts)
    amp = rng.uniform(0.8, 2.0); period = rng.uniform(40, 90); phase = rng.uniform(0, 6.3)
    out = []
    s = 0.0
    for k, (x, y) in enumerate(pts):
        if k:
            s += math.hypot(x - pts[k - 1][0], y - pts[k - 1][1])
        a, b = (pts[max(k - 1, 0)], pts[min(k + 1, len(pts) - 1)])
        tx, ty = b[0] - a[0], b[1] - a[1]; L = math.hypot(tx, ty) or 1
        w = amp * math.sin(2 * math.pi * s / period + phase)
        out.append((x - ty / L * w, y + tx / L * w))
    def extend(path, at_end, d):
        # move the end `d` points along the stroke's direction there (d < 0: short of it)
        p = path[-1] if at_end else path[0]; q = path[-3] if at_end else path[2]
        ux, uy = p[0] - q[0], p[1] - q[1]; L = math.hypot(ux, uy) or 1
        if d < 0:
            # cut back along the path
            keep = path[:] if at_end else path[::-1]
            left = -d
            while len(keep) > 2 and left > 0:
                a, b = keep[-1], keep[-2]
                seg = math.hypot(a[0] - b[0], a[1] - b[1])
                if seg <= left:
                    keep.pop(); left -= seg
                else:
                    t = left / seg; keep[-1] = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t); left = 0
            return keep if at_end else keep[::-1]
        n = max(1, int(d / 3))
        extra = [(p[0] + ux / L * d * k / n, p[1] + uy / L * d * k / n) for k in range(1, n + 1)]
        return path + extra if at_end else extra[::-1] + path
    lo, hi = miss
    def m():
        d = rng.uniform(lo, hi)
        return d if rng.random() < 0.5 else -d
    if kind == "loop":
        out = extend(out, True, m())
    elif kind == "ends":
        out = extend(out, True, m()); out = extend(out, False, m())
    return out

def norm(p):
    return [round(p[0] / W, 5), round(p[1] / H, 5)]

# --- runs ------------------------------------------------------------------------------------

def run(subject, hand, seed):
    strokes, shapes = SUBJECTS[subject]()
    rng = random.Random(hash((subject, hand, seed)) & 0xffffffff)
    g = []
    for k, (pts, kind) in enumerate(strokes):
        pen = {"tool": "pen", "points": [norm(p) for p in finger(pts, kind, rng, HANDS[hand])], "inked": True,
               "caption": f"stroke {k + 1} ({kind})"}
        if opts.smoothing is not None:
            pen["smoothing"] = opts.smoothing
        g.append(pen)
    for name, _, at, rgb in shapes:
        g.append({"tool": "bucket", "at": norm(at), "rgb": list(rgb), "caption": f"pour {name}"})
    d = os.path.join(OUT, hand, f"{subject}-{seed}")
    os.makedirs(d, exist_ok=True)
    gj = os.path.join(d, "gestures.json")
    json.dump({"screen": {"width": W, "zoom": 1}, "gestures": g}, open(gj, "w"))
    r = subprocess.run([PBN, "refine", PHOTO, gj, "--out", d, "--blank"], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"pbn refine failed on {d}: {r.stderr[-800:]}")
    rep = json.load(open(os.path.join(d, "refine.json")))
    img = Image.open(os.path.join(d, "after.ppm")).convert("RGB")
    sx = img.width / W; sy = img.height / H
    px = img.load()
    # Score each shape: the pour's color is the pixel at its pour point (the drawn color in sRGB).
    results = []
    step = 3
    for name, inside, at, rgb in shapes:
        c = px[int(at[0] * sx), int(at[1] * sy)]
        def near(q):
            return sum(abs(a - b) for a, b in zip(q, c)) < 30
        tot = hit = out = 0
        for yy in range(0, int(H), step):
            for xx in range(0, int(W), step):
                q = px[min(int(xx * sx), img.width - 1), min(int(yy * sy), img.height - 1)]
                if inside(xx, yy):
                    tot += 1; hit += near(q)
                elif near(q):
                    out += 1
        cover = hit / max(tot, 1); leak = out / max(tot, 1)
        verdict = "closed" if cover >= 0.9 and leak < 0.05 else ("leaked" if leak >= 0.05 else "split")
        results.append((name, verdict, cover, leak))
    toasts = [s.get("toast") for s in rep["steps"] if s.get("toast")]
    return results, toasts, d, rep

def main():
    hands = opts.hands.split(","); subjects = opts.subjects.split(",")
    summary = {}
    for hand in hands:
        rows = []
        for subject in subjects:
            for seed in range(opts.seeds):
                res, toasts, d, rep = run(subject, hand, seed)
                bad = [f"{n} {v}" for n, v, _, _ in res if v != "closed"]
                rows.append((subject, seed, sum(v == "closed" for _, v, _, _ in res), len(res), bad, toasts, d))
        summary[hand] = rows
        closed = sum(r[2] for r in rows); total = sum(r[3] for r in rows)
        whole = sum(r[2] == r[3] for r in rows)
        print(f"\n{hand} hand (ends miss {HANDS[hand][0]}-{HANDS[hand][1]} pt): {closed}/{total} shapes closed, "
              f"{whole}/{len(rows)} pictures came out whole")
        for subject, seed, c, t, bad, toasts, d in rows:
            print(f"  {subject:5} seed {seed}: {c}/{t}" + (f"  — {', '.join(bad)}" if bad else "") +
                  (f"  [toasts: {'; '.join(sorted(set(toasts)))}]" if toasts else ""))
        # a strip of each subject's first two seeds
        tiles = [Image.open(os.path.join(r[6], "after.ppm")).convert("RGB").resize((360, 270)) for r in rows
                 if r[1] < 2]
        strip = Image.new("RGB", (360 * len(tiles), 270), "white")
        for k, t in enumerate(tiles):
            strip.paste(t, (360 * k, 0))
        strip.save(os.path.join(OUT, f"{hand}.png"))
    json.dump({h: [[r[0], r[1], r[2], r[3], r[4]] for r in rows] for h, rows in summary.items()},
              open(os.path.join(OUT, "summary.json"), "w"), indent=1)

main()
