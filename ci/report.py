#!/usr/bin/env python3
"""Writes the CI report's STATUS.md from the jobs' artifacts, to standard output.

    ci/report.py <report-dir> <job>=<result> ...

The arguments name every job in the order STATUS.md lists them, with the result the workflow
gives it (`needs.<job>.result`; a simulator job of the matrix gets the matrix's). The first
lines keep the form `<job>: <result>` that readers of STATUS.md look for. A simulator job
(its artifact holds `outcomes.txt`) gets its own result from its steps' outcomes, then a line
of details below: its steps, its tests' counts, the tests that failed or passed only when run
again, the screenshot scenarios that never signalled readiness, and its crash reports.
`--self-test` checks the parsing on made-up results.
"""
import json
import os
import re
import sys


def outcomes(job_dir):
    """`step=outcome` pairs from the job's outcomes.txt, in order; None without the file."""
    path = os.path.join(job_dir, "outcomes.txt")
    if not os.path.isfile(path):
        return None
    with open(path) as f:
        return [tuple(pair.split("=", 1)) for pair in f.read().split() if "=" in pair]


def job_result(steps, matrix_result):
    """A simulator job's result from its steps; the matrix's when it left no outcomes."""
    if steps is None:
        return "cancelled" if matrix_result == "cancelled" else f"no report ({matrix_result})"
    states = {outcome for _, outcome in steps}
    for state in ("failure", "cancelled"):
        if state in states:
            return state
    return "success"


def messages(node):
    """The failure messages under a test node, in order."""
    found = []
    for child in node.get("children") or []:
        if child.get("nodeType") == "Failure Message":
            found.append(child.get("name", ""))
        else:
            found.extend(messages(child))
    return found


def test_cases(node, path=()):
    """(suite/test name, node) for every test case under `node`."""
    if node.get("nodeType") == "Test Case":
        yield "/".join(path[-1:] + (node.get("name", "?"),)), node
        return
    if node.get("nodeType") == "Test Suite":
        path = path + (node.get("name", "?"),)
    for child in node.get("children") or []:
        yield from test_cases(child, path)


def classify(node):
    """passed, failed, skipped or flaky (failed, then passed when run again)."""
    runs = [c.get("result") for c in node.get("children") or [] if c.get("nodeType") == "Repetition"]
    final = runs[-1] if runs else node.get("result")
    if final == "Passed" and ("Failed" in runs[:-1] or node.get("result") == "Failed"):
        return "flaky"
    return {"Passed": "passed", "Failed": "failed", "Skipped": "skipped", "Expected Failure": "passed"}.get(final, "failed")


def test_summary(results):
    """A count line and the failed and flaky tests with their first message."""
    counts = {"passed": 0, "failed": 0, "skipped": 0, "flaky": 0}
    notes = []
    for root in results.get("testNodes") or []:
        for name, node in test_cases(root):
            kind = classify(node)
            counts[kind] += 1
            if kind in ("failed", "flaky"):
                first = next(iter(messages(node)), "")
                label = "failed" if kind == "failed" else "passed when run again"
                notes.append(f"  {label}: {name}: {first[:300]}")
    total = sum(counts.values())
    parts = [f"{counts['passed'] + counts['flaky']} passed"]
    if counts["failed"]:
        parts.append(f"{counts['failed']} failed")
    if counts["skipped"]:
        parts.append(f"{counts['skipped']} skipped")
    if counts["flaky"]:
        parts.append(f"{counts['flaky']} only when run again")
    return f"{total} tests: " + ", ".join(parts), notes


def screenshot_notes(job_dir):
    """Scenarios without a ready marker and crashes, from the screenshots' steps log."""
    notes = []
    shots = os.path.join(job_dir, "shots")
    for name in sorted(os.listdir(shots)) if os.path.isdir(shots) else []:
        if not name.endswith("-steps.log"):
            continue
        with open(os.path.join(shots, name), errors="replace") as f:
            text = f.read()
        unready = re.findall(r"(\S+): no ready marker within (\d+) s", text)
        crashed = re.findall(r"captured (\S+) — CRASH", text)
        if unready:
            notes.append("  no ready marker (taken at the timeout): " + ", ".join(f"{s} ({t} s)" for s, t in unready))
        if crashed:
            notes.append("  crashed: " + ", ".join(crashed))
    return notes


