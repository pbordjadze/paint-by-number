#!/usr/bin/env python3
"""Where the time went in each segment of a traced run: a device or simulator trace (Instruments' Animation
Hitches or Time Profiler template) cut by the marks of the run's own -tourLog (painting-company row 292).

    stacks.py <trace> <tour-log.tsv> [--pid N] [--segment NAME] [--top N]

Segments are summary.py's (launch, maps, forming, start, a demo's own marks). For each: Instruments' hitches
where the trace has them (count, total and worst, ms), how busy the main thread was (ms of 1 kHz samples, and
per tenth of a second), and the heaviest frames: the main thread's leaves, its innermost and outermost frames
in the app's own code, and the workers' innermost app frames. A rough reading for finding what to look at;
Instruments' own call tree is the authority. Needs DEVELOPER_DIR for xctrace when several Xcodes are installed.
"""
import collections, datetime, os, subprocess, sys, tempfile
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import summary

APP = {"PaintByNumber", "PaintCore", "MosaicCore", "MosaicEngine", "MosaicKit", "MakingOf", "Ravenna"}


def export(trace, xpath=None):
    out = tempfile.NamedTemporaryFile(delete=False, suffix=".xml")
    subprocess.run(["xcrun", "xctrace", "export", "--input", trace] + (["--xpath", xpath] if xpath else ["--toc"]),
                   stdout=out, stderr=subprocess.DEVNULL, check=True)
    out.close()
    return out.name


def rows(trace, schema):
    path = export(trace, f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]')
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return
    finally:
        os.unlink(path)
    ids = {}

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
        yield {c: resolve(cell) for c, cell in zip(cols, list(row))}, ids


def number(e):
    return int(e.text) if e is not None and e.text and e.text.strip().lstrip("-").isdigit() else 0


def option(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    trace, log = sys.argv[1], sys.argv[2]
    pid, only, top = option("--pid"), option("--segment"), int(option("--top", "14"))
    if pid is None:
        # The log is tour-log-<pid>.tsv as the app wrote it; run.sh's copies keep no pid.
        stem = os.path.basename(log)
        pid = stem[len("tour-log-"):-len(".tsv")] if stem.startswith("tour-log-") else None
    toc_path = export(trace)
    toc = ET.parse(toc_path).getroot()
    os.unlink(toc_path)
    start = datetime.datetime.fromisoformat(toc.find(".//summary/start-date").text).timestamp()
    segments = [(s["segment"], s["begin"] - start, s["begin"] - start + s["seconds"]) for s in summary.summarize(log)["segments"]]

    def mine(r):
        p = r["process"].find("pid") if r.get("process") is not None else None
        return pid is None or (p is not None and p.text == pid)

    # A Time Profiler recording (all a simulator makes) has no hitches table: its table of contents says so, and
    # its stacks are as good. Any other export that fails still stops the script.
    recorded = {t.get("schema") for t in toc.iter("table")}
    hitches = [(number(r["start"]) / 1e9, number(r["duration"]) / 1e6)
               for r, _ in (rows(trace, "hitches") if "hitches" in recorded else []) if mine(r)]
    samples = []
    for r, ids in rows(trace, "time-profile"):
        if not mine(r):
            continue
        frames = []
        stack = r.get("stack")
        if stack is not None:
            for f in stack.iter("frame"):
                if "ref" in f.attrib:
                    f = ids[f.attrib["ref"]]
                b = f.find("binary")
                if b is not None and "ref" in b.attrib:
                    b = ids[b.attrib["ref"]]
                frames.append((f.get("name") or "?", (b.get("name") if b is not None else None) or "?"))
        samples.append((number(r["time"]) / 1e9, "Main Thread" in r["thread"].get("fmt", ""), frames))
    print("trace %s, pid %s: %d samples, %d hitches" % (os.path.basename(trace.rstrip("/")), pid, len(samples), len(hitches)))
    for name, t0, t1 in segments:
        if only and name != only:
            continue
        inside = [s for s in samples if t0 <= s[0] < t1]
        if not inside and not [h for h in hitches if t0 <= h[0] < t1]:
            continue
        main_samples = [s for s in inside if s[1]]
        h = [d for t, d in hitches if t0 <= t < t1]
        print("\n== %s: %.2f s; Instruments' hitches %d (%.0f ms, worst %.0f); main thread %d ms busy, all threads %d ms" % (
            name, t1 - t0, len(h), sum(h), max(h, default=0), len(main_samples), len(inside)))
        tenths = collections.Counter(int((s[0] - t0) * 10) for s in main_samples)
        print("main thread, ms busy in each tenth of a second:", " ".join(str(tenths[i]) for i in range(int((t1 - t0) * 10) + 1)))
        leaf, inner, outer, workers = (collections.Counter() for _ in range(4))
        for _, is_main, frames in inside:
            app = [n for n, b in frames if b in APP]
            if is_main:
                if frames:
                    leaf["%s [%s]" % (frames[0][0][:80], frames[0][1])] += 1
                inner[(app[0] if app else "(no app frame)")[:110]] += 1
                outer[" > ".join(x[:56] for x in [n for n, b in reversed(frames) if b in APP][:3]) or "(none)"] += 1
            elif app:
                workers[app[0][:110]] += 1
        for title, counter in (("main thread: leaves", leaf), ("main thread: innermost app frame", inner),
                               ("main thread: outermost app frames", outer), ("workers: innermost app frame", workers)):
            print("-- " + title)
            for frame, n in counter.most_common(top):
                print("%6d  %s" % (n, frame))


if __name__ == "__main__":
    main()
