#!/usr/bin/env python3
"""Whether a change left coloring books of the size the app makes byte for byte as they were (painting-company
row 292). `tools/template_hashes.py`'s large pictures are not books, and the quality gate's books are 768 px: the
book's own stages (the lines, the cells, the layers) meet a picture of the app's size nowhere else outside the app.

    book_hashes.py --out <hashes.json>                              the reference, before the change
    book_hashes.py --against <hashes.json> [--out <hashes.json>]    after it
    … --pbn <path>                                                  another build's pbn (the reference's)
    … --bands <n>                                                   split the work as a device with n bands does

On a Mac (`sips` enlarges the photos). The six `Tests/Corpus` photos, enlarged to the 2,048 px the app decodes a
photo to, are each made a coloring book by `.build/release/pbn generate` (build it first: `swift build -c release
--product pbn`) from the committed maps of `tools/baseline/lines`, at the app's default settings and at two others.
The maps are those of the 768 px photos, so these are not the books the app would make of these photos; they are
books of its size from real maps, which is what the stages need. Then what a plain book never meets (`edges/…`):
the painter's own lines, rubs and fills (Refine's edits), eyes, a subject's silhouette, writing, all of them at
once, a book with no line at all, a drawing on paper (`pbn drawing`), and pictures a pixel or three wide, where
anything that walks a neighbourhood must mind the border. `--against` lists every case whose template changed and
exits 1 if any did (a case pbn refuses is compared by what it says). The hashes are this machine's (see
template_hashes.py). Each case's time and its slowest stages are kept too (one run each: not a benchmark).

A template must not depend on how many cores made it, and the package's own test of that uses pictures too small
to be split: run `--against` again with `--bands 1`, `--bands 16` (an iPad Air) and an odd `--bands 37` (pbn's
`PBN_BANDS`; `PBN_BANDS=16 tools/template_hashes.py …` does the same for that tool's 34).
"""
import hashlib, json, math, os, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PBN = ROOT / ".build/release/pbn"
CORPUS = ROOT / "Tests/Corpus"
LINES = ROOT / "tools/baseline/lines"
PHOTOS = ["barn", "espresso", "hibiscus", "lighthouse", "parrots", "regatta"]
# (colors, detail): the app's defaults for a book (the gate's BOOK_REGIME), a spare one and a busy one.
SETTINGS = [(24, 0.5), (14, 0.2), (36, 0.85)]
LONG_SIDE = 2048


def option(name):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else None


def ring(cx, cy, rx, ry, n=24):
    """A closed polygon, normalized to the photo."""
    return [[cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n)] for k in range(n)]


# Refine's edits, in the order a painter might make them: two lines drawn, a rub, a line taken away, a fill.
EDITS = [
    {"kind": "draw", "points": [[0.20, 0.30], [0.30, 0.35], [0.45, 0.33], [0.60, 0.40]]},
    {"kind": "draw", "points": [[0.70, 0.20], [0.72, 0.50], [0.70, 0.80]]},
    {"kind": "erase", "points": [[0.40, 0.60], [0.50, 0.62], [0.55, 0.70]], "radius": 0.02},
    {"kind": "eraseLine", "points": [[0.30, 0.50], [0.35, 0.50]]},
    {"kind": "fill", "points": [[0.50, 0.50]]},
]
EYES = [ring(0.40, 0.40, 0.03, 0.018, 12), ring(0.60, 0.40, 0.03, 0.018, 12), ring(0.40, 0.40, 0.009, 0.009, 8), ring(0.60, 0.40, 0.009, 0.009, 8)]
OBJECTS = [ring(0.50, 0.55, 0.25, 0.30)]
WRITING = [[[0.15, 0.10], [0.55, 0.11], [0.55, 0.16], [0.15, 0.15]], [[0.15, 0.18], [0.45, 0.19], [0.45, 0.24], [0.15, 0.23]]]


def netpbm(path, width, height, pixel):
    """A PPM (three numbers a pixel) or PGM (one) of `pixel(x, y)`."""
    first = pixel(0, 0)
    gray = isinstance(first, int)
    body = bytearray()
    for y in range(height):
        for x in range(width):
            v = pixel(x, y)
            body += bytes([v]) if gray else bytes(v)
    pathlib.Path(path).write_bytes(b"%s\n%d %d\n255\n" % (b"P5" if gray else b"P6", width, height) + bytes(body))