def simulator_lines(job, job_dir, steps):
    """The job's details: the steps that went wrong, its tests, and notes below."""
    parts = [", ".join(f"{step} {outcome}" for step, outcome in steps if outcome not in ("success", "skipped"))]
    notes = []
    results_path = os.path.join(job_dir, "test-results.json")
    if os.path.isfile(results_path):
        try:
            with open(results_path) as f:
                counts, notes = test_summary(json.load(f))
            parts.append(counts)
        except (OSError, ValueError) as error:
            parts.append(f"test results unreadable ({error})")
    detail = "; ".join(part for part in parts if part) or "every step passed"
    notes += screenshot_notes(job_dir)
    crashes = os.path.join(job_dir, "crashes")
    if os.path.isdir(crashes) and os.listdir(crashes):
        notes.append(f"  crash reports: {len(os.listdir(crashes))} in {job}/crashes/")
    return [f"{job}: {detail}"] + notes


def last_line(path):
    try:
        with open(path, errors="replace") as f:
            lines = [line.rstrip() for line in f if line.strip()]
    except OSError:
        return None
    return lines[-1] if lines else None


def main(argv):
    if argv[1:] == ["--self-test"]:
        return self_test()
    report, jobs = argv[1], [arg.split("=", 1) for arg in argv[2:]]
    head, details = [], []
    for job, result in jobs:
        job_dir = os.path.join(report, job)
        steps = outcomes(job_dir)
        if steps is None and not os.path.isdir(job_dir) and result != "skipped" and job in ("ipad", "ipad-ui", "iphone"):
            # A matrix job that left no artifact: planned but lost, or not planned at all.
            head.append(f"{job}: {job_result(None, result)}")
            continue
        if steps is not None:
            head.append(f"{job}: {job_result(steps, result)}")
            details += simulator_lines(job, job_dir, steps)
        else:
            head.append(f"{job}: {result}")
        if job == "core":
            for label, path in (("regression", "regression/regression.txt"), ("strings", "strings-check.log")):
                last = last_line(os.path.join(job_dir, path))
                if last:
                    head.append(f"{label}: {last}")
    print("\n".join(head))
    if details:
        print()
        print("\n".join(details))
    return 0


def self_test():
    def case(name, result, *runs, message=None):
        children = [{"nodeType": "Repetition", "result": r} for r in runs]
        if message:
            children.append({"nodeType": "Failure Message", "name": message})
        return {"nodeType": "Test Case", "name": name, "result": result, "children": children}

    results = {"testNodes": [{"nodeType": "Test Plan", "children": [{"nodeType": "UI test bundle", "children": [
        {"nodeType": "Test Suite", "name": "Suite", "children": [
            case("a()", "Passed"),
            case("b()", "Failed", message="B.swift:1: broke"),
            case("c()", "Passed", "Failed", "Passed", message="C.swift:2: flaked"),
            case("d()", "Skipped"),
            case("e()", "Failed", "Failed", "Failed", message="E.swift:3: broke twice"),
        ]}]}]}]}
    counts, notes = test_summary(results)
    assert counts == "5 tests: 2 passed, 2 failed, 1 skipped, 1 only when run again", counts
    assert notes == [
        "  failed: Suite/b(): B.swift:1: broke",
        "  passed when run again: Suite/c(): C.swift:2: flaked",
        "  failed: Suite/e(): E.swift:3: broke twice",
    ], notes
    assert job_result([("build", "success"), ("tests", "failure")], "failure") == "failure"
    assert job_result([("build", "success"), ("tests", "success"), ("release", "skipped")], "failure") == "success"
    assert job_result(None, "cancelled") == "cancelled"
    print("report: self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
