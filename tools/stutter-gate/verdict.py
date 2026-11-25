#!/usr/bin/env python3
"""The stutter check's verdict on one tools/perf-tour/run.sh outdir (painting-company row 392).

    verdict.py <outdir> <limits.json> [--title <text>]

Reads every <scenario>-<run>.tsv run.sh left, measures each segment limits.json names for that
scenario (summary.py's segments; `run`, the whole log from a second after the first refresh the app
answers to its end, for a demo that marks no segment of its own), and holds each number to its
limit. A limit is over only when every run of the scenario reached the segment and is over it: one run spoiled by the Mac's
load or a notification is noise, a stutter in every run is the app's. A segment no run reached
(the app never got there, or was gone) fails too. A scenario with no log at all is the check's own
trouble (the iPad locked, the app not installed), not the app's: the verdict is then `error`.

Writes <outdir>/report.md and <outdir>/verdict.json ({"state": success|failure|error, "headline":
one line for the commit status}), and exits 0 (success), 1 (failure) or 2 (error).
"""
import glob, json, os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "perf-tour"))
import summary

# What each number is, for the report: (label, unit).
METRICS = {
    "seconds": ("length", "s"),
    "hitch_ms_per_s": ("main thread late", "ms/s"),
    "worst_gap_ms": ("longest freeze", "ms"),
    "missed_60hz_frames": ("canvas frames missed", ""),
}


def events(path):
    out = []
    for line in open(path):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            try:
                out.append((float(parts[0]), parts[1], parts[2:]))
            except ValueError:
                pass
    return out


def whole_run(path):
    """The `run` segment: a second after the first refresh to the log's last line."""
    evs = events(path)
    first = next((t for t, k, f in evs if k == "mark" and f and f[0] == "first refresh"), None)
    if first is None or not evs:
        return None
    t0, t1 = first + 1.0, evs[-1][0]
    if t1 <= t0:
        return None
    hitches = [summary.fields(f) for t, k, f in evs if k == "hitch" and t0 <= t < t1]
    late = sum(max(float(h["gap"]) - float(h["frame"]), 0) for h in hitches)
    device = [summary.fields(f) for t, k, f in evs if k == "device" and t0 <= t < t1]
    return {"segment": "run", "seconds": round(t1 - t0, 3), "hitches": len(hitches),
            "hitch_ms_per_s": round(late / (t1 - t0), 1),
            "worst_gap_ms": round(max((float(h["gap"]) for h in hitches), default=0), 1),
            "thermal_max": max((int(d["thermal"]) for d in device if "thermal" in d), default=None),
            "low_power": any(d.get("lowPower") == "true" for d in device)}


def segments(path):
    found = {}
    for s in summary.summarize(path)["segments"]:
        found.setdefault(s["segment"], s)   # a segment's first time in the log
    run = whole_run(path)
    if run:
        found["run"] = run
    return found


def fmt(value):
    if value is None:
        return "–"
    return ("%.0f" if abs(value) >= 100 else "%.1f" if abs(value) >= 1 else "%.2f") % value


def main():
    args = [a for a in sys.argv[1:]]
    title = None
    if "--title" in args:
        i = args.index("--title"); title = args[i + 1]; del args[i:i + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    out, limits_path = args
    limits = json.load(open(limits_path))
    limits.pop("_about", None)

    rows, failures, errors, notes = [], [], [], []
    for scenario, segs in limits.items():
        logs = sorted(glob.glob(os.path.join(out, scenario + "-[0-9]*.tsv")),
                      key=lambda p: int(re.search(r"-(\d+)\.tsv$", p).group(1)))
        if not logs:
            errors.append("%s: no log from any run" % scenario)
            continue
        measured = [segments(p) for p in logs]
        for m in measured:
            for s in m.values():
                if s.get("low_power"):
                    notes.append("%s: Low Power Mode was on" % scenario)
                if (s.get("thermal_max") or 0) >= 2:
                    notes.append("%s: the iPad was hot (thermal state %s)" % (scenario, s["thermal_max"]))
        for seg, metrics in segs.items():
            if seg.startswith("_"):
                continue
            reached = [m[seg] for m in measured if seg in m]
            if not reached:
                failures.append("%s never reached `%s` in %d runs (crashed, or stuck before it)" % (scenario, seg, len(logs)))
                rows.append((scenario, seg, "reached", "yes", ["no"] * len(logs), "FAIL"))
                continue
            if len(reached) < len(logs):
                notes.append("%s: `%s` missing from %d of %d runs" % (scenario, seg, len(logs) - len(reached), len(logs)))
            for metric, limit in metrics.items():
                values = [s.get(metric) for s in reached]
                values = [v for v in values if v is not None]
                if not values:
                    continue
                # A run that never reached the segment is named above, not counted as over.
                over = len(values) == len(logs) and min(values) > limit
                label, unit = METRICS.get(metric, (metric, ""))
                rows.append((scenario, seg, label, "%s %s" % (fmt(limit), unit), [fmt(v) for v in values],
                             "OVER" if over else "ok"))
                if over:
                    failures.append("%s %s: %s %s %s in every run (limit %s)" % (
                        scenario, seg, label, "/".join(fmt(v) for v in values), unit, fmt(limit)))

    if errors:
        state = "error"
        headline = "Stutter check couldn't run: " + errors[0]
    elif failures:
        state = "failure"
        headline = "Stutter on the iPad: " + failures[0] + (" (+%d more)" % (len(failures) - 1) if len(failures) > 1 else "")
    else:
        state = "success"
        headline = "No stutter over the limits on the iPad (%d scenarios)" % len(limits)

    lines = ["# %s" % (title or "Stutter check"), "", "**%s**: %s" % (state.upper(), headline), ""]
    if failures:
        lines += ["## Over the limit", ""] + ["- " + f for f in failures] + [""]
    if errors:
        lines += ["## The check's own trouble", ""] + ["- " + e for e in errors] + [""]
    if notes:
        lines += ["## Worth knowing", ""] + ["- " + n for n in sorted(set(notes))] + [""]
    lines += ["## Every number", "",
              "Each run's value; a number is over only when every run is over its limit.", "",
              "| scenario | segment | number | limit | runs | |", "|---|---|---|---|---|---|"]
    for scenario, seg, label, limit, values, verdict in rows:
        lines.append("| %s | %s | %s | %s | %s | %s |" % (scenario, seg, label, limit, " · ".join(values), verdict))
    lines.append("")
    open(os.path.join(out, "report.md"), "w").write("\n".join(lines))
    json.dump({"state": state, "headline": headline, "failures": failures, "errors": errors, "notes": sorted(set(notes))},
              open(os.path.join(out, "verdict.json"), "w"), indent=1)
    print("\n".join(lines))
    sys.exit({"success": 0, "failure": 1, "error": 2}[state])


if __name__ == "__main__":
    main()
