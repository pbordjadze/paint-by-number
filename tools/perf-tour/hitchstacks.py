#!/usr/bin/env python3
"""What the main thread was doing in each hitch of a segment, from a run made with the app's
`-tourStacks YES` (`HitchStacks`; `run.sh -s`; painting-company row 390).

    hitchstacks.py <segment> <tour-log.tsv>...      (start, open, zen-30, finish, ...)

For every `hitch` line inside the segment (from `<segment> begin` to its end, or to the log's end):
its offset in seconds after the begin mark, its gap, the last mark before it, and its `stacks` line:
how many of the sampler's stack reads fell inside the gap, then the app's innermost frames (what of
ours was running), its outermost (what of ours started the work) and the innermost frames of all,
each "count x name", most first. Swift names are demangled with `swift demangle --simplified`
(or `xcrun swift-demangle`) when either is on the PATH, and left mangled otherwise. `-` as an app
frame means a read with none of ours on the stack (the system's own work: layout, rendering,
an animation's commit).
"""
import shutil, subprocess, sys

FIELDS = ("inner", "outer", "leaf")


def demangler():
    if shutil.which("swift"):
        return ["swift", "demangle", "--simplified", "--compact"]
    if shutil.which("xcrun"):
        return ["xcrun", "swift-demangle", "--simplified", "--compact"]
    return None


def demangle_all(names):
    command = demangler()
    names = sorted(names)
    if not command or not names:
        return {n: n for n in names}
    try:
        out = subprocess.run(command, input="\n".join(names) + "\n", capture_output=True, text=True, check=True).stdout
        lines = out.split("\n")
        return {n: (lines[i] if i < len(lines) and lines[i] else n) for i, n in enumerate(names)}
    except (OSError, subprocess.CalledProcessError):
        return {n: n for n in names}


def counts(field):
    """'3×name | 1×other' -> [(3, 'name'), (1, 'other')]"""
    out = []
    for part in field.split(" | ") if field else []:
        count, _, name = part.partition("×")
        out.append((count, name))
    return out


def main(segment, paths):
    runs = []
    names = set()
    for path in paths:
        events = []
        for raw in open(path):
            p = raw.rstrip("\n").split("\t")
            if len(p) >= 2:
                try:
                    events.append((float(p[0]), p[1], p[2:]))
                except ValueError:
                    pass
        begin = next((t for t, k, f in events if k == "mark" and f and f[0].startswith(f"{segment} begin")), None)
        end = next((t for t, k, f in events if k == "mark" and f and f[0].startswith(f"{segment} end")), None)
        stacks = [(t, dict(x.split("=", 1) for x in f if "=" in x)) for t, k, f in events if k == "stacks"]
        for _, s in stacks:
            for field in FIELDS:
                names.update(n for _, n in counts(s.get(field, "")))
        runs.append((path, events, begin, end, stacks))
    named = demangle_all(names)
    for path, events, begin, end, stacks in runs:
        print(f"== {path.split('/')[-1]}  {segment} begin={begin} end={end}")
        if begin is None:
            continue
        if not stacks:
            print("  (no stacks lines: was the run made with -tourStacks YES?)")
        stop = end if end is not None else float("inf")
        used = set()
        for t, k, f in events:
            if k != "hitch" or not begin <= t <= stop:
                continue
            gap = f[0].split("=")[1] if f else "?"
            mark = next((f2[0] for t2, k2, f2 in reversed(events) if k2 == "mark" and t2 <= t and f2), "")
            print(f"  +{t - begin:7.3f} s  gap {gap:>6} ms  after: {mark}")
            match = next((i for i, (t2, s) in enumerate(stacks)
                          if i not in used and t <= t2 + 0.05 and t2 - t < 3 and s.get("gap") == gap), None)
            if match is None:
                print("      no stacks line")
                continue
            used.add(match)
            s = stacks[match][1]
            print(f"      samples {s.get('samples', '?')}")
            for field, title in zip(FIELDS, ("ours, innermost", "ours, outermost", "innermost")):
                for count, name in counts(s.get(field, "")):
                    print(f"      {title:16} {count:>3}  {named.get(name, name)[:220]}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2:])
