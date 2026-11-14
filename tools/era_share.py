#!/usr/bin/env python3
"""Moves a file the app and Paint by Mosaic each keep a copy of into `App/Shared` (painting-company row 336).

    python3 tools/era_share.py <path under App/PaintByNumber> …      e.g. Model/Log.swift

The shared file is the app's, with the seams the copy already had named for both eras: where a
line of Paint by Mosaic's copy differs from the app's only by `bundle: .ravenna`,
`UserDefaults.ravenna` or `RavennaTipSwitch`, the shared line asks the module instead
(`bundle: .era`, `UserDefaults.era`, `TipSwitch`: each module's `App/SharedSeams.swift`). Every
other difference is printed and the app's line kept: settle each by hand (a seam, a word in
Paint by Mosaic's catalog, or the app's behavior for both) before committing, and run
`tools/strings_check.py`, which holds a shared file to `bundle: .era`. `tools/era_twins.py`
lists the copies left.
"""
import difflib
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent


def named(line):
    """A line of Paint by Mosaic's copy with its seams asked of the module."""
    return (line.replace("bundle: .ravenna", "bundle: .era").replace("UserDefaults = .ravenna", "UserDefaults = .era")
            .replace("UserDefaults.ravenna", "UserDefaults.era").replace("RavennaTipSwitch", "TipSwitch"))


def plain(line):
    """The same line as the app wrote it before there were seams."""
    line = re.sub(r",\s*bundle: \.ravenna", "", line)
    return (line.replace("UserDefaults = .ravenna", "UserDefaults = .standard")
            .replace("UserDefaults.ravenna", "UserDefaults.standard").replace("RavennaTipSwitch", "TipSwitch"))


for rel in sys.argv[1:]:
    app, era, shared = root / "App/PaintByNumber" / rel, root / "App/Ravenna" / rel, root / "App/Shared" / rel
    a, b = app.read_text().splitlines(), era.read_text().splitlines()
    out, left = [], []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, [plain(l) for l in b], autojunk=False).get_opcodes():
        if tag == "equal":
            out += [named(l) for l in b[j1:j2]]
        else:
            out += a[i1:i2]
            left.append((i1, a[i1:i2], b[j1:j2]))
    shared.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "mv", str(app), str(shared)], check=True)
    shared.write_text("\n".join(out) + "\n")
    subprocess.run(["git", "rm", "-q", str(era)], check=True)
    print(f"{rel}: shared" + (f", {len(left)} differences kept as the app's:" if left else ""))
    for line, ours, theirs in left:
        print(f"  line {line + 1}")
        for l in ours:
            print("    app    " + l.strip()[:150])
        for l in theirs:
            print("    mosaic " + l.strip()[:150])
