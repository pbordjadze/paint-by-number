#!/usr/bin/env python3
"""Puts a key of the app's string catalog into Paint by Mosaic's, with that era's words.

    python3 tools/era_words.py "<key>" ["<Paint by Mosaic's English>"]

A shared file (`App/Shared`) looks its words up in the era's catalog (`bundle: .era`): the key is
the app's, and Paint by Mosaic's catalog says its own words for it. This copies the app's entry
(comment, plural forms) into `App/RavennaResources/Localizable.xcstrings` in place, with the
English value given (none: the app's words). `--unused` instead lists that catalog's keys no
source of `App/Ravenna` or `App/Shared` mentions any more.
"""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
APP, ERA = root / "App/PaintByNumber/Resources/Localizable.xcstrings", root / "App/RavennaResources/Localizable.xcstrings"


def write(catalog):
    ERA.write_text(json.dumps(catalog, indent=2, separators=(",", ": "), ensure_ascii=False) + "\n")


def main():
    era = json.loads(ERA.read_text())
    if sys.argv[1:] == ["--unused"]:
        text = "".join(p.read_text() for d in ("App/Ravenna", "App/Shared") for p in sorted((root / d).rglob("*.swift")))
        text += (root / "App/RavennaResources/Samples/library.json").read_text()
        for key in era["strings"]:
            if json.dumps(key, ensure_ascii=False)[1:-1] not in text and not key.startswith("sample."):
                print(key)
        return
    key, value = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else None)
    entry = json.loads(json.dumps(json.loads(APP.read_text())["strings"][key]))
    if value is not None:
        if "variations" in json.dumps(entry):
            sys.exit(f"{key} has plural forms: write Paint by Mosaic's by hand")
        entry["localizations"] = {"en": {"stringUnit": {"state": "translated", "value": value}}}
    strings, placed = {}, False
    for k, v in era["strings"].items():
        if k == key:
            continue
        if not placed and k.lower() > key.lower():
            strings[key], placed = entry, True
        strings[k] = v
    if not placed:
        strings[key] = entry
    era["strings"] = strings
    write(era)


main()
