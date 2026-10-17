"""The pre-registered measures from two blind codings.

    analyze.py EXPDIR
Reads EXPDIR/key.json, EXPDIR/coding-1.json, coding-2.json ({"f001": {"cluster": "...", "checkable": true}, ...})
and the replies' favorites; prints per arm: findings, distinct checkable clusters, redundancy, unique clusters,
checkable share, distinct favorites; and the coders' adjusted Rand index.
"""
import json, os, sys, itertools
from collections import defaultdict, Counter
from math import comb
exp = sys.argv[1]
key = json.load(open(os.path.join(exp, "key.json")))
def ari(a, b):
    ids = sorted(set(a) & set(b)); n = len(ids)
    ct = Counter((a[i], b[i]) for i in ids); ra = Counter(a[i] for i in ids); rb = Counter(b[i] for i in ids)
    s = sum(comb(v, 2) for v in ct.values()); sa = sum(comb(v, 2) for v in ra.values()); sb = sum(comb(v, 2) for v in rb.values())
    e = sa * sb / comb(n, 2); m = (sa + sb) / 2
    return (s - e) / (m - e) if m != e else 1.0
codings = []
for k in (1, 2):
    p = os.path.join(exp, f"coding-{k}.json")
    if os.path.exists(p): codings.append(json.load(open(p)))
if len(codings) == 2:
    print("coders' adjusted Rand index:", round(ari({i: v["cluster"] for i, v in codings[0].items()}, {i: v["cluster"] for i, v in codings[1].items()}), 3))
for ci, coding in enumerate(codings, 1):
    print(f"\n== by coder {ci}")
    arm_items = defaultdict(list)
    for fid, rid in key.items():
        if fid in coding: arm_items[rid.split("-")[0]].append((fid, rid, coding[fid]["cluster"], bool(coding[fid]["checkable"])))
    clusters_by_arm = {arm: {c for _, _, c, ok in v if ok} for arm, v in arm_items.items()}
    for arm in "BMVE":
        v = arm_items.get(arm, [])
        if not v: continue
        chk = [x for x in v if x[3]]
        by_cluster = defaultdict(set)
        for fid, rid, c, ok in v: by_cluster[c].add(rid)
        shared = sum(1 for fid, rid, c, ok in v if len(by_cluster[c]) >= 2)
        others = set().union(*(clusters_by_arm[a] for a in clusters_by_arm if a != arm))
        unique = clusters_by_arm[arm] - others
        print(f"{arm}: findings {len(v)}, distinct checkable clusters {len(clusters_by_arm[arm])}, redundancy {shared / len(v):.2f}, "
              f"unique {len(unique)}, checkable share {len(chk) / len(v):.2f}")
favs = defaultdict(list)
for rid in sorted(os.listdir(os.path.join(exp, "reviewers"))):
    try:
        r = json.load(open(os.path.join(exp, "reviewers", rid, "reply.json"))); L = json.load(open(os.path.join(exp, "reviewers", rid, "letters.json")))
        f = r.get("favorite", "abstain"); favs[rid.split("-")[0]].append(L.get(f, f))
    except Exception: pass
print("\nfavorites by arm:", {a: Counter(v).most_common() for a, v in favs.items()})
