#!/usr/bin/env python3
"""Copies TestFlight's beta feedback (screenshots with a comment, and crashes) into a folder.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8=… python3 ci/testflight_feedback.py <out> [--days 14]

What testers send from the TestFlight app (a screenshot's Share Beta Feedback, or a crash's) lands
in App Store Connect, not in the feedback relay. This writes each submission of the last `--days`
days to `<out>/<YYYY-MM-DD>/testflight-<id>/` (beside the relay's reports): `submission.json` (Apple's record, as it came), `feedback.md`
(the comment, device, build and time) and the screenshots (`screenshot-<n>.jpg`), or for a crash
`crash.txt` (its log). A submission already there is left alone, so a second run adds only new
ones. Run by `.github/workflows/testflight-feedback.yml`, which commits them to the private
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


def submissions(client, app_id, kind, since):
    path = f"/apps/{app_id}/{kind}"
    query = {"limit": "50", "sort": "-createdDate"}
    while path:
        page = client.call("GET", path, query=query)
        for item in page.get("data", []):
            created = item["attributes"].get("createdDate", "")
            if created and created < since:
                return
            yield item
        nxt = page.get("links", {}).get("next")
        path, query = (nxt.removeprefix("https://api.appstoreconnect.apple.com/v1"), None) if nxt else (None, None)


def markdown(kind, item):
    a = item["attributes"]
    lines = [f"# TestFlight {kind} feedback", ""]
    lines.append(f"{a.get('createdDate', '?')}, build {a.get('buildBundleId', '')} "
                 f"on {a.get('deviceModel', '?')} ({a.get('deviceFamily', '')}), {a.get('osVersion', '?')}")
    lines += ["", "## Comment", "", a.get("comment") or "(none)", ""]
    keys = ("appUptimeInMilliseconds", "batteryPercentage", "diskBytesAvailable", "connectionType",
            "screenWidthInPoints", "screenHeightInPoints", "locale", "timeZone", "architecture")
    lines += ["## Device", ""] + [f"- {k}: {a[k]}" for k in keys if a.get(k) is not None] + [""]
    return "\n".join(lines)


def save(client, out, kind, item):
    a = item["attributes"]
    folder = os.path.join(out, (a.get("createdDate") or "unknown")[:10], "testflight-" + item["id"])
    if os.path.exists(os.path.join(folder, "submission.json")):
        return False
    os.makedirs(folder, exist_ok=True)
    for n, shot in enumerate(a.get("screenshots") or [], 1):
        with urllib.request.urlopen(shot["url"], timeout=60) as response:
            with open(os.path.join(folder, f"screenshot-{n}.jpg"), "wb") as f:
                f.write(response.read())
    if kind == "crash":
        try:
            log = client.call("GET", f"/betaFeedbackCrashSubmissions/{item['id']}/crashLog")
            text = log.get("data", {}).get("attributes", {}).get("logText") or ""
        except APIError as error:
            text = f"(no log: {error})"
        with open(os.path.join(folder, "crash.txt"), "w") as f:
            f.write(text)
    with open(os.path.join(folder, "feedback.md"), "w") as f:
        f.write(markdown(kind, item))
    with open(os.path.join(folder, "submission.json"), "w") as f:
        json.dump(item, f, indent=2)
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("out")
    parser.add_argument("--days", type=int, default=14)
    args = parser.parse_args()
    client = Client(private_key())
    app_id = find_app(client)["id"]
    since = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=args.days)).strftime("%Y-%m-%dT%H:%M:%S")
    lines = []
    for path, kind in KINDS.items():
        found = new = 0
        try:
            for item in submissions(client, app_id, path, since):
                found += 1
                new += save(client, args.out, kind, item)
        except APIError as error:
            lines.append(f"{kind}: {error}")
            continue
        lines.append(f"{kind}: {found} in the last {args.days} days, {new} new")
    print("\n".join(lines))
    summarize(lines)


if __name__ == "__main__":
    main()
