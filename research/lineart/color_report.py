"""Markdown tables from stage 2's summary.json (written by run_color.py --batch / --summarize).

    color_report.py <color-root>/summary.json [--options '*-medium'] [--by-family]
"""

import argparse
import fnmatch
import json
import statistics as st
from collections import defaultdict


def family(option: str) -> str:
    return option.rsplit("-", 1)[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("summary")
    ap.add_argument("--options", default=None, help="comma-separated option globs")
    ap.add_argument("--by-family", action="store_true", help="also aggregate per family and detail")
    ap.add_argument("--pics", default=None, help="comma-separated pictures")
    a = ap.parse_args()
    rows = json.load(open(a.summary))
    for r in rows:
        r["opt"] = r["option"].split("/")[-1]
        # ΔE where the paint shows (the photo's own dark lines are ink here, paint in pbn's raster)
        r["de"] = r.get("meanDeltaEOutsideInk", r["meanDeltaE"])
        r["pbnde"] = r.get("pbnMeanDeltaEOutsideInk", r["pbnMeanDeltaE"])
    if a.pics:
        rows = [r for r in rows if r["picture"] in a.pics.split(",")]
    if a.options:
        pats = a.options.split(",")
        rows = [r for r in rows if any(fnmatch.fnmatch(r["opt"], p) for p in pats)]
    pairs = defaultdict(dict)
    for r in rows:
        pairs[(r["picture"], r["opt"])][r["method"]] = r

    print("| picture | option | regions C1 / C2 (pbn) | areas | regions per area C1 / C2 | slivers C1 / C2 "
          "| cells too small (joined / absorbed / kept) | min room C1 / C2 | ΔE flat outside ink C1 / C2 (pbn) "
          "| ΔE finished C1 / C2 |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for (pic, opt), m in sorted(pairs.items()):
        c1, c2 = m.get("c1"), m.get("c2")
        if not (c1 and c2):
            continue
        print(f"| {pic} | {opt} | {c1['regions']} / {c2['regions']} ({c1['pbnRegions']}) | {c1['enclosedAreas']} "
              f"| {c1['regionsPerArea']['mean']:.1f} / {c2['regionsPerArea']['mean']:.1f} "
              f"| {c1['slivers']} / {c2['slivers']} "
              f"| {c1['cellsTooSmall']} ({c1['cellsJoinedAcrossLine']} / {c1['cellsAbsorbed']} / "
              f"{c1['regionsBelowMinimumRadius']}) "
              f"| {c1['minRoom']:.2f} / {c2['minRoom']:.2f} "
              f"| {c1['de']:.4f} / {c2['de']:.4f} ({c1['pbnde']:.4f}) "
              f"| {c1.get('finishedMeanDeltaE', 0):.4f} / {c2.get('finishedMeanDeltaE', 0):.4f} |")

    def agg(group_rows, title):
        print(f"\n| {title} | method | options | regions / pbn (median) | slivers (mean) | cells too small (mean) "
              "| kept below min (mean) | ΔE flat / pbn, outside ink (median) | ΔE finished (median) "
              "| unlined share (median) |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for key in sorted(group_rows):
            for meth in ("c1", "c2"):
                rs = [r for r in group_rows[key] if r["method"] == meth]
                if not rs:
                    continue
                print(f"| {key} | {meth.upper()} | {len(rs)} "
                      f"| {st.median(r['regions'] / max(r['pbnRegions'], 1) for r in rs):.2f} "
                      f"| {st.mean(r['slivers'] for r in rs):.1f} | {st.mean(r['cellsTooSmall'] for r in rs):.1f} "
                      f"| {st.mean(r['regionsBelowMinimumRadius'] for r in rs):.1f} "
                      f"| {st.median(r['de'] / r['pbnde'] for r in rs):.2f} "
                      f"| {st.median(r.get('finishedMeanDeltaE', 0) for r in rs):.4f} "
                      f"| {st.median(r['unlinedBoundaryShare'] for r in rs):.2f} |")

    agg({"all": rows}, "set")
    if a.by_family:
        fam = defaultdict(list)
        det = defaultdict(list)
        for r in rows:
            fam[family(r["opt"])].append(r)
            det[r["opt"].rsplit("-", 1)[-1]].append(r)
        agg(fam, "family")
        agg(det, "detail")


if __name__ == "__main__":
    main()
