#!/usr/bin/env python3
"""Copies TestFlight's beta feedback (screenshots with a comment, and crashes) into a folder.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8=… python3 ci/testflight_feedback.py <out> [--days 14]

What testers send from the TestFlight app (a screenshot's Share Beta Feedback, or a crash's) lands
in App Store Connect, not in the feedback relay. This writes each submission of the last `--days`
days to `<out>/<YYYY-MM-DD>/testflight-<id>/` (beside the relay's reports): `submission.json` (Apple's record, as it came), `feedback.md`
(the comment, device, build and time) and the screenshots (`screenshot-<n>.jpg`), or for a crash
`crash.txt` (its log). A submission already there is left alone, so a second run adds only new
ones; a submission that fails (a crash whose log isn't ready, a screenshot that won't
download) is tried again next run, and the run exits 1 so it is seen. Run by `.github/workflows/testflight-feedback.yml`, which commits them to the private
feedback repository's `reports/` every hour: the comments and pictures are testers' own, so nothing of them is printed
here (the repository's logs are public), only counts. Needs `cryptography`; the client is
ci/testflight_testers.py's.
"""

import argparse
import datetime
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from testflight_testers import APIError, Client, find_app, private_key, summarize  # noqa: E402

KINDS = {
    "betaFeedbackScreenshotSubmissions": "screenshot",
    "betaFeedbackCrashSubmissions": "crash",
}


def created(item):
    """When the submission was made, in UTC (Apple's dates carry their own offset)."""
    text = item["attributes"].get("createdDate") or ""
    try:
        return datetime.datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(datetime.timezone.utc)
    except ValueError:
        return None


def submissions(client, app_id, kind, since):
    path = f"/apps/{app_id}/{kind}"
    query = {"limit": "50", "sort": "-createdDate"}
    while path:
        page = client.call("GET", path, query=query)
        for item in page.get("data", []):
            when = created(item)
            if when and when < since:
                return
            yield item
        nxt = page.get("links", {}).get("next")
        path, query = (nxt.removeprefix("https://api.appstoreconnect.apple.com/v1"), None) if nxt else (None, None)


def build_version(client, path, item):
    """The build's CFBundleVersion (e.g. 32.1), or "" when App Store Connect doesn't say."""
    try:
        build = client.call("GET", f"/{path}/{item['id']}/build").get("data") or {}
        return (build.get("attributes") or {}).get("version") or ""
    except APIError:
        return ""


def eastern(when):
    """`when` as Paul reads times: Eastern, labelled ET."""
    if when is None:
        return "?"
    from zoneinfo import ZoneInfo
    local = when.astimezone(ZoneInfo("America/New_York"))
    return local.strftime("%B %-d, %-I:%M %p ET")


def markdown(kind, item, version):
    a = item["attributes"]
    # The first line, without its "# ", is the report's issue title too (the workflow's Issues step).
    lines = [f"# TestFlight {kind} feedback, {eastern(created(item))} ({version or '?'})", ""]
    lines.append(f"{a.get('createdDate', '?')}, build {version or '?'} "
                 f"on {a.get('deviceModel', '?')} ({a.get('deviceFamily', '')}), {a.get('osVersion', '?')}")
    lines += ["", "## Comment", "", a.get("comment") or "(none)", ""]
    keys = ("appUptimeInMilliseconds", "batteryPercentage", "diskBytesAvailable", "connectionType",
            "screenWidthInPoints", "screenHeightInPoints", "locale", "timeZone", "architecture")
    lines += ["## Device", ""] + [f"- {k}: {a[k]}" for k in keys if a.get(k) is not None] + [""]
    return "\n".join(lines)


def save(client, out, path, kind, item):
    """Writes one submission; returns its folder, or None when it was already there. Anything
    that fails leaves `submission.json` (the done mark) unwritten, so the next run tries again."""
    a = item["attributes"]
    when = created(item)
    # UTC dates, as the relay's folders.
    folder = os.path.join(out, when.strftime("%Y-%m-%d") if when else "unknown", "testflight-" + item["id"])
    if os.path.exists(os.path.join(folder, "submission.json")):
        return None
    os.makedirs(folder, exist_ok=True)
    for n, shot in enumerate(a.get("screenshots") or [], 1):
        with urllib.request.urlopen(shot["url"], timeout=60) as response:
            with open(os.path.join(folder, f"screenshot-{n}.jpg"), "wb") as f:
                f.write(response.read())
    if kind == "crash":
        # Not yet processed: no log, and the next run asks again.
        log = client.call("GET", f"/betaFeedbackCrashSubmissions/{item['id']}/crashLog")
        text = log.get("data", {}).get("attributes", {}).get("logText") or ""
        if not text:
            raise APIError("crash log not ready")
        with open(os.path.join(folder, "crash.txt"), "w") as f:
            f.write(text)
    with open(os.path.join(folder, "feedback.md"), "w") as f:
        f.write(markdown(kind, item, build_version(client, path, item)))
    with open(os.path.join(folder, "submission.json"), "w") as f:
        json.dump(item, f, indent=2)
    return folder


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("out")
    parser.add_argument("--days", type=int, default=14)
    parser.add_argument("--new-list", help="a file to write the folders this run added to, one a line")
    args = parser.parse_args()
    client = Client(private_key())
    app_id = find_app(client)["id"]
    since = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=args.days)
    lines, saved, failed = [], [], False
    for path, kind in KINDS.items():
        found = new = missed = 0
        try:
            for item in submissions(client, app_id, path, since):
                found += 1
                try:
                    folder = save(client, args.out, path, kind, item)
                except (APIError, OSError) as error:
                    # The error names a path of ids or a network failure, never what a tester wrote.
                    missed += 1
                    lines.append(f"{kind} {item['id']}: {error}")
                    continue
                if folder:
                    new += 1
                    saved.append(folder)
        except (APIError, OSError) as error:
            lines.append(f"{kind}: {error}")
            failed = True
            continue
        failed = failed or missed > 0
        lines.append(f"{kind}: {found} in the last {args.days} days, {new} new, {missed} to try again")
    if args.new_list:
        with open(args.new_list, "w") as f:
            f.write("".join(folder + "\n" for folder in saved))
    print("\n".join(lines))
    summarize(lines)
    # Red, so a lasting failure (an expired key) is seen; what was saved is still committed.
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
