#!/usr/bin/env python3
"""Lists the files Paint by Mosaic (`App/Ravenna`) still keeps as its own copy of the app's.

    python3 tools/era_twins.py [--identical]

Code both eras use lives once in `App/Shared`, compiled into both modules (App/CLAUDE.md ›
Ravenna). A file of the same name in `App/PaintByNumber` and `App/Ravenna` is a copy that has
not been shared yet: this prints each pair with the lines that differ (0 means the pair can
move to `App/Shared` as it is), smallest first. `--identical` prints only those, as paths, and
exits 1 when there are any (a copy that drifted back to identical, or was added twice).
"""
import difflib
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
app, era = root / "App/PaintByNumber", root / "App/Ravenna"
names = {}
for path in sorted(app.rglob("*.swift")):
    names.setdefault(path.name, path)
rows = []
for path in sorted(era.rglob("*.swift")):
    twin = names.get(path.name)
    if twin is None:
        continue
    a, b = twin.read_text().splitlines(), path.read_text().splitlines()
    same = sum(block.size for block in difflib.SequenceMatcher(None, a, b, autojunk=False).get_matching_blocks())
    rows.append((len(a) + len(b) - 2 * same, len(a), len(b), path.relative_to(era), twin.relative_to(app)))
rows.sort()
if "--identical" in sys.argv[1:]:
    identical = [row for row in rows if row[0] == 0]
    for row in identical:
        print(row[3])
    sys.exit(1 if identical else 0)
for differing, a, b, path, twin in rows:
    print(f"{differing:5d} differ  app {a:5d}  mosaic {b:5d}  {path}" + ("" if path == twin else f"  (app: {twin})"))
print(f"{len(rows)} copies, {sum(row[2] for row in rows)} lines in App/Ravenna")
