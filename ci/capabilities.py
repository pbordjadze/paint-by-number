#!/usr/bin/env python3
"""Warns when the app is signed with an entitlement the developer site doesn't have yet.

    python3 ci/capabilities.py [--self-test]

Reads every `*.entitlements` under `App/` and compares each one's entitlements with its own
entry in `ci/developer-site.json`, the record of what Certificates, Identifiers & Profiles already
carries for the identifiers that file signs: a key and its value (each item of a list, such as an
app group), so a capability the app has and an extension gains still warns. App Store Connect's API can turn some capabilities on, but it can't
register an app group or choose one, and has no SharePlay (Group Activities) switch, so
testflight.yml's export fails ("No profiles", "Authentication failed") until someone with an
Apple ID does the step: Xcode signed in on the Mac (an archive signed with
`-allowProvisioningUpdates`) or the developer website. This check makes that show the day the
entitlement lands, not the night of the upload (painting-company row 365). CI's `core` job runs
it as a warning, never a failure; its last line goes into STATUS.md.
"""

import glob
import json
import os
import plistlib
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECORD = os.path.join(ROOT, "ci", "developer-site.json")


def wanted(paths):
    """(file, key, value) for each entitlement, a list giving one for each of its items."""
    found = []
    for path in sorted(paths):
        with open(path, "rb") as handle:
            entitlements = plistlib.load(handle)
        for key, value in sorted(entitlements.items()):
            if isinstance(value, list):
                found += [(path, key, str(item)) for item in value]
            else:
                found.append((path, key, str(value)))
    return found


def missing(found, record):
    files = record["files"]
    gaps = []
    for path, key, value in found:
        known = files.get(os.path.relpath(path, ROOT), {})
        if key not in known:
            gaps.append((path, key, value))
            continue
        have = known[key]
        values = have if isinstance(have, list) else [have]
        if value is not None and value not in [str(item) for item in values]:
            gaps.append((path, key, value))
    return gaps


def report(found, gaps):
    for path, key, value in gaps:
        what = f"{key} = {value}"
        print(f"::warning title=Developer site::{os.path.relpath(path, ROOT)} asks for {what}, which "
              "ci/developer-site.json doesn't list: the developer site needs it before the next "
              "TestFlight upload (Xcode's Apple ID on the Mac, or by hand), then add it there")
    if gaps:
        print(f"{len(gaps)} of {len(found)} entitlements not yet on the developer site")
    else:
        print(f"all {len(found)} entitlements on the developer site")
    return gaps


def self_test():
    import tempfile
    with tempfile.TemporaryDirectory(dir=ROOT) as folder:
        one = os.path.join(folder, "One.entitlements")
        two = os.path.join(folder, "Two.entitlements")
        with open(one, "wb") as handle:
            plistlib.dump({"a.groups": ["g1", "g2"], "b.flag": True, "c.new": True, "d.env": "production"}, handle)
        with open(two, "wb") as handle:
            plistlib.dump({"b.flag": True}, handle)
        rel = lambda path: os.path.relpath(path, ROOT)
        record = {"files": {rel(one): {"a.groups": ["g1"], "b.flag": True, "d.env": "development"}}}
        found = wanted([one, two])
        gaps = [(rel(p), k, v) for p, k, v in missing(found, record)]
        assert gaps == [(rel(one), "a.groups", "g2"), (rel(one), "c.new", "True"),
                        (rel(one), "d.env", "production"), (rel(two), "b.flag", "True")], gaps
        record["files"][rel(one)].update({"a.groups": ["g1", "g2"], "c.new": True, "d.env": "production"})
        record["files"][rel(two)] = {"b.flag": True}
        assert missing(found, record) == [], "recorded entries pass"
    print("capabilities self-test passed")


def main():
    if "--self-test" in sys.argv:
        self_test()
        return 0
    with open(RECORD) as handle:
        record = json.load(handle)
    found = wanted(glob.glob(os.path.join(ROOT, "App", "**", "*.entitlements"), recursive=True))
    report(found, missing(found, record))
    return 0


if __name__ == "__main__":
    sys.exit(main())
