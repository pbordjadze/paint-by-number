#!/usr/bin/env python3
"""Leaves out of a run on main the simulator entries that already passed on the same files.

    LANES='["ipad", "ipad-ui", …]' ci/plan.py        (the workflow's `plan` job; needs GH_TOKEN)
    ci/plan.py --self-test

A branch's run tests `ipad` and `ipad-ui` before its merge. When the merge leaves main with the
very files that run tested (main fast-forwarded to the branch, as a night train lands; or a merge
commit of a branch that already held main, whose tree is its second parent's), main's run would
only repeat them: about three hours of a macOS runner. So for a push to main this looks up
the check runs of the pushed commit and of each parent with the same tree, and an entry whose job
passed there, in another run a push started (one started by hand may have been given only some
scenarios), is left out; STATUS.md names the run it passed in. Anything else
(another branch, a run started by hand, a commit with other files, an API that doesn't answer)
keeps every entry: leaving one out needs proof, running it needs none.

And it gives one entry of a branch's run to the Mac (painting-company row 346): a runner of our
own, labelled `pbm-mac`, beside GitHub's five, which runs one job at a time. With the repository
variable MAC_CI `on` (the workflow passes it as MAC) and no job of ours waiting for the Mac or
running on it, the run's longest entry goes there (FOR_MAC, in order); every other entry, and
every entry of main's runs, stays on GitHub's runners, so a Mac that is asleep, paused for a
speed measurement (`ci-pause` there) or busy holds up one branch at most, and never main.
GitHub would keep a job waiting a day for a runner that isn't there, so the workflow's `mac-watch`
job (`ci/plan.py --watch`) cancels a run whose entry the Mac hasn't taken in 15 minutes; an entry
cancelled so, in the last six hours, keeps the Mac out of the plans after it. Start the run again
(or push) and GitHub's runners take every entry.

Writes `lanes` (the entries to run, JSON), `matrix` (the same with each entry's runner:
[{"job": …, "on": …}]) and `before` ({entry: the run it passed in}, JSON) to $GITHUB_OUTPUT. The demo caches main's `ipad` and `ipad-ui` keep for the branches are then only
as fresh as its last run of them: a branch that misses them makes its own (the warm-up).
"""
import json
import os
import re
import sys
import time
import urllib.request
from datetime import datetime, timedelta, timezone

# The entries' job names, as `jobs.apple.name` in ci.yml gives them (the self-test compares): a
# check run is found by its name.
NAMES = {
    "ipad": "iPad — build, screenshots, unit tests, Release check",
    "ipad-ui": "iPad — UI tests",
    "iphone": "iPhone — build, screenshots, unit tests",
    "iphone-ui": "iPhone — UI tests",
    "release-tests": "iPad — App Store build, its tests",
}


HOSTED, MAC = "xcode-27", "pbm-mac"
# The entry the Mac takes, the first of these a run has: the longest, and the quick checks a
# session waits on.
FOR_MAC = ("ipad-ui", "compile", "test", "duo", "release-tests", "ipad")


# How long the Mac has to take an entry, and how long one it never took keeps it out of the plans.
WAIT, AWAY = timedelta(minutes=15), timedelta(hours=6)


def api(path, method="GET"):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/{path}", method=method,
        headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        return json.loads(body) if body.strip() else {}


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


def pushed(run_id):
    """Whether a push started the workflow run."""
    return api(f"actions/runs/{run_id}")["event"] == "push"


def passed(lanes, runs, this_run, pushed=pushed):
    """{entry: URL of the job it passed in} among `runs`: a job of a run a push started, never
    of this run."""
    before = {}
    for lane in lanes:
        for run in runs:
            url = run.get("html_url") or run.get("details_url") or ""
            found = re.search(r"/actions/runs/(\d+)/", url)
            if (run.get("name") == NAMES.get(lane) and run.get("conclusion") == "success"
                    and (run.get("app") or {}).get("slug") == "github-actions"
                    and found and found.group(1) != str(this_run) and pushed(found.group(1))):
                before[lane] = url
                break
    return before


