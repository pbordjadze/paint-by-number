#!/usr/bin/env python3
"""Per-segment numbers from a device trace (Instruments' Animation Hitches template, which carries a Time
Profiler) and the app's -tourLog file (painting-company row 292, Step 0).

    analyze.py <trace|-> <tour-log.tsv> [marks.txt] [pid]

A trace of `-` gives the tour log's numbers alone (an untraced run). A trace attached to the app
(`xctrace record --attach`) or one with no hitches table (Time Profiler) works too; `pid` picks the app
out of an all-processes trace.

Segments come from marks.txt (`TOURMARK <name> begin|end <epoch s>` lines, the tour UI test's output); without
it, from the tour log's create events (launch, forming, settled). Prints one JSON object per segment.
Needs DEVELOPER_DIR for xctrace.
"""
import collections, datetime, json, os, re, subprocess, sys, tempfile
import xml.etree.ElementTree as ET

IDS = {}
APP_BINARIES = {"PaintByNumber", "PaintCore", "MosaicCore", "MosaicEngine", "MosaicKit", "MakingOf", "Ravenna"}


def export(trace, xpath=None):
    args = ["xcrun", "xctrace", "export", "--input", trace] + (["--xpath", xpath] if xpath else ["--toc"])
    out = tempfile.NamedTemporaryFile(delete=False, suffix=".xml")
    subprocess.run(args, stdout=out, stderr=subprocess.DEVNULL, check=True)
    out.close()
    return out.name


def table(trace, schema):
    if trace == "-":
        return
    path = export(trace, f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]')
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return
    finally:
        os.unlink(path)
    ids = IDS
    ids.clear()

    def resolve(e):
        if "ref" in e.attrib:
            return ids[e.attrib["ref"]]
        if "id" in e.attrib:
            ids[e.attrib["id"]] = e
        for c in e:
            resolve(c)
        return e

    cols = [m.text for m in root.iter("mnemonic")]
    for row in root.iter("row"):
        yield {col: resolve(cell) for col, cell in zip(cols, list(row))}


def ns(e):
    return int(e.text) if e is not None and e.text and e.text.strip().lstrip("-").isdigit() else 0