def bitmap(picture, scratch):
    """`picture` at 2,048 px as (width, height, pixel(x, y) -> (r, g, b)), by way of a BMP of sips's."""
    bmp = scratch / "picture.bmp"
    subprocess.run(["sips", "-s", "format", "bmp", "-Z", str(LONG_SIDE), str(picture), "--out", str(bmp)], check=True, capture_output=True)
    data = bmp.read_bytes()
    offset = int.from_bytes(data[10:14], "little"); width = int.from_bytes(data[18:22], "little", signed=True)
    height = int.from_bytes(data[22:26], "little", signed=True); bits = int.from_bytes(data[28:30], "little")
    step = bits // 8; row = (width * step + 3) // 4 * 4; rows = abs(height)
    def pixel(x, y):
        at = offset + (y if height < 0 else rows - 1 - y) * row + x * step
        return (data[at + 2], data[at + 1], data[at]) if step >= 3 else (data[at],) * 3
    return width, rows, pixel


def paper(drawing_png, path, scratch):
    """The committed line drawing as ink on paper, 2,048 px: what a photo of a drawing is to `pbn drawing`."""
    width, height, pixel = bitmap(drawing_png, scratch)
    netpbm(path, width, height, lambda x, y: (255 - pixel(x, y)[0],) * 3)


def note(photo, path, scratch):
    """The photo with a note on it where `WRITING`'s two lines are: pale paper, and a dark zigzag for a hand."""
    width, height, pixel = bitmap(photo, scratch)
    ink = set()
    for quad in WRITING:
        x0, x1 = int(quad[0][0] * width), int(quad[1][0] * width)
        y0, y1 = int(quad[0][1] * height), int(quad[3][1] * height)
        middle, reach = (y0 + y1) // 2, max(2, (y1 - y0) // 3)
        for x in range(x0 + 6, x1 - 6):
            wave = int(reach * abs(((x - x0) % 40) / 20 - 1) * 2 - reach)
            for thick in range(-2, 3):
                ink.add((x, middle + wave + thick))
    def written(x, y):
        if (x, y) in ink:
            return (30, 30, 34)
        if 0.13 * width <= x <= 0.57 * width and 0.08 * height <= y <= 0.26 * height:
            return (244, 241, 232)
        return pixel(x, y)
    netpbm(path, width, height, written)


def generate(pbn, command, source, out, arguments):
    """One template of pbn: its hash and what stats.json says, or what pbn said when it refused."""
    environment = dict(os.environ, PBN_BANDS=option("--bands")) if option("--bands") else None
    done = subprocess.run([str(pbn), command, str(source), str(out)] + [str(a) for a in arguments], capture_output=True, text=True,
                          env=environment)
    template = pathlib.Path(out) / "template.pbnt"
    if done.returncode != 0 or not template.exists():
        return {"sha1": "refused: " + ((done.stderr.strip() or f"exited {done.returncode}").splitlines()[-1])[:200]}
    stats = json.load(open(pathlib.Path(out) / "stats.json"))
    stages = sorted(stats.get("timingsMs", {}).items(), key=lambda kv: -kv[1])
    return {"sha1": hashlib.sha1(template.read_bytes()).hexdigest(), "ms": round(stats["totalMs"], 1),
            "size": [stats["width"], stats["height"]], "regions": stats["regions"],
            "stages": {name: round(ms, 1) for name, ms in stages[:12]}}


