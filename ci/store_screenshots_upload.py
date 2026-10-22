#!/usr/bin/env python3
"""Puts the App Store screenshots on the App Store version being prepared, through the App Store
Connect API.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8=… python3 ci/store_screenshots_upload.py SLIDES [--upload]

SLIDES holds one folder per screenshot display type, named for it (APP_IPHONE_61, APP_IPHONE_67,
APP_IPAD_PRO_3GEN_129, …), each with 1.png … 10.png in App Store order: what
tools/store_screenshots.py renders (iphone-63-* is 1206 × 2622, iphone-69-* 1320 × 2868, ipad-13-*
2064 × 2752). Run by `.github/workflows/store-screenshots.yml`, which reads SLIDES from the private
feedback repository: the slides show the painter's own photos, which never go in this public one.

It finds the app by its bundle id, its iOS version in an editable state (Prepare for Submission,
or rejected) and that version's LOCALE (en-US) localization. Without --upload it stops there and
lists the screenshot sets the version has and the folders SLIDES has, changing nothing (a missing
SLIDES is fine then). With --upload, for each folder it replaces that display type's set: deletes
the screenshots in it, reserves each file, sends its parts where App Store Connect says, commits
it with its MD5, puts the set in file order, then waits for App Store Connect to process the
images and fails naming any it refused (a wrong size means a wrong folder name). Every step reads
what is there first, so running it again leaves the same set.

The repository's logs are public: nothing here prints a secret, an image or an upload URL (those
are signed). Needs `cryptography` (ES256 tokens, through ci/testflight_testers.py's client).
"""

import argparse
import hashlib
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from testflight_testers import BUNDLE_ID, APIError, Client, private_key, summarize

# The states in which a version's metadata can still be changed.
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
# How long App Store Connect may take to process the images once they are sent.
PROCESSING_MINUTES = 15


def editable_version(client, app_id):
    versions = client.call("GET", f"/apps/{app_id}/appStoreVersions",
                           query={"filter[platform]": "IOS", "limit": "10"})["data"]
    for version in versions:
        attributes = version["attributes"]
        if (attributes.get("appVersionState") or attributes.get("appStoreState")) in EDITABLE:
            return version
    states = ", ".join(f"{v['attributes'].get('versionString')}: "
                       f"{v['attributes'].get('appVersionState') or v['attributes'].get('appStoreState')}"
                       for v in versions)
    raise APIError(f"no iOS version can be edited ({states or 'none'})")


def localization(client, version_id, locale):
    found = client.call("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")["data"]
    for item in found:
        if item["attributes"]["locale"] == locale:
            return item
    raise APIError(f"the version has no {locale} localization ({', '.join(i['attributes']['locale'] for i in found)})")


