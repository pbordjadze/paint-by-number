#!/usr/bin/env python3
"""compare.py <side-by-side outdir>: the frozen build's runs beside the new build's, a line a scenario and number.

For each scenario's own segment (and `maps`, `forming` and `launch` where a scenario has them), each number as the
frozen build's runs then the new build's, and what the rule makes of it, lower being better for all of them:
GAIN when every new run is below the frozen build's lowest, WORSE when every new run is above its highest,
otherwise nothing (noise). `what` (the digest of flights, sounds and haptics) is `same` when every run of both
builds agrees. Every run found is shown; none is left out.
"""
import collections, glob, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import summary

OWN = {"launch": ["launch"], "forming": ["maps", "forming"], "forming-cold": ["maps", "forming"], "start": ["start"],
       "start-making-of": ["start"], "zen-30": ["zen-30"], "finish": ["finish"]}
NUMBERS = [("seconds", "s"), ("hitches", ""), ("hitch_ms", "ms late"), ("missed_60hz_frames", "missed"),
           ("tick_work_median_ms", "work ms"), ("footprint_mb_max", "MB"), ("peak_mb_since_launch", "peak MB")]

def main():
    out = sys.argv[1]
    runs = collections.defaultdict(lambda: collections.defaultdict(list))   # (scenario, segment) -> build -> [segment dict]
    builds = {}
    for build in ("frozen", "new"):
        for path in sorted(glob.glob(os.path.join(out, build, "*", "*.tsv"))):
            scenario = os.path.basename(path).rsplit("-", 1)[0]
            s = summary.summarize(path)
            builds.setdefault(build, set()).add(s["build"].get("uuid", "?"))
            for seg in s["segments"]:
                if seg["segment"] in OWN.get(scenario, []):
                    runs[(scenario, seg["segment"])][build].append(seg)
    for build, uuids in builds.items():
        print("%s: binary %s" % (build, ", ".join(sorted(uuids))))
    order = list(OWN)
    for (scenario, segment) in sorted(runs, key=lambda k: (order.index(k[0]), k[1])):
        frozen, new = runs[(scenario, segment)]["frozen"], runs[(scenario, segment)]["new"]
        whats = {s["what"] for s in frozen + new}
        print("\n%s / %s  (%d frozen, %d new runs; what: %s)" % (scenario, segment, len(frozen), len(new),
              "same" if len(whats) == 1 else "DIFFERS " + " ".join(sorted(whats))))
        for key, unit in NUMBERS:
            a = [s[key] for s in frozen if s.get(key) is not None]
            b = [s[key] for s in new if s.get(key) is not None]
            if not a and not b:
                continue
            verdict = ""
            if a and b and len(a) == len(frozen) and len(b) == len(new):
                if max(b) < min(a): verdict = "GAIN"
                elif min(b) > max(a): verdict = "WORSE"
            fmt = lambda v: " ".join(("%.1f" % x).rstrip("0").rstrip(".") for x in v)
            print("  %-22s frozen %-26s new %-26s %s" % (key + (" (" + unit + ")" if unit else ""), fmt(a), fmt(b), verdict))

if __name__ == "__main__":
    main()