def main():
    trace, log = sys.argv[1], sys.argv[2]
    marks = sys.argv[3] if len(sys.argv) > 3 else None
    pid = sys.argv[4] if len(sys.argv) > 4 else None
    if trace == "-":
        start, device = 0.0, None
    else:
        toc = ET.parse(export(trace)).getroot()
        start = datetime.datetime.fromisoformat(toc.find(".//summary/start-date").text).timestamp()
        proc = toc.find(".//target/process[@type='launched']")
        if proc is None:
            proc = toc.find(".//target/process[@type='attached']")
        device = toc.find(".//target/device")
        pid = pid or (proc.get("pid") if proc is not None else None)
    lines = [l.rstrip("\n").split("\t") for l in open(log)]
    ev = [(float(l[0]) - start, l[1], l[2:]) for l in lines]  # trace-relative seconds

    # Lifecycle: the launch, from the first lifecycle period to the end of Initial Frame Rendering.
    life = []
    for r in table(trace, "life-cycle-period"):
        p = r["process"].find("pid") if r.get("process") is not None else None
        if pid and (p is None or p.text != pid):
            continue
        life.append((ns(r["start"]) / 1e9, ns(r["duration"]) / 1e9, r["period"].get("fmt")))
    launch = None
    if life:
        first = min(s for s, _, _ in life)
        frame = [s + d for s, d, p in life if "Initial Frame Rendering" in p]
        if frame:
            launch = (first, frame[0])

    # Segments.
    segs = []
    if marks:
        m = {}
        for l in open(marks):
            if not l.startswith("TOURMARK"):
                continue
            _, name, edge, t = l.split()
            m.setdefault(name, {})[edge] = float(t) - start
        segs = [(n, v["begin"], v["end"]) for n, v in m.items() if "begin" in v and "end" in v]
        segs.sort(key=lambda s: s[1])
    else:
        creates = [(t, f[0]) for t, k, f in ev if k == "create"]
        drafted = next((t for t, f in creates if "started" in f), None)
        shown = [t for t, f in creates if f.startswith("Full") and f.endswith("shown")]
        if launch:
            segs.append(("launch", launch[0], launch[1]))
        if drafted and shown:
            segs.append(("forming", drafted, shown[0]))
            segs.append(("settled", shown[0], shown[0] + 15))

    hitches = []
    for r in table(trace, "hitches"):
        p = r["process"].find("pid") if r.get("process") is not None else None
        if pid and (p is None or p.text != pid):
            continue
        hitches.append((ns(r["start"]) / 1e9, ns(r["duration"]) / 1e6))
    thermal = [(ns(r["start"]) / 1e9, ns(r["duration"]) / 1e9, r["thermal-state"].get("fmt"))
               for r in table(trace, "device-thermal-state-intervals")]

    samples = []
    for r in table(trace, "time-profile"):
        p = r["process"].find("pid")
        if pid and (p is None or p.text != pid):
            continue
        thread = r["thread"].get("fmt", "")
        frames = []
        bt = r.get("stack")
        if bt is not None:
            for f in bt.iter("frame"):
                if "ref" in f.attrib:
                    f = IDS[f.attrib["ref"]]
                b = f.find("binary")
                if b is not None and "ref" in b.attrib:
                    b = IDS[b.attrib["ref"]]
                frames.append((f.get("name") or "?", (b.get("name") if b is not None else None) or "?"))
        samples.append((ns(r["time"]) / 1e9, "Main Thread" in thread, frames))

    # Who owns a main-thread sample: the leaf-most frame in a library we can name (the app's own code
    # counts as the app). A rough split; Instruments' own call tree is the authority.
    SIDES = [("app", APP_BINARIES), ("SwiftUI", {"SwiftUI", "SwiftUICore", "AttributeGraph"}),
             ("UIKit/CoreAnimation", {"UIKitCore", "QuartzCore", "UIKit"}),
             ("Metal", {"Metal", "MetalTools", "IOGPU", "AGXMetalG13X", "AGXMetal13_3"}),
             ("CoreGraphics/vImage", {"CoreGraphics", "vImage", "ImageIO", "libvDSP.dylib"}),
             ("accessibility", {"UIAccessibility", "AXCoreUtilities", "AccessibilityUtilities", "AXRuntime"})]

    def owner(frames):
        for _, b in frames:
            for side, names in SIDES:
                if b in names or (side == "Metal" and b.startswith("AGX")):
                    return side
        return "other system"

    out = []
    for name, t0, t1 in segs:
        dur = max(t1 - t0, 1e-6)
        h = [d for t, d in hitches if t0 <= t < t1]
        s = [x for x in samples if t0 <= x[0] < t1]
        main = [x for x in s if x[1]]
        own = collections.Counter(owner(f) for _, _, f in main)
        top_app = collections.Counter()
        for _, _, f in s:
            a = next((n for n, b in f if b in APP_BINARIES), None)
            if a:
                top_app[a[:90]] += 1
        top_leaf = collections.Counter((f[0][0][:70] + " [" + f[0][1] + "]") for _, _, f in main if f)
        ticks = [float(f[0].split("=")[1]) for t, k, f in ev if k == "tick" and t0 <= t < t1 and f[2] == "drew=1"]
        works = [float(f[1].split("=")[1]) for t, k, f in ev if k == "tick" and t0 <= t < t1]
        mem = [int(f[2].split("=")[1]) for t, k, f in ev if k == "device" and t0 <= t < t1]
        th = sorted({st for a, d, st in thermal if a < t1 and a + d > t0})
        out.append({
            "segment": name, "seconds": round(dur, 2),
            "hitches": len(h), "hitch_ms": round(sum(h), 1), "hitch_ms_per_s": round(sum(h) / dur, 1),
            "worst_hitch_ms": round(max(h), 1) if h else 0,
            "tick_frames": len(ticks),
            # Gaps between drawn ticks: over 8.3 ms misses a 120 Hz frame; over 25 ms misses a 60 Hz one.
            "tick_gap_over_8.3": sum(g > 8.4 for g in ticks),
            "tick_gap_over_25": sum(g > 25 for g in ticks),
            "tick_worst_gap_ms": round(max(ticks), 1) if ticks else None,
            # Gaps over 200 ms are the display link resuming after an idle pause, not drops; between 25
            # and 200 ms, each 16.7 ms past the first is a missed 60 Hz frame.
            "missed_60hz_frames": sum(round(g / 16.667) - 1 for g in ticks if 25 < g <= 200),
            "drop_gaps_25_200": sum(25 < g <= 200 for g in ticks),
            "worst_drop_gap_ms": round(max([g for g in ticks if g <= 200] or [0]), 1),
            "tick_work_median_ms": round(sorted(works)[len(works) // 2], 2) if works else None,
            "tick_work_over_8.3": sum(w > 8.3 for w in works),
            "tick_work_over_16.7": sum(w > 16.7 for w in works),
            "tick_work_p99_ms": round(sorted(works)[int(len(works) * 0.99) - 1], 2) if len(works) > 10 else None,
            "tick_work_max_ms": round(max(works), 2) if works else None,
            "flights": sum(1 for t, k, f in ev if k == "flight" and t0 <= t < t1),
            "sounds": sum(1 for t, k, f in ev if k == "sound" and t0 <= t < t1),
            "haptics": sum(1 for t, k, f in ev if k == "haptic" and t0 <= t < t1),
            "footprint_mb_max": max(mem) if mem else None, "thermal": th,
            "main_samples_ms": len(main), "all_samples_ms": len(s),
            "main_owner": dict(own.most_common()),
            "top_app_frames": top_app.most_common(8), "top_main_leaves": top_leaf.most_common(6),
        })
    print(json.dumps({"device": f'{device.get("model")} {device.get("platform")} {device.get("os-version")}' if device is not None else None,
                      "pid": pid, "launch_ms": round((launch[1] - launch[0]) * 1000) if launch else None,
                      "segments": out}, indent=1))


if __name__ == "__main__":
    main()
