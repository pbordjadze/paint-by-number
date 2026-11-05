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
area outside it, both judged 3 points clear of the shape's outline, which a wobble moves); otherwise it `leaked` (paint ran out through a gap) or was `split`. Prints a
table per hand (shapes closed out of shapes drawn, over seeds) and writes, per subject, hand and
seed, the `pbn refine` folder (`refine.json`, `gestures.json`, and `after.png` at 1200 wide: its
full-size rasters, tens of MB each, are deleted) and a strip `<out>/<hand>.png` of every
subject's first seeds. Written for the from-scratch loop of November 3 (Refine, painting-company
row 175's sequel); run it after a change to PenAssist, Snap's reach or the editor's draw, and
compare. `--qa` replays instead the strokes with which the QA of November 3 failed to close a
roof (Shapes' Line), a sea under a horizon drawn to the picture's edges, a hull, a trunk over a
ground line drawn after it, and a mouth (Pen strokes tip to tip), and says whether each closes. Needs pbn built (`tools/swift.sh build -c release --static-swift-stdlib`) and Pillow.
"""
import argparse, json, math, os, random, subprocess, sys, zlib

from PIL import Image, ImageDraw

ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
ap.add_argument("--pbn", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".build", "release", "pbn"))
ap.add_argument("--out", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "refine-from-scratch"))
ap.add_argument("--seeds", type=int, default=6)
ap.add_argument("--hands", default="careful,casual,sloppy")
ap.add_argument("--subjects", default="cat,house,face")
ap.add_argument("--smoothing", type=float, default=None, help="the Pen's Smoothing, 0...1 (default off)")
ap.add_argument("--qa", action="store_true", help="replay the QA runs' failures of November 3 instead, and say whether each closes")
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
    roof = [(250, 380), (390, 240), (530, 380)]
    door = [(360, 620), (360, 500), (420, 500), (420, 620)]
    win = [(450, 430), (505, 430), (505, 480), (450, 480)]
    trunk = [(735, 620), (735, 470), (775, 470), (775, 620)]
    crown = (755, 400, 90, 85)
    ground = [(80, 620), (900, 620)]
    strokes = [
        (poly(*ground), "none"), (poly(wall[3], wall[0], wall[1], wall[2]), "ends"),
        (poly(*roof), "ends"), (poly(*door), "ends"), (poly(*win, win[0]), "loop"),
        (poly(*trunk), "ends"), (ellipse(*crown), "loop"),
    ]
    iw = inside_poly(*wall); idoor = inside_poly(*door); iwin = inside_poly(*win)
    icr = inside_ellipse(*crown); itr = inside_poly(*trunk)
    shapes = [
        ("wall", lambda x, y: iw(x, y) and not idoor(x, y) and not iwin(x, y), (300, 450), (0.95, 0.85, 0.6)),
        ("roof", lambda x, y: inside_poly(*roof)(x, y) and y < 380, (390, 330), (0.75, 0.2, 0.15)),
        ("door", idoor, (390, 560), (0.45, 0.25, 0.1)),
        ("window", iwin, (477, 455), (0.6, 0.8, 0.95)),
        ("trunk", lambda x, y: itr(x, y) and not icr(x, y), (755, 560), (0.6, 0.4, 0.25)),
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
    rng = random.Random(zlib.crc32(f"{subject}-{hand}-{seed}".encode()))  # the same strokes in every run
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
    r = subprocess.run([PBN, "refine", PHOTO, gj, "--out", d, "--blank", "--no-steps"], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"pbn refine failed on {d}: {r.stderr[-800:]}")
    rep = json.load(open(os.path.join(d, "refine.json")))
    img = Image.open(os.path.join(d, "after.ppm")).convert("RGB")
    img = img.resize((1200, int(1200 * img.height / img.width)), Image.NEAREST)
    img.save(os.path.join(d, "after.png"))
    for f in os.listdir(d):
        if f.endswith((".ppm", ".pbnt")):
            os.remove(os.path.join(d, f))
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
        def clear(x, y, want):  # x, y and the points 3 pt round it all inside (want True) or outside
            return all(inside(x + dx, y + dy) == want for dx, dy in ((0, 0), (3, 0), (-3, 0), (0, 3), (0, -3)))
        for yy in range(0, int(H), step):
            for xx in range(0, int(W), step):
                q = px[min(int(xx * sx), img.width - 1), min(int(yy * sy), img.height - 1)]
                if clear(xx, yy, True):
                    tot += 1; hit += near(q)
                elif clear(xx, yy, False) and near(q):
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
        tiles = [Image.open(os.path.join(r[6], "after.png")).convert("RGB").resize((360, 270)) for r in rows
                 if r[1] < 2]
        strip = Image.new("RGB", (360 * len(tiles), 270), "white")
        for k, t in enumerate(tiles):
            strip.paste(t, (360 * k, 0))
        strip.save(os.path.join(OUT, f"{hand}.png"))
    json.dump({h: [[r[0], r[1], r[2], r[3], r[4]] for r in rows] for h, rows in summary.items()},
              open(os.path.join(OUT, "summary.json"), "w"), indent=1)

# --- the QA runs' own strokes ------------------------------------------------------------------
# Shapes and Pen swipes from the exploratory QA of November 3 (qa-explore runs 41579909695, an
# iPhone, and 41584230981, an iPad), in screen points, with the picture's place on screen measured
# from their screenshots; each case says which pour must stay inside its shape.

def qa():
    with open(os.path.join(OUT, "paper-square.ppm"), "wb") as f:
        f.write(b"P6 1000 1000 255\n" + bytes([10, 10, 14]) * (1000 * 1000))
    with open(os.path.join(OUT, "paper-wide.ppm"), "wb") as f:  # a 3:2-ish photo, as Red Fuji
        f.write(b"P6 1470 1000 255\n" + bytes([135, 135, 120]) * (1470 * 1000))
    def case(name, x0, y0, width, steps, pour, outside, paper="paper-square.ppm"):
        paper = os.path.join(OUT, paper)
        aspect = 1000 / 1470 if paper.endswith("wide.ppm") else 1.0
        def n(x, y):
            return [round((x - x0) / width, 5), round((y - y0) / (width * aspect), 5)]
        g = []
        for s in steps:
            if s[0] == "pen":
                (ax, ay), (bx, by) = s[1], s[2]
                g.append({"tool": "pen", "inked": True, "points": [n(ax + (bx - ax) * k / 12, ay + (by - ay) * k / 12) for k in range(13)]})
            else:
                g.append({"tool": "shape", "shape": s[0], "from": n(*s[1]), "to": n(*s[2])})
        g.append({"tool": "bucket", "at": n(*pour), "rgb": [0.9, 0.15, 0.15]})
        d = os.path.join(OUT, "qa", name)
        os.makedirs(d, exist_ok=True)
        json.dump({"screen": {"width": width}, "gestures": g}, open(os.path.join(d, "gestures.json"), "w"))
        r = subprocess.run([PBN, "refine", paper, os.path.join(d, "gestures.json"), "--out", d, "--blank", "--no-steps"],
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit(f"pbn refine failed on {d}: {r.stderr[-800:]}")
        img = Image.open(os.path.join(d, "after.ppm")).convert("RGB")
        k = img.width / width
        poured = img.getpixel((int((pour[0] - x0) * k), int((pour[1] - y0) * k)))
        spilled = img.getpixel((int((outside[0] - x0) * k), int((outside[1] - y0) * k)))
        img.resize((600, int(600 * img.height / img.width))).save(os.path.join(d, "after.png"))
        os.remove(os.path.join(d, "after.ppm"))
        print(f"  {name}: {'closed' if poured != spilled else 'LEAKED (the pour ran outside the shape)'}")
    print("QA replays:")
    # The iPhone's roof: two slopes and a base drawn with Shapes' Line along the wall's top on to the eaves.
    case("roof-iphone", 12, 185, 378, [
        ("rectangle", (50, 340), (190, 480)), ("line", (40, 340), (120, 260)), ("line", (120, 260), (200, 340)),
        ("line", (40, 340), (200, 340)), ("line", (12, 480), (370, 480))], pour=(120, 305), outside=(300, 250))
    # The iPad's mouth: the upper lip a zigzag of four Pen strokes, the middle line, the lower lip three strokes.
    up = [(565, 860), (590, 843), (612, 852), (635, 843), (660, 860)]
    lo = [(565, 860), (592, 882), (635, 882), (660, 860)]
    # The iPhone's sailboat (run 41588232599): a Pen horizon from a point inside the left edge to the
    # right one, then the hull's sides (Shapes' Line) ending 5 points above the horizon.
    case("horizon-iphone", 12.2, 245.8, 376.5, [("pen", (13, 430), (389, 430))], pour=(300, 470), outside=(300, 300),
         paper="paper-wide.ppm")
    case("hull-iphone", 12.2, 245.8, 376.5, [
        ("pen", (13, 430), (389, 430)), ("line", (122, 405), (278, 405)), ("line", (122, 405), (150, 425)),
        ("line", (278, 405), (250, 425))], pour=(200, 415), outside=(300, 470), paper="paper-wide.ppm")
    # Its second hull, all Shapes' Lines: sides crossing the hull's top and the horizon both.
    case("hull-crossing-iphone", 12.2, 245.8, 376.5, [
        ("line", (3, 418), (399, 418)), ("line", (115, 397), (285, 397)), ("line", (117, 393), (155, 422)),
        ("line", (283, 393), (245, 422)), ("line", (200, 286), (200, 402))], pour=(200, 410), outside=(300, 300),
         paper="paper-wide.ppm")
    # Round 1's trunk (run 41618590832, iPhone): two Lines from the treetop's oval down to a
    # point above where the ground line, drawn after them, then passed.
    case("trunk-iphone", 12.2, 248, 376.5, [
        ("oval", (255, 325), (345, 420)), ("line", (291, 418), (291, 488)), ("line", (309, 418), (309, 488)),
        ("line", (13, 489), (389, 489))], pour=(300, 460), outside=(200, 300), paper="paper-wide.ppm")
    # Round 2's bridge (run 42045777195, iPhone): two rectangles, then two Lines from the top one's
    # bottom edge to the bottom one's top edge; the strip between them should be an area of its own.
    case("bridge-iphone", 12, 185, 378, [
        ("rectangle", (60, 240), (160, 290)), ("rectangle", (60, 420), (160, 470)),
        ("line", (90, 290), (90, 420)), ("line", (130, 290), (130, 420))], pour=(110, 355), outside=(300, 300))
    # And its stem as a rectangle overlapping the top shape's bottom and the bottom one's top.
    case("bridge-rectangle-iphone", 12, 185, 378, [
        ("rectangle", (60, 240), (160, 290)), ("rectangle", (60, 420), (160, 470)),
        ("rectangle", (90, 286), (130, 424))], pour=(110, 355), outside=(300, 300))
    # Its iPad horizon (run 42045770277): Shapes' Line from past the left edge to 15 points short
    # of the right one, where the swipe's last points went missing.
    case("horizon-ipad", 223.5, 279, 796, [("line", (211, 700), (1004, 700))], pour=(600, 500), outside=(600, 900))
    case("mouth-ipad", 208, 279, 811.5, [("oval", (424, 430), (804, 1010))] + [("pen", a, b) for a, b in zip(up, up[1:])] +
         [("pen", (565, 860), (660, 860))] + [("pen", a, b) for a, b in zip(lo, lo[1:])], pour=(600, 855), outside=(612, 760))

qa() if opts.qa else main()