def moment(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def never_taken(job, now):
    """Whether the job is an entry the Mac was given and never took: cancelled, at most AWAY ago,
    after waiting WAIT or nearly, with no runner's name on it."""
    if MAC not in (job.get("labels") or []) or job.get("conclusion") != "cancelled" or job.get("runner_name"):
        return False
    if not job.get("created_at") or not job.get("completed_at"):
        return False
    made, ended = moment(job["created_at"]), moment(job["completed_at"])
    return now - ended <= AWAY and ended - made >= WAIT - timedelta(minutes=5)


def mac_is_free():
    """Whether no job of this repository waits for the Mac or runs on it, and it took the last
    entries it was given."""
    for status in ("queued", "in_progress"):
        for run in api(f"actions/runs?status={status}&per_page=50")["workflow_runs"]:
            if str(run["id"]) == os.environ["GITHUB_RUN_ID"]:
                continue
            for job in api(f"actions/runs/{run['id']}/jobs?per_page=100")["jobs"]:
                if MAC in (job.get("labels") or []) and job.get("status") != "completed":
                    return False
    now = datetime.now(timezone.utc)
    for run in api("actions/runs?status=cancelled&per_page=20")["workflow_runs"]:
        if now - moment(run["updated_at"]) > AWAY:
            break
        if any(never_taken(job, now) for job in api(f"actions/runs/{run['id']}/jobs?per_page=100")["jobs"]):
            return False
    return True


def watch():
    """Cancels this run if the Mac hasn't taken its entry WAIT after the entry was made."""
    run = os.environ["GITHUB_RUN_ID"]
    while True:
        waiting = [job for job in api(f"actions/runs/{run}/jobs?per_page=100")["jobs"]
                   if MAC in (job.get("labels") or []) and job.get("status") == "queued"]
        if not waiting:
            print("mac-watch: the Mac took its entry (or the run gave it none)")
            return 0
        if datetime.now(timezone.utc) - moment(waiting[0]["created_at"]) >= WAIT:
            print(f"::error::The Mac (runner {MAC}) didn't take its entry in {int(WAIT.total_seconds() // 60)} minutes: "
                  "asleep, paused or off. This run is cancelled; start it again and GitHub's runners take every entry.")
            api(f"actions/runs/{run}/cancel", method="POST")
            return 1
        time.sleep(60)


def routed(lanes, mac):
    """[{job, on}]: the first of FOR_MAC the run has on the Mac when it may take one."""
    taken = next((lane for lane in FOR_MAC if lane in lanes), None) if mac else None
    return [{"job": lane, "on": MAC if lane == taken else HOSTED} for lane in lanes]


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
    mac = False
    if os.environ.get("MAC") == "on" and os.environ.get("GITHUB_REF_NAME") != "main" and lanes:
        try:
            mac = mac_is_free()
        except Exception as error:  # no answer: GitHub's runners, which are always there
            print(f"::warning::ci/plan.py couldn't see the Mac's queue ({type(error).__name__}: {error}); GitHub's runners take every entry")
    matrix = routed(lanes, mac)
    for lane, url in before.items():
        print(f"{lane}: passed on the same files in {url}; left out")
    print("entries:", " ".join(f"{entry['job']} ({entry['on']})" for entry in matrix) or "none")
    with open(os.environ["GITHUB_OUTPUT"], "a") as out:
        out.write(f"lanes={json.dumps(lanes)}\nmatrix={json.dumps(matrix)}\nbefore={json.dumps(before)}\n")
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
    def any_push(run_id):
        return True

    assert passed(list(NAMES), runs, "7", any_push) == {"ipad": "https://github.com/o/r/actions/runs/5/job/51"}
    assert passed(["ipad"], runs, "5", any_push) == {}
    assert passed(["compile", "ipad-ui"], runs, "9", any_push) == {"ipad-ui": "https://github.com/o/r/actions/runs/7/job/71"}
    # Run 7 is not run 70.
    assert passed(["ipad-ui"], runs, "70", any_push) == {"ipad-ui": "https://github.com/o/r/actions/runs/7/job/71"}
    # A run started by hand proves nothing: it may have taken only some scenarios.
    assert passed(list(NAMES), runs, "7", lambda run_id: run_id != "5") == {}
    assert routed(["ipad", "ipad-ui"], True) == [{"job": "ipad", "on": HOSTED}, {"job": "ipad-ui", "on": MAC}]
    assert routed(["ipad", "ipad-ui"], False) == [{"job": "ipad", "on": HOSTED}, {"job": "ipad-ui", "on": HOSTED}]
    assert routed(["compile"], True) == [{"job": "compile", "on": MAC}]
    assert routed(["iphone", "iphone-ui"], True) == [{"job": "iphone", "on": HOSTED}, {"job": "iphone-ui", "on": HOSTED}]
    assert routed([], True) == []
    now = datetime(2026, 11, 14, 22, 0, tzinfo=timezone.utc)
    gone = {"labels": [MAC], "conclusion": "cancelled", "runner_name": "",
            "created_at": "2026-11-14T20:00:00Z", "completed_at": "2026-11-14T20:15:30Z"}
    assert never_taken(gone, now)
    assert not never_taken({**gone, "runner_name": "pauls-mbp"}, now)      # cut off at work
    assert not never_taken({**gone, "labels": [HOSTED]}, now)
    assert not never_taken({**gone, "completed_at": "2026-11-14T20:02:00Z"}, now)  # a newer push came
    assert not never_taken(gone, now + AWAY)
    assert not never_taken({**gone, "conclusion": "success"}, now)
    workflow = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".github", "workflows", "ci.yml")
    with open(workflow) as f:
        text = f.read()
    for lane, name in NAMES.items():
        assert f"'{name}'" in text, f"ci.yml names no job {name!r} ({lane}): keep NAMES in step with jobs.apple.name"
    print("plan: self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(self_test() if sys.argv[1:] == ["--self-test"] else watch() if sys.argv[1:] == ["--watch"] else main())
