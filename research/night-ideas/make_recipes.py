"""Recipes for each corpus painting's paints, and the one extra tube that would help it most.

    python3 make_recipes.py <gen/book dir> <out.json>
"""
import json
import os
import sys

import numpy as np

import km

EXTRA = [
    ("Yellow Ochre", "#C89B3C", 0.5),
    ("Burnt Sienna", "#8A3B1E", 0.3),
    ("Alizarin Crimson", "#6B1A26", 0.15),
    ("Dioxazine Purple", "#2E1A47", 0.15),
    ("Sap Green", "#3F5A26", 0.25),
    ("Payne's Gray", "#2B3440", 0.3),
]


def hexs(c):
    return "#" + "".join("%02X" % v for v in (np.clip(c, 0, 1) * 255).round().astype(int))


def recipes_for(R, palette):
    out = []
    for h in palette:
        b = R.best(km.hex_rgb(h))
        out.append(dict(target="#" + h.upper(), mix=hexs(b["mixed"]), de=round(b["de"] * 100, 1),
                        parts=[[R.set.names[i], p] for i, p in sorted(b["desc"], key=lambda x: -x[1])],
                        text=b["recipe"]))
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    base = km.Recipes()
    extras = {name: km.Recipes(km.TUBES + [(name, h, s)]) for name, h, s in EXTRA}
    tubes = {name: h for name, h, _ in km.TUBES + EXTRA}
    paintings = []
    for n in sorted(os.listdir(src)):
        stats = os.path.join(src, n, "stats.json")
        if not os.path.isfile(stats):
            continue
        s = json.load(open(stats))
        rec = recipes_for(base, s["palette"])
        mean = float(np.mean([r["de"] for r in rec]))
        best = None
        for name, R in extras.items():
            m = float(np.mean([R.best(km.hex_rgb(h))["de"] * 100 for h in s["palette"]]))
            if best is None or m < best[1]:
                best = (name, m)
        add = None
        if best and mean - best[1] > 0.15:
            fixed = recipes_for(extras[best[0]], s["palette"])
            add = dict(tube=best[0], meanBefore=round(mean, 2), meanAfter=round(best[1], 2),
                       improves=[i + 1 for i, (a, b) in enumerate(zip(rec, fixed)) if b["de"] < a["de"] - 1.0])
        for i, r in enumerate(rec):
            r["number"] = i + 1
            r["nickname"] = s["colorNicknames"][i]
        paintings.append(dict(name=n, paints=rec, addTube=add))
    json.dump(dict(tubes=[dict(name=k, hex=v) for k, v in tubes.items()],
                   basic=[t[0] for t in km.TUBES], paintings=paintings), open(dst, "w"), indent=1)


if __name__ == "__main__":
    main()
