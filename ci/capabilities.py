#!/usr/bin/env python3
"""Warns when the app is signed with an entitlement the developer site doesn't have yet.

    python3 ci/capabilities.py [--self-test]

Reads every `*.entitlements` under `App/` and compares each key (and each value of a list, such
as an app group) with `ci/developer-site.json`, the record of what Certificates, Identifiers &
Profiles already carries. App Store Connect's API can turn some capabilities on, but it can't
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
    """(file, key, value) for each entitlement; value is None for a key that isn't a list."""
    found = []
    for path in sorted(paths):
        with open(path, "rb") as handle:
            entitlements = plistlib.load(handle)
        for key, value in sorted(entitlements.items()):
            if isinstance(value, list):
                found += [(path, key, str(item)) for item in value]
            else:
                found.append((path, key, None))
    return found


def missing(found, record):
    known = record["entitlements"]
    gaps = []
    for path, key, value in found:
        entry = known.get(key)
        if entry is None or (value is not None and value not in entry.get("values", [])):
            gaps.append((path, key, value))
    return gaps


def report(found, gaps):
    for path, key, value in gaps:
        what = f"{key} = {value}" if value is not None else key
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
    record = {"entitlements": {"a.groups": {"values": ["g1"]}, "b.flag": {}}}
    with tempfile.TemporaryDirectory() as folder:
        one = os.path.join(folder, "One.entitlements")
        with open(one, "wb") as handle:
            plistlib.dump({"a.groups": ["g1", "g2"], "b.flag": True, "c.new": True}, handle)
        found = wanted([one])
        assert len(found) == 4, found
        gaps = missing(found, record)
        assert [(k, v) for _, k, v in gaps] == [("a.groups", "g2"), ("c.new", None)], gaps
        assert missing([found[0], found[2]], record) == [], "recorded entries pass"
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
