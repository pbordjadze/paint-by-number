#!/usr/bin/env python3
"""Whether a change left coloring books of the size the app makes byte for byte as they were (painting-company
row 292). `tools/template_hashes.py`'s large pictures are not books, and the quality gate's books are 768 px: the
book's own stages (the lines, the cells, the layers) meet a picture of the app's size nowhere else outside the app.

    book_hashes.py --out <hashes.json>                              the reference, before the change
    book_hashes.py --against <hashes.json> [--out <hashes.json>]    after it

On a Mac (`sips` enlarges the photos). The six `Tests/Corpus` photos, enlarged to the 2,048 px the app decodes a
photo to, are each made a coloring book by `.build/release/pbn generate` (build it first: `swift build -c release
--product pbn`) from the committed maps of `tools/baseline/lines`, at the app's default settings and at two others.
The maps are those of the 768 px photos, so these are not the books the app would make of these photos; they are
books of its size from real maps, which is what the stages need. `--against` lists every case whose template
changed and exits 1 if any did. The hashes are this machine's (see template_hashes.py). Each case's time and its
slowest stages are kept too (one run each: not a benchmark).
"""
import hashlib, json, pathlib, subprocess, sys, tempfile

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


def main():
    if not (option("--out") or option("--against")):
        sys.exit(__doc__)
    if not PBN.exists():
        sys.exit(f"{PBN} is missing: swift build -c release --product pbn")
    cases = {}
    with tempfile.TemporaryDirectory() as scratch:
        scratch = pathlib.Path(scratch)
        for photo in PHOTOS:
            large = scratch / f"{photo}.png"
            subprocess.run(["sips", "-s", "format", "png", "-Z", str(LONG_SIDE), str(CORPUS / f"{photo}.jpg"), "--out", str(large)],
                           check=True, capture_output=True)
            for colors, detail in SETTINGS:
                out = scratch / f"{photo}-{colors}"
                subprocess.run([str(PBN), "generate", str(large), str(out), "--colors", str(colors), "--detail", str(detail),
                                "--line-style", "coloringBook", "--edges", str(LINES / f"{photo}-contours.png"),
                                "--lines", str(LINES / f"{photo}-drawing.png")], check=True, stdout=subprocess.DEVNULL)
                stats = json.load(open(out / "stats.json"))
                stages = sorted(stats.get("timingsMs", {}).items(), key=lambda kv: -kv[1])
                cases[f"book/{photo}-c{colors}-d{detail}"] = {
                    "sha1": hashlib.sha1((out / "template.pbnt").read_bytes()).hexdigest(), "ms": round(stats["totalMs"], 1),
                    "size": [stats["width"], stats["height"]], "regions": stats["regions"],
                    "stages": {name: round(ms, 1) for name, ms in stages[:12]}}
    if option("--out"):
        json.dump(cases, open(option("--out"), "w"), indent=1, sort_keys=True)
    reference = option("--against")
    if not reference:
        print(f"{len(cases)} coloring books hashed")
        return
    before = json.load(open(reference))
    changed = [name for name in sorted(set(before) | set(cases)) if before.get(name, {}).get("sha1") != cases.get(name, {}).get("sha1")]
    for name in changed:
        print("changed: %s (%s -> %s)" % (name, before.get(name, {}).get("sha1", "absent")[:10], cases.get(name, {}).get("sha1", "absent")[:10]))
    total = lambda group: sum(c["ms"] for c in group.values())
    print("%d coloring books: %d byte-identical, %d changed; the time of one run of each: %.0f ms then, %.0f ms now" % (
        len(cases), len(cases) - len(changed), len(changed), total(before), total(cases)))
    sys.exit(1 if changed else 0)


if __name__ == "__main__":
    main()