def edge_cases(pbn, scratch, large):
    """`edges/…`: see the docstring."""
    cases = {}
    for name, value in (("edits", EDITS), ("eyes", EYES), ("objects", OBJECTS), ("writing", WRITING)):
        json.dump(value, open(scratch / f"{name}.json", "w"))
    book = ["--colors", 24, "--detail", 0.5, "--line-style", "coloringBook"]
    def maps(photo):
        return ["--edges", LINES / f"{photo}-contours.png", "--lines", LINES / f"{photo}-drawing.png"]
    asks = {"edits": ["--line-edits", scratch / "edits.json"], "eyes": ["--eyes", scratch / "eyes.json"],
            "objects": ["--objects", scratch / "objects.json"], "writing": ["--writing", scratch / "writing.json"]}
    for kind, photo in (("edits", "barn"), ("edits", "parrots"), ("eyes", "parrots"), ("objects", "lighthouse")):
        cases[f"edges/{kind}-{photo}"] = generate(pbn, "generate", large[photo], scratch / f"{kind}-{photo}", book + maps(photo) + asks[kind])
    # Writing is traced from the photo, so the photo gets a note where the recognizer's lines are said to be.
    for photo in ("espresso", "hibiscus"):
        note(large[photo], scratch / f"note-{photo}.ppm", scratch)
    cases["edges/writing-espresso"] = generate(pbn, "generate", scratch / "note-espresso.ppm", scratch / "writing-espresso",
                                               book + maps("espresso") + asks["writing"])
    everything = [a for kind in ("edits", "eyes", "objects", "writing") for a in asks[kind]]
    cases["edges/all-hibiscus"] = generate(pbn, "generate", scratch / "note-hibiscus.ppm", scratch / "all", book + maps("hibiscus") + everything)
    # No line anywhere: both maps black.
    netpbm(scratch / "blank.pgm", 768, 512, lambda x, y: 0)
    cases["edges/no-lines-regatta"] = generate(pbn, "generate", large["regatta"], scratch / "no-lines",
                                               book + ["--edges", scratch / "blank.pgm", "--lines", scratch / "blank.pgm"])
    for photo in ("barn", "regatta"):
        paper(LINES / f"{photo}-drawing.png", scratch / f"paper-{photo}.ppm", scratch)
        cases[f"edges/drawing-{photo}"] = generate(pbn, "drawing", scratch / f"paper-{photo}.ppm", scratch / f"drawing-{photo}", ["--cleaned"])
    # A pixel or three wide, with maps as small: a gradient, and a line down or across the middle.
    for width, height in ((1, 1), (3, 40), (40, 3), (16, 16)):
        tag = f"{width}x{height}"
        netpbm(scratch / f"tiny-{tag}.ppm", width, height, lambda x, y: ((x * 37 + y * 11) % 256, (x * 5 + y * 23) % 256, 128))
        netpbm(scratch / f"tiny-{tag}.pgm", width, height, lambda x, y: 255 if x == width // 2 or y == height // 2 else 0)
        cases[f"edges/tiny-{tag}"] = generate(pbn, "generate", scratch / f"tiny-{tag}.ppm", scratch / f"tiny-{tag}",
                                              ["--colors", 4, "--detail", 0.5, "--line-style", "coloringBook",
                                               "--edges", scratch / f"tiny-{tag}.pgm", "--lines", scratch / f"tiny-{tag}.pgm"])
    return cases


def main():
    if not (option("--out") or option("--against")):
        sys.exit(__doc__)
    pbn = pathlib.Path(option("--pbn") or PBN)
    if not pbn.exists():
        sys.exit(f"{pbn} is missing: swift build -c release --product pbn")
    cases = {}
    with tempfile.TemporaryDirectory() as scratch:
        scratch = pathlib.Path(scratch)
        large = {}
        for photo in PHOTOS:
            large[photo] = scratch / f"{photo}.png"
            subprocess.run(["sips", "-s", "format", "png", "-Z", str(LONG_SIDE), str(CORPUS / f"{photo}.jpg"), "--out", str(large[photo])],
                           check=True, capture_output=True)
            for colors, detail in SETTINGS:
                made = generate(pbn, "generate", large[photo], scratch / f"{photo}-{colors}",
                                ["--colors", colors, "--detail", detail, "--line-style", "coloringBook",
                                 "--edges", LINES / f"{photo}-contours.png", "--lines", LINES / f"{photo}-drawing.png"])
                if made["sha1"].startswith("refused"):
                    sys.exit(f"{photo} at {colors} colors: {made['sha1']}")
                cases[f"book/{photo}-c{colors}-d{detail}"] = made
        cases.update(edge_cases(pbn, scratch, large))
    if option("--out"):
        json.dump(cases, open(option("--out"), "w"), indent=1, sort_keys=True)
    reference = option("--against")
    if not reference:
        print(f"{len(cases)} coloring books hashed ({sum(1 for c in cases.values() if c['sha1'].startswith('refused'))} refused by pbn)")
        return
    before = json.load(open(reference))
    changed = [name for name in sorted(set(before) | set(cases)) if before.get(name, {}).get("sha1") != cases.get(name, {}).get("sha1")]
    for name in changed:
        print("changed: %s (%s -> %s)" % (name, before.get(name, {}).get("sha1", "absent")[:10], cases.get(name, {}).get("sha1", "absent")[:10]))
    total = lambda group: sum(c.get("ms", 0) for c in group.values())
    print("%d coloring books: %d byte-identical, %d changed; the time of one run of each: %.0f ms then, %.0f ms now" % (
        len(cases), len(cases) - len(changed), len(changed), total(before), total(cases)))
    sys.exit(1 if changed else 0)


if __name__ == "__main__":
    main()
