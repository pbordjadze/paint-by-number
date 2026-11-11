#!/usr/bin/env python3
"""One step of a QA explore relay session (ci/qa/qa.py's `send`), with a screenshot at device pixels.

  RUN=<run id> BR=<relay branch> [OUT=<dir>] tools/qa_relay_step.py "<maestro steps>" [--shot <name>] [--inspect]

Sends, as one relay call: the Maestro steps (YAML list items, without the appId header), then with
--shot a `takeScreenshot` into the runner's out/shots/<name>.png (the full-resolution PNG the run
publishes to refs/qa-runs/<run id>: `git fetch origin refs/qa-runs/<id>:refs/qa-runs/<id>` and
`git show refs/qa-runs/<id>:shots/<name>.png`), then with --inspect the screen's elements, and
last Maestro's own screenshot (scaled to 1500 px wide, for a quick look). An empty steps string
just takes the screenshot. Painting-company row 237 drove its newcomer QA with it; the relay
session itself is the QA explore workflow's `relay` mode (its header). Keep each call under two
minutes of the app's time or run it in the background: `send` waits up to 600 s.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Where the workflow's checkout puts out/ on the macOS runner.
SHOTS = "/Users/runner/work/paint-by-number/paint-by-number/out/shots"


def main():
    if len(sys.argv) < 2 or "RUN" not in os.environ or "BR" not in os.environ:
        sys.exit(__doc__)
    steps, flags = sys.argv[1], sys.argv[2:]
    header = "appId: com.pbordjadze.paintbynumber\n---\n"
    calls = []
    if steps.strip():
        calls.append({"tool": "run", "arguments": {"yaml": header + steps}})
    if "--shot" in flags:
        name = flags[flags.index("--shot") + 1]
        calls.append({"tool": "run", "arguments": {"yaml": header + f"- takeScreenshot: {SHOTS}/{name}\n"}})
    if "--inspect" in flags:
        calls.append({"tool": "inspect_screen", "arguments": {}})
    calls.append({"tool": "take_screenshot", "arguments": {}})
    out = os.environ.get("OUT", f"qa-relay-{os.environ['RUN']}")
    result = subprocess.run(
        ["python3", "ci/qa/qa.py", "send", os.environ["RUN"], json.dumps(calls), "--branch", os.environ["BR"],
         "--out", out, "--wait", "600", "--chars", "6000"], cwd=ROOT)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
