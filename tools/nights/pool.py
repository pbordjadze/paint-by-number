#!/usr/bin/env python3
"""Adds the pictures chosen by eye to Tonight's Picture's pool (painting-company row 368).

    tools/nights/pool.py --picks PICKS.json DIR [DIR ...] [--pool tools/nights/pool.json]

The way a picture gets into the pool: catalog.py gathers a museum's open-access works into
DIR/candidates.jsonl under the library's license and subject rules, judge.py makes each one's
template and lays the good ones out on contact sheets, a person (or a critic) looks at the sheets
and writes PICKS.json, [{"id", "title"}] with a short natural title for each, and this script turns
each pick's judged record (found in any DIR's judged.jsonl) into a pool record and appends it to the
pool, after the pictures already there: publish.py takes pictures in the pool's order, so the
order of what is already there never changes. A pick already in the pool is skipped, and so is one
whose record isn't "ok".

A pool record is what publish.py and the app's `Nights.Picture` read: id, title, creator, year,
credit, license, source (the museum's page), evidence (the license, as the museum states it),
medium, place, kind, and download (the museum's full-size file, which publish.py sizes once).
Every fact is a string; publish.py adds image, thumb and sha256.
"""
import argparse
import json
import sys
from pathlib import Path

FIELDS = ("creator", "year", "credit", "license", "source", "evidence", "medium", "place")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", type=Path, nargs="+")
    ap.add_argument("--picks", type=Path, required=True)
    ap.add_argument("--pool", type=Path, default=Path(__file__).with_name("pool.json"))
    a = ap.parse_args()
    judged = {}
    for d in a.dirs:
        for line in (d / "judged.jsonl").open():
            r = json.loads(line)
            judged[r["id"]] = r
    pool = json.loads(a.pool.read_text()) if a.pool.exists() else []
    have = {r["id"] for r in pool}
    added = 0
    for pick in json.loads(a.picks.read_text()):
        r = judged.get(pick["id"])
        if pick["id"] in have:
            continue
        if not r or r.get("verdict") != "ok" or r.get("rejected"):
            print(f"{pick['id']}: not an ok judged record, skipped", file=sys.stderr)
            continue
        title = " ".join(str(pick.get("title") or r["title"]).split())
        if not title or len(title) > 200:
            print(f"{pick['id']}: no usable title, skipped", file=sys.stderr)
            continue
        record = {"id": r["id"], "title": title, "kind": "painting"}
        for f in FIELDS:
            value = r.get(f)
            record[f] = "" if value is None else str(value)
        record["creator"] = record["creator"][:200]
        record["download"] = r["image"]
        pool.append(record)
        have.add(r["id"])
        added += 1
    a.pool.write_text(json.dumps(pool, ensure_ascii=False, indent=1) + "\n")
    print(f"{added} added; the pool holds {len(pool)}", file=sys.stderr)


if __name__ == "__main__":
    main()
