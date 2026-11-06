#!/usr/bin/env python3
"""Adds manual entries to the app's string catalog, keeping Xcode's layout so the diff is only them.

    tools/catalog_add.py entries.json

entries.json is a list of {"key", "comment", "value"?, "after"?}: "value" (an explicit key's English)
writes localizations.en; "after" inserts the key after that neighbour (else in sorted order).
Run tools/strings_check.py afterwards.
"""
import collections, json, sys

CATALOG = "App/PaintByNumber/Resources/Localizable.xcstrings"

def main(path):
    entries = json.load(open(path))
    catalog = json.load(open(CATALOG), object_pairs_hook=collections.OrderedDict)
    strings = catalog["strings"]
    for e in entries:
        entry = collections.OrderedDict([("comment", e["comment"]), ("extractionState", "manual")])
        if "value" in e:
            entry["localizations"] = {"en": {"stringUnit": {"state": "translated", "value": e["value"]}}}
        items = [(k, v) for k, v in strings.items() if k != e["key"]]
        after = e.get("after")
        if after is None:
            at = next((i for i, (k, _) in enumerate(items) if k > e["key"]), len(items))
        else:
            at = [k for k, _ in items].index(after) + 1
        items.insert(at, (e["key"], entry))
        strings = collections.OrderedDict(items)
    catalog["strings"] = strings
    with open(CATALOG, "w") as f:
        f.write(json.dumps(catalog, indent=2, separators=(",", " : "), ensure_ascii=False) + "\n")

if __name__ == "__main__":
    main(sys.argv[1])
