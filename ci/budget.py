#!/usr/bin/env python3
"""The design budget, counted from the sources: warns, never fails (stdlib only).

    python3 ci/budget.py              one line per count, a warning for each past its limit
    python3 ci/budget.py --self-test  checks the counting on small samples

The limits and their exceptions are `ci/design-budget.json`; why they exist is painting-company's
`process/design-budget.md`. They are soft (since November 17, 2026: warnings first, the numbers
revisited after a few weeks): CI runs it so that nothing it finds, nor a break in its own counting
(a function renamed, say), fails the build; `core` prints its last line in STATUS.md. On GitHub each count past its limit is also a
`::warning::` annotation on the run.

What it counts, from the sources (so it runs on Linux in a second, before any simulator):
- settings.rows: the switches and pickers of Settings (`Toggle(` and `Picker(` in SettingsView).
- menu.items: the items a menu's function can show (`Button`, `Toggle`, `Picker` and nested
  `Menu`s count one each, a nested menu's own items not at all). Branches that never show
  together (Replay or Stop) both count: an upper bound.
- choice.options: the cases of each enum a picker offers.
- screen.controls: Edit's tool rail (one control per `RefineTool`) and the Finished panel (its bar's
  four controls plus one per `FinishedDoor`).
- gates.unreleased: `#if UNRELEASED` lines under App/, engineering's count of two builds to keep.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "App", "PaintByNumber")

# The menus counted: (name, file under App/PaintByNumber, the functions whose items show in it).
MENUS = [
    ("the painting's More menu", "Features/Paint/PaintView.swift", ["moreMenu"]),
    ("a gallery card's hold menu", "Features/Gallery/GalleryView.swift", ["editingMenu"]),
    ("a gallery card's Share submenu", "Features/Gallery/GalleryView.swift", ["shareItems"]),
]

# The choices counted: (name, file under App/, enum).
CHOICES = [
    ("Palette › Rows", "Shared/Features/Paint/PaletteArrangement.swift", "PaletteRows"),
    ("Palette › Order", "Shared/Features/Paint/PaletteArrangement.swift", "PaletteOrder"),
    ("Settings › Paper", "PaintByNumber/Canvas/CanvasTypes.swift", "PaperAppearance"),
    ("Settings › Line Weight", "Shared/App/LineWeight.swift", "LineWeight"),
    ("Settings › Music", "Shared/App/Sky.swift", "SkySetting"),
    ("Painting Length", "../Sources/PaintCore/Auto/PaintingLength.swift", "PaintingLength"),
]

# Controls the Finished panel's bar always has: its name, Replay and Done (Share left on
# November 18, 2026: Send It sends the time-lapse).
FINISHED_BAR = 3


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def strip_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def body(source, name):
    """The body of the first `func name` in `source`, braces matched, comments gone."""
    source = strip_comments(source)
    match = re.search(r"func\s+" + re.escape(name) + r"\b[^{]*\{", source)
    if not match:
        raise ValueError(f"no func {name}")
    depth, start = 1, match.end()
    for i in range(start, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i]
    raise ValueError(f"func {name} never closes")


def menu_items(text):
    """Items a menu body can show: controls at its own level, a nested Menu as one. A body that
    builds the menu itself (`return Menu { … }` before any item) is counted inside it."""
    count, i = 0, 0
    token = re.compile(r"\b(Button|Toggle|Picker)\s*[({]|\bMenu\s*\{")
    first = token.search(text)
    if first and first.group(0).startswith("Menu"):
        depth, j = 1, first.end()
        while j < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[j], 0)
            j += 1
        return menu_items(text[first.end():j - 1])
    while True:
        match = token.search(text, i)
        if not match:
            return count
        count += 1
        if match.group(0).startswith("Menu"):
            # Skip the nested menu's contents: its items are the submenu's.
            depth, j = 1, match.end()
            while j < len(text) and depth:
                depth += {"{": 1, "}": -1}.get(text[j], 0)
                j += 1
            i = j
        else:
            i = match.end()


def enum_cases(source, name):
    source = strip_comments(source)
    match = re.search(r"enum\s+" + re.escape(name) + r"\b[^{]*\{", source)
    if not match:
        raise ValueError(f"no enum {name}")
    depth, i, cases = 1, match.end(), 0
    line_start = i
    while i < len(source) and depth:
        c = source[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif c == "\n":
            line = source[line_start:i].strip()
            if depth == 1 and line.startswith("case "):
                cases += len([part for part in line[5:].split(",") if part.strip()])
            line_start = i + 1
        i += 1
    return cases


def settings_rows(source):
    source = strip_comments(source)
    source = re.sub(r"#if DEBUG.*?#endif", "", source, flags=re.S)
    return len(re.findall(r"\b(?:Toggle|Picker)\s*\(", source))


def counts():
    """(budget key, what, count) for everything counted."""
    out = []
    out.append(("settings.rows", "Settings' switches and pickers",
                settings_rows(read(os.path.join(APP, "Features/Settings/SettingsView.swift")))))
    for name, path, funcs in MENUS:
        source = read(os.path.join(APP, path))
        out.append(("menu.items", name, sum(menu_items(body(source, f)) for f in funcs)))
    for name, path, enum in CHOICES:
        out.append(("choice.options", name, enum_cases(read(os.path.join(ROOT, "App", path)), enum)))
    tools = enum_cases(read(os.path.join(APP, "Features/Refine/RefineTool.swift")), "RefineTool")
    out.append(("screen.controls", "Edit's tool rail", tools))
    doors = enum_cases(read(os.path.join(APP, "Features/Paint/FinishedDoors.swift")), "FinishedDoor")
    out.append(("screen.controls", "the Finished panel (SideStore)", FINISHED_BAR + doors))
    gates = 0
    for folder, _, files in os.walk(os.path.join(ROOT, "App")):
        for f in files:
            if f.endswith(".swift"):
                gates += len(re.findall(r"^\s*#if UNRELEASED\b", read(os.path.join(folder, f)), flags=re.M))
    out.append(("gates.unreleased", "#if UNRELEASED in App/", gates))
    return out


def main():
    with open(os.path.join(ROOT, "ci", "design-budget.json"), encoding="utf-8") as f:
        budget = json.load(f)
    limits = budget["limits"]
    excepted = {(e["key"], e["what"]) for e in budget.get("exceptions", [])}
    over = []
    for key, what, count in counts():
        limit = limits[key]
        mark = ""
        if count > limit:
            if (key, what) in excepted:
                mark = "  (over, by a written exception)"
            else:
                mark = "  OVER"
                over.append(f"{what} {count}/{limit}")
                if os.environ.get("GITHUB_ACTIONS"):
                    print(f"::warning title=Design budget::{what}: {count}, its limit {limit} ({key})")
        print(f"{key:18} {what:34} {count:4} / {limit}{mark}")
    if over:
        print(f"design budget: {len(over)} over (a warning, not a failure): " + ", ".join(over))
    else:
        print("design budget: everything within its limits")
    return 0


def self_test():
    menu = """
        Toggle(isOn: $a) { Label("A", systemImage: "a") }
        Button { x() } label: { Label("B", systemImage: "b") }
        Menu {
            Button("Inside") {}
            Picker(selection: $p) { Text("P") } label: { Text("Q") }
        } label: { Label("Sub", systemImage: "c") }
        // Button("commented out")
        Button(role: .destructive) { y() } label: { Text("C") }
    """
    assert menu_items(strip_comments(menu)) == 4, menu_items(strip_comments(menu))
    built = "return Menu { " + menu + " } label: { Image(systemName: \"ellipsis\") }"
    assert menu_items(strip_comments(built)) == 4, menu_items(strip_comments(built))
    enum = """
    enum Kind: String {
        case one = 1, two, three
        /// case not counted
        case four
        var id: String { switch self { case .one: "x"
        default: "y" } }
    }
    """
    assert enum_cases(enum, "Kind") == 4, enum_cases(enum, "Kind")
    settings = """
        Toggle(isOn: $a) { Text("A") }
        Picker(selection: $b) { Text("B") } label: { Text("C") }
        #if DEBUG
        Toggle(isOn: $c) { Text("D") }
        #endif
    """
    assert settings_rows(settings) == 2
    assert body("func f() -> Int { if a { 1 } else { 2 } }\nfunc g() {}", "f").strip().startswith("if a")
    for key, what, count in counts():
        assert count > 0, what
    print("budget self-test: ok")
    return 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv[1:] else main())
