#!/usr/bin/env python3
"""Whether the checks and the measuring are still what they were at a commit (painting-company row 292): what a
long change that must lose no feature, and must not move its own goalposts, shows before it is judged.

    tools/frozen.py <frozen commit> [<commit>]        (the second defaults to HEAD)

Three things, each listed when it fails, and exit 1 if any does:
1. The frozen paths are unchanged: the tests, their fixtures and corpora, the gates and their baselines, this
   file, tools/checks.sh, the measuring tools, the demo scenarios, the tour log, the project's configurations.
2. Every line the tour log writes is written as it was: each `TourLog.trace(…)` statement of the app, wherever it
   now lives (a file may be split or renamed; the statement may not change).
3. The recorders the tests read are as they were: the lines of `SoundPlayer`'s and `HapticsPlayer`'s Debug-only
   records of what they were asked to play, and `CanvasView.frameUniforms`.
A check that turns out wrong is changed in a commit of its own that says so, and the frozen commit moves to it.
"""
import collections, re, subprocess, sys

PATHS = [
    "App/PaintByNumberTests", "App/PaintByNumberUITests", "Tests",
    "tools/checks.sh", "tools/frozen.py", "tools/regression.py", "tools/baseline", "tools/strings_check.py", "tools/tests",
    "tools/perf-tour", "tools/template_hashes.py",
    "ci/check_release.sh", "ci/warnings.sh", "ci/scenarios.txt", "ci/screenshots.sh",
    "App/PaintByNumber/App/TourLog.swift", "App/PaintByNumber/App/DemoMode.swift", "App/PaintByNumber/App/ShellDemo.swift",
    "App/PaintByNumber/Features/Paint/PaintDemoView.swift", "App/PaintByNumber/Features/MakingOf/MakingOfDemoView.swift",
    "App/PaintByNumber/Generation/LineArtMapsCache.swift", "App/PaintByNumber/Model/DemoTemplateCache.swift",
    "App/PaintByNumber/Canvas/SyntheticTemplate.swift", "App/PaintByNumber.xcodeproj/project.pbxproj",
]
RECORDER = re.compile(
    r"\basked\b|\bmade\.append\(|\bdescribe\(|func (played|patterns|samples|frameUniforms)\(|struct (Pattern|Event|Curve|Cue)\b|enum Voice\b"
    r"|tourRested|tourLastTick|tourStart|tourFrames")


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def lines_of(commit):
    """The tour log's statements and the recorders' lines in the app's sources at `commit`, as multisets."""
    traces, recorders = collections.Counter(), collections.Counter()
    for path in git("ls-tree", "-r", "--name-only", commit, "--", "App/PaintByNumber").splitlines():
        if not path.endswith(".swift") or path.endswith("App/TourLog.swift"):
            continue
        source = git("show", f"{commit}:{path}").splitlines()
        i = 0
        while i < len(source):
            line = source[i].strip()
            if "TourLog.trace(" in line:
                statement = line
                while statement.count("(") > statement.count(")") and i + 1 < len(source):
                    i += 1
                    statement += " " + source[i].strip()
                traces[statement] += 1
            elif RECORDER.search(line) and not line.startswith("//"):
                recorders[line] += 1
            i += 1
    return traces, recorders


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    frozen, head = sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    failed = False
    changed = git("diff", "--stat", f"{frozen}..{head}", "--", *PATHS).strip()
    if changed:
        failed = True
        print("1. frozen paths changed:\n" + changed)
    else:
        print("1. frozen paths: unchanged (%d paths)" % len(PATHS))
    (traces_then, recorders_then), (traces_now, recorders_now) = lines_of(frozen), lines_of(head)
    for number, what, then, now in ((2, "tour log statements", traces_then, traces_now), (3, "recorder lines", recorders_then, recorders_now)):
        gone, new = then - now, now - then
        if gone or new:
            failed = True
            print(f"{number}. {what} changed:")
            for line, n in sorted(gone.items()):
                print(f"   gone ({n}): {line}")
            for line, n in sorted(new.items()):
                print(f"   new ({n}): {line}")
        else:
            print(f"{number}. {what}: as they were ({sum(then.values())})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
