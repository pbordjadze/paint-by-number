"""Verdicts, favorites and vetoes per candidate, letters undone, overall and by arm.

    tally.py EXPDIR
"""
import json, os, sys
from collections import Counter, defaultdict
exp = sys.argv[1]; rows = []
for rid in sorted(os.listdir(os.path.join(exp, "reviewers"))):
    d = os.path.join(exp, "reviewers", rid)
    try: r = json.load(open(os.path.join(d, "reply.json"))); L = json.load(open(os.path.join(d, "letters.json")))
    except Exception: continue
    rows.append((rid, r, L))
keys = sorted({k for _, _, L in rows for k in L.values()})
verd = defaultdict(Counter); fav = defaultdict(Counter); vetoes = []
for rid, r, L in rows:
    arm = rid.split("-")[0]
    for letter, v in r.get("verdicts", {}).items():
        if letter in L: verd[(L[letter], "all")][v] += 1; verd[(L[letter], arm)][v] += 1
    f = r.get("favorite", "abstain"); f = L.get(f, f); fav["all"][f] += 1; fav[arm][f] += 1
    for v in r.get("veto", []) or []:
        vetoes.append((rid, L.get(v.get("candidate"), v.get("candidate")), v.get("reason", "")))
print(f"{len(rows)} replies\n")
print(f"{'candidate':12s} {'keep':>5s} {'fix':>5s} {'kill':>5s} {'abst':>5s} {'fav':>5s}   favorites by arm B/M/V/E")
for k in keys:
    c = verd[(k, "all")]
    print(f"{k:12s} {c['keep']:5d} {c['fix']:5d} {c['kill']:5d} {c['abstain']:5d} {fav['all'][k]:5d}   " + " ".join(str(fav[a][k]) for a in "BMVE"))
print("\nvetoes:")
for rid, k, why in vetoes: print(f"  {rid} -> {k}: {why}")
