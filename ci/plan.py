#!/usr/bin/env python3
"""Leaves out of a run on main the simulator entries that already passed on the same files.

    LANES='["ipad", "ipad-ui", …]' ci/plan.py        (the workflow's `plan` job; needs GH_TOKEN)
    ci/plan.py --self-test

A branch's run tests `ipad` and `ipad-ui` before its merge. When the merge leaves main with the
very files that run tested (main fast-forwarded to the branch, as a night train lands; or a merge
commit of a branch that already held main, whose tree is its second parent's), main's run would
only repeat them: about three hours of a macOS runner. So for a push to main this looks up
the check runs of the pushed commit and of each parent with the same tree, and an entry whose job
passed there, in another run, is left out; STATUS.md names the run it passed in. Anything else
(another branch, a run started by hand, a commit with other files, an API that doesn't answer)
keeps every entry: leaving one out needs proof, running it needs none.

Writes `lanes` (the entries to run, JSON) and `before` ({entry: the run it passed in}, JSON) to
$GITHUB_OUTPUT. The demo caches main's `ipad` and `ipad-ui` keep for the branches are then only
as fresh as its last run of them: a branch that misses them makes its own (the warm-up).
"""
import json
import os
import re
import sys
import urllib.request

# The entries' job names, as `jobs.apple.name` in ci.yml gives them (the self-test compares): a
# check run is found by its name.
NAMES = {
    "ipad": "iPad — build, screenshots, unit tests, Release check",
    "ipad-ui": "iPad — UI tests",
    "iphone": "iPhone — build, screenshots, unit tests",
    "iphone-ui": "iPhone — UI tests",
    "release-tests": "iPad — App Store build, its tests",
}


def api(path):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/{path}",
        headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def same_files(sha):
    """The commit and each of its parents with the same tree."""
    commit = api(f"git/commits/{sha}")
    found = [sha]
    for parent in commit["parents"]:
        if api(f"git/commits/{parent['sha']}")["tree"]["sha"] == commit["tree"]["sha"]:
            found.append(parent["sha"])
    return found


def check_runs(sha):
    """Every check run of the commit: `filter=all`, since the default keeps only the newest of
    each name, which is this run's own, still waiting."""
    found, page = [], 1
    while page <= 10:
        batch = api(f"commits/{sha}/check-runs?filter=all&per_page=100&page={page}")["check_runs"]
        found += batch
        if len(batch) < 100:
            break
        page += 1
    return found


def passed(lanes, runs, this_run):
    """{entry: URL of the job it passed in} among `runs`, never a job of this run."""
    mine = re.compile(rf"/actions/runs/{this_run}/")
    before = {}
    for lane in lanes:
        for run in runs:
            url = run.get("html_url") or run.get("details_url") or ""
            if (run.get("name") == NAMES.get(lane) and run.get("conclusion") == "success"
                    and (run.get("app") or {}).get("slug") == "github-actions"
                    and "/actions/runs/" in url and not mine.search(url)):
                before[lane] = url
                break
    return before


def main():
    lanes = json.loads(os.environ["LANES"])
    before = {}
    if os.environ.get("GITHUB_REF_NAME") == "main" and os.environ.get("GITHUB_EVENT_NAME") == "push":
        try:
            runs = [run for sha in same_files(os.environ["GITHUB_SHA"]) for run in check_runs(sha)]
            before = passed(lanes, runs, os.environ["GITHUB_RUN_ID"])
        except Exception as error:  # no answer is no proof: every entry runs
            print(f"::warning::ci/plan.py couldn't look up earlier runs ({type(error).__name__}: {error}); every entry runs")
            before = {}
    lanes = [lane for lane in lanes if lane not in before]
    for lane, url in before.items():
        print(f"{lane}: passed on the same files in {url}; left out")
    print("entries:", " ".join(lanes) or "none")
    with open(os.environ["GITHUB_OUTPUT"], "a") as out:
        out.write(f"lanes={json.dumps(lanes)}\nbefore={json.dumps(before)}\n")
    return 0


def self_test():
    def run(name, conclusion, run_id, slug="github-actions"):
        url = f"https://github.com/o/r/actions/runs/{run_id}/job/{run_id}1"
        return {"name": name, "conclusion": conclusion, "html_url": url, "app": {"slug": slug}}

    runs = [
        run(NAMES["ipad"], None, 7),             # this run's own, waiting
        run(NAMES["ipad"], "success", 5),
        run(NAMES["ipad-ui"], "failure", 5),
        run(NAMES["ipad-ui"], "success", 7),      # this run's own never counts
        run(NAMES["iphone"], "success", 6, slug="someone-else"),
        run(NAMES["release-tests"], "cancelled", 5),
        run("iPad — compile check", "success", 4),
    ]
    assert passed(list(NAMES), runs, "7") == {"ipad": "https://github.com/o/r/actions/runs/5/job/51"}
    assert passed(["ipad"], runs, "5") == {}
    assert passed(["compile", "ipad-ui"], runs, "9") == {"ipad-ui": "https://github.com/o/r/actions/runs/7/job/71"}
    # Run 7 is not run 70.
    assert passed(["ipad-ui"], runs, "70") == {"ipad-ui": "https://github.com/o/r/actions/runs/7/job/71"}
    workflow = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".github", "workflows", "ci.yml")
    with open(workflow) as f:
        text = f.read()
    for lane, name in NAMES.items():
        assert f"'{name}'" in text, f"ci.yml names no job {name!r} ({lane}): keep NAMES in step with jobs.apple.name"
    print("plan: self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(self_test() if sys.argv[1:] == ["--self-test"] else main())
