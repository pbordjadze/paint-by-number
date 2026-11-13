#!/usr/bin/env python3
"""Whether a change left every generated template byte for byte as it was (painting-company row 292): what a
change to PaintCore that is not meant to alter pictures must show, on the machine it was made on.

    template_hashes.py <regression.json> --out <hashes.json>             the reference, before the change
    template_hashes.py <regression.json> --against <hashes.json> [--out <hashes.json>]     after it

Hashes the templates of two sets. The first is the quality gate's thirty cases, read from the JSON a
`tools/regression.py --json` run of the same build wrote (classic, coloring books from the committed maps,
Auto's choices: 768 x 512 photos). The second is made here with `.build/release/pbn generate` (build it first:
`swift build -c release --product pbn`): four of the app's own pictures at the canvas sizes the app makes, up
to 2,100 px, where the bands and chunks of the parallel stages fall differently. `--against` lists every case
whose template changed and exits 1 if any did. The hashes are this machine's: Linux's differ in the last bits of
some floats, so compare runs of one machine only. Each case's time is kept too (`ms`), for the curious: one run
each, not a benchmark.
"""
import hashlib, json, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PBN = ROOT / ".build/release/pbn"
SAMPLES = ROOT / "App/PaintByNumber/Resources/Samples"
# (picture, colors, detail, smoothness): the app's suggested settings run from about 16 to 40 colors.
LARGE = [("great-wave", 22, 0.57, 0.5), ("red-fox", 30, 0.8, 0.4), ("milkmaid", 16, 0.3, 0.6), ("blue-marble", 40, 1.0, 0.5)]


def option(name):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else None


def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("--"):
        sys.exit(__doc__)
    cases = {}
    regression = json.load(open(sys.argv[1]))
    for name, case in sorted(regression["cases"].items()):
        cases["gate/" + name] = {"sha1": case["metrics"]["templateSHA1"], "ms": round(case["metrics"]["totalMs"], 1)}
    if not PBN.exists():
        sys.exit(f"{PBN} is missing: swift build -c release --product pbn")
    with tempfile.TemporaryDirectory() as scratch:
        for picture, colors, detail, smooth in LARGE:
            out = pathlib.Path(scratch) / picture
            subprocess.run([str(PBN), "generate", str(SAMPLES / f"{picture}.jpg"), str(out), "--colors", str(colors),
                            "--detail", str(detail), "--smooth", str(smooth)], check=True, stdout=subprocess.DEVNULL)
            stats = json.load(open(out / "stats.json"))
            template = (out / "template.pbnt").read_bytes()
            cases[f"large/{picture}-c{colors}-d{detail}"] = {
                "sha1": hashlib.sha1(template).hexdigest(), "ms": round(stats["totalMs"], 1),
                "size": [stats["width"], stats["height"]], "regions": stats["regions"]}
    if option("--out"):
        json.dump(cases, open(option("--out"), "w"), indent=1, sort_keys=True)
    reference = option("--against")
    if not reference:
        print(f"{len(cases)} templates hashed")
        return
    before = json.load(open(reference))
    changed = [name for name in sorted(set(before) | set(cases)) if before.get(name, {}).get("sha1") != cases.get(name, {}).get("sha1")]
    for name in changed:
        print("changed: %s (%s -> %s)" % (name, before.get(name, {}).get("sha1", "absent")[:10], cases.get(name, {}).get("sha1", "absent")[:10]))
    total = lambda group: sum(c["ms"] for c in group.values())
    print("%d templates: %d byte-identical, %d changed; the time of one run of each: %.0f ms then, %.0f ms now" % (
        len(cases), len(cases) - len(changed), len(changed), total(before), total(cases)))
    sys.exit(1 if changed else 0)


if __name__ == "__main__":
    main()
