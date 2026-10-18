#!/usr/bin/env python3
"""Build live.json, the one file the status page reads, from the front desk's pieces.

    python3 .claude/skills/front-desk/live.py <dash dir> <decisions.json> <out live.json>

<dash dir> holds sessions.json, inbox.json and account.json (sessions.py --dashboard writes
them); queue.json and releases.json are read from beside this file. Every row gets `kind`
(decision, queue, next, inbox, session, account) and a unique `key` ("<kind>:<id>"); the page
filters by kind. Publish the result with one Artifact upload and point datasets/live at it.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def rows(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except FileNotFoundError:
        return []
    return data if isinstance(data, list) else [data]


def main():
    dash, decisions, out = sys.argv[1:4]
    live = []

    def add(kind, items, ident):
        for r in items:
            r = dict(r)
            if "key" in r:
                r["ref"] = r.pop("key")
            if "kind" in r:
                r["phase"] = r.pop("kind")
            r["kind"], r["key"] = kind, f"{kind}:{ident(r)}"
            live.append(r)

    add("decision", rows(decisions), lambda r: r["id"])
    add("queue", rows(os.path.join(HERE, "queue.json")), lambda r: r["ref"])
    add("next", rows(os.path.join(HERE, "releases.json")), lambda r: r["ref"])
    add("inbox", rows(os.path.join(dash, "inbox.json")), lambda r: r["n"])
    add("session", rows(os.path.join(dash, "sessions.json")), lambda r: r["id"])
    add("account", rows(os.path.join(dash, "account.json")), lambda r: "now")
    keys = [r["key"] for r in live]
    dupes = {k for k in keys if keys.count(k) > 1}
    if dupes:
        sys.exit(f"duplicate keys: {sorted(dupes)}")
    with open(out, "w") as f:
        json.dump(live, f, ensure_ascii=False)
    size = os.path.getsize(out)
    print(f"{len(live)} rows, {size // 1024} KB -> {out}")
    if size > 8 * 1024 * 1024:
        sys.exit("over the page's 8 MB file limit")


if __name__ == "__main__":
    main()