def screenshot_sets(client, localization_id):
    found = client.call("GET", f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")["data"]
    return {item["attributes"]["screenshotDisplayType"]: item for item in found}


def slides(folder):
    """{display type: [files in App Store order]}: N.png files, sorted by N."""
    found = {}
    for kind in (sorted(p for p in folder.iterdir() if p.is_dir()) if folder.is_dir() else []):
        files = sorted((p for p in kind.iterdir() if re.fullmatch(r"\d+\.png", p.name)), key=lambda p: int(p.stem))
        if files:
            found[kind.name] = files
    return found


def send_parts(operations, data):
    """Sends the file's parts to the signed URLs App Store Connect gave; never prints them."""
    for operation in operations:
        offset, length = operation["offset"], operation["length"]
        request = urllib.request.Request(operation["url"], data=data[offset:offset + length], method=operation["method"])
        for header in operation.get("requestHeaders") or []:
            request.add_header(header["name"], header["value"])
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                response.read()
        except urllib.error.HTTPError as error:
            raise APIError(f"sending a part of {length} bytes: {error.code} {error.reason}") from None


def replace_set(client, localization_id, sets, kind, files):
    screenshot_set = sets.get(kind)
    if screenshot_set is None:
        body = {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": kind},
                         "relationships": {"appStoreVersionLocalization": {
                             "data": {"type": "appStoreVersionLocalizations", "id": localization_id}}}}}
        screenshot_set = client.call("POST", "/appScreenshotSets", body)["data"]
    set_id = screenshot_set["id"]
    for old in client.call("GET", f"/appScreenshotSets/{set_id}/appScreenshots", query={"limit": "50"})["data"]:
        client.call("DELETE", f"/appScreenshots/{old['id']}")
    ids = []
    for path in files:
        data = path.read_bytes()
        body = {"data": {"type": "appScreenshots", "attributes": {"fileName": path.name, "fileSize": len(data)},
                         "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}}
        reserved = client.call("POST", "/appScreenshots", body)["data"]
        send_parts(reserved["attributes"]["uploadOperations"], data)
        client.call("PATCH", f"/appScreenshots/{reserved['id']}", {"data": {
            "type": "appScreenshots", "id": reserved["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        ids.append(reserved["id"])
        print(f"{kind}: sent {path.name} ({len(data) // 1024} KB).", flush=True)
    client.call("PATCH", f"/appScreenshotSets/{set_id}/relationships/appScreenshots",
                {"data": [{"type": "appScreenshots", "id": i} for i in ids]})
    return ids


def wait_until_processed(client, ids_by_kind):
    """Fails naming each screenshot App Store Connect refused; returns once all are complete."""
    deadline = time.time() + PROCESSING_MINUTES * 60
    pending = {i: kind for kind, ids in ids_by_kind.items() for i in ids}
    refused = []
    while pending:
        for screenshot_id, kind in list(pending.items()):
            attributes = client.call("GET", f"/appScreenshots/{screenshot_id}",
                                     query={"fields[appScreenshots]": "fileName,assetDeliveryState"})["data"]["attributes"]
            state = attributes.get("assetDeliveryState") or {}
            if state.get("state") == "COMPLETE":
                del pending[screenshot_id]
            elif state.get("state") == "FAILED":
                reasons = "; ".join(f"{e.get('code')}: {e.get('description')}" for e in state.get("errors") or [])
                refused.append(f"{kind} {attributes.get('fileName')}: {reasons or 'refused'}")
                del pending[screenshot_id]
        if pending:
            if time.time() >= deadline:
                raise APIError(f"{len(pending)} screenshots still processing after {PROCESSING_MINUTES} minutes")
            print(f"Waiting for App Store Connect to process {len(pending)} screenshots…", flush=True)
            time.sleep(20)
    if refused:
        raise APIError("App Store Connect refused: " + " | ".join(refused))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("slides", type=Path)
    parser.add_argument("--upload", action="store_true", help="replace the sets (otherwise only list them)")
    parser.add_argument("--locale", default="en-US")
    args = parser.parse_args()
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"):
        if not os.environ.get(name):
            sys.exit(f"{name} is not set")
    client = Client(private_key())
    apps = client.call("GET", "/apps", query={"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"No App Store Connect app has the bundle id {BUNDLE_ID}")
    version = editable_version(client, apps[0]["id"])
    name = version["attributes"].get("versionString")
    target = localization(client, version["id"], args.locale)
    sets = screenshot_sets(client, target["id"])
    found = slides(args.slides)
    print(f"Version {name}, {args.locale}: sets {', '.join(sorted(sets)) or 'none'}.")
    print(f"Slides: {', '.join(f'{k} ({len(v)})' for k, v in found.items()) or 'none found'}.")
    if not args.upload:
        summarize([f"### Version {name}, {args.locale} (dry run, nothing changed)",
                   f"Screenshot sets now: {', '.join(sorted(sets)) or 'none'}.",
                   f"Slides found: {', '.join(f'{k} ({len(v)})' for k, v in found.items()) or 'none'}."])
        return
    if not found:
        sys.exit(f"No slides under {args.slides}: one folder per display type, each with 1.png, 2.png, …")
    ids_by_kind = {kind: replace_set(client, target["id"], sets, kind, files) for kind, files in found.items()}
    wait_until_processed(client, ids_by_kind)
    lines = [f"{kind}: {len(ids)} screenshots" for kind, ids in ids_by_kind.items()]
    print("Done. " + "; ".join(lines) + ".")
    summarize([f"### Screenshots on version {name}, {args.locale}"] + [f"- {line}" for line in lines])


if __name__ == "__main__":
    try:
        main()
    except APIError as error:
        sys.exit(f"App Store Connect refused: {error}")
