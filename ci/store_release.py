#!/usr/bin/env python3
"""Makes the App Store version for a release, picks its build and submits it for App Review.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8=… python3 ci/store_release.py VERSION BUILD [--prepare] [--submit]

VERSION is the version string the store shows (MARKETING_VERSION, e.g. 1.1) and BUILD the
TestFlight build to ship (e.g. 17.1: the build number App Store Connect lists under it).

Without a flag it is a dry run: it prints the app's iOS versions and their states, and whether
BUILD is processed, changing nothing. --prepare makes VERSION when no iOS version is being
prepared (App Store Connect allows one at a time) and sets BUILD as its build; a VERSION already
being prepared only gets BUILD. That is what the listing (ci/store_listing.py) and the screenshots
(ci/store_screenshots_upload.py) then fill in. --submit (with --prepare, or after it) adds the
version to a review submission and submits it: App Review starts, and with releaseType
AFTER_APPROVAL (ci/store-listing.json) the app goes live when it is approved. Submitting can be
cancelled in App Store Connect while the version waits for review. Each step says what it found
and did, so a rerun picks up where one stopped.

Run by `.github/workflows/store-release.yml`, on request only. Needs `cryptography` (ES256 tokens,
through ci/testflight_testers.py's client).
"""

import argparse
import os
import sys

from store_screenshots_upload import EDITABLE
from testflight_testers import APIError, Client, find_app, find_build, private_key, summarize


def versions(client, app_id):
    return client.call("GET", f"/apps/{app_id}/appStoreVersions",
                       query={"filter[platform]": "IOS", "limit": "10"})["data"]


def describe(version):
    attributes = version["attributes"]
    return f"{attributes.get('versionString')} ({attributes.get('appVersionState') or attributes.get('appStoreState')})"


def prepare(client, app_id, wanted, build, apply):
    """The version `wanted`, made if nothing is being prepared, with `build` as its build; None on a
    dry run that would make it. A version already past preparing is returned as it is."""
    found = versions(client, app_id)
    print("iOS versions: " + (", ".join(describe(v) for v in found) or "none"), flush=True)
    version = next((v for v in found if v["attributes"].get("versionString") == wanted), None)
    if version is not None and version["attributes"].get("appVersionState") not in EDITABLE:
        print(f"Version {describe(version)} is past preparing: its build stays.", flush=True)
        return version
    others = [v for v in found if v["attributes"].get("appVersionState") in EDITABLE and v is not version]
    if version is None and others:
        raise APIError(f"version {describe(others[0])} is being prepared, not {wanted}: "
                       "App Store Connect prepares one at a time")
    if version is None:
        if not apply:
            print(f"Would make version {wanted} with build {build['attributes']['version']}.")
            return None
        version = client.call("POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": wanted},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                              "build": {"data": {"type": "builds", "id": build["id"]}}}}})["data"]
        print(f"Made version {wanted} with build {build['attributes']['version']}.", flush=True)
        return version
    current = client.call("GET", f"/appStoreVersions/{version['id']}/relationships/build").get("data")
    if current and current["id"] == build["id"]:
        print(f"Version {wanted} has build {build['attributes']['version']}.", flush=True)
    elif apply:
        client.call("PATCH", f"/appStoreVersions/{version['id']}/relationships/build",
                    {"data": {"type": "builds", "id": build["id"]}})
        print(f"Set version {wanted}'s build to {build['attributes']['version']}.", flush=True)
    else:
        print(f"Would set version {wanted}'s build to {build['attributes']['version']}.")
    return version


def submit(client, app_id, version):
    """Adds `version` to the app's open review submission (made if none) and submits it. Returns
    what it says of the outcome. A submission App Review turned back (UNRESOLVED_ISSUES) is
    submitted again once the version is fixed."""
    open_ones = client.call("GET", "/reviewSubmissions", query={
        "filter[app]": app_id, "filter[platform]": "IOS",
        "filter[state]": "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"})["data"]
    waiting = [s for s in open_ones if s["attributes"].get("state") in ("WAITING_FOR_REVIEW", "IN_REVIEW")]
    if waiting:
        return f"already {waiting[0]['attributes'].get('state')}, nothing sent"
    submission = open_ones[0] if open_ones else client.call("POST", "/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    items = client.call("GET", f"/reviewSubmissions/{submission['id']}/items",
                        query={"include": "appStoreVersion"})["data"]
    for item in items:
        print(f"In the submission already: {item['id']} ({item['attributes'].get('state')})", flush=True)
    if not any((i["relationships"].get("appStoreVersion", {}).get("data") or {}).get("id") == version["id"] for i in items):
        client.call("POST", "/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
                              "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    done = client.call("PATCH", f"/reviewSubmissions/{submission['id']}", {"data": {
        "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})["data"]
    state = done["attributes"].get("state")
    print(f"Submitted version {version['attributes']['versionString']} for App Review ({state}).", flush=True)
    return f"submitted ({state})"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("version")
    parser.add_argument("build")
    parser.add_argument("--prepare", action="store_true", help="make the version and set its build")
    parser.add_argument("--submit", action="store_true", help="submit the version for App Review")
    args = parser.parse_args()
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"):
        if not os.environ.get(name):
            sys.exit(f"{name} is not set")
    client = Client(private_key())
    try:
        app = find_app(client)
        build = find_build(client, app["id"], args.build)
        print(f"Build {args.build}: processed.", flush=True)
        version = prepare(client, app["id"], args.version, build, args.prepare or args.submit)
        lines = [f"### Release {args.version} (build {args.build})"]
        if not (args.prepare or args.submit):
            lines.append("Dry run: nothing changed.")
        elif args.submit:
            lines.append(f"App Review: {submit(client, app['id'], version)}.")
        else:
            lines.append(f"Version {describe(version)} ready to fill in; not submitted.")
        summarize(lines)
    except APIError as error:
        summarize([f"### Release {args.version}: stopped", str(error)])
        sys.exit(f"Store release: {error}")


if __name__ == "__main__":
    main()
