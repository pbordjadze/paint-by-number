#!/usr/bin/env python3
"""Puts the App Store screenshots on the App Store version being prepared, through the App Store
Connect API.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8=… python3 ci/store_screenshots_upload.py SLIDES [--upload]

SLIDES holds one folder per screenshot display type, named for it (APP_IPHONE_61, APP_IPHONE_67,
APP_IPAD_PRO_3GEN_129, …), each with 1.png … 10.png in App Store order: what
tools/store_screenshots.py renders (iphone-63-* is 1206 × 2622, iphone-69-* 1320 × 2868, ipad-13-*
2064 × 2752). It may also hold the creative assets App Store Connect shows from iOS 27 on, one
image each in a folder named for its placement type, `CREATIVE`: PRODUCT_PAGE_HEADER_ASSET/1.png
(3840 × 1646) and APP_STORE_SEARCH_RESULTS_ASSET/1.png (3:2, 1920 × 1280 to 3840 × 2560), or the
universal 5244 × 2950 in either. Run by `.github/workflows/store-screenshots.yml`, which reads
SLIDES from the private feedback repository: the slides show the painter's own photos, which never
go in this public one.

It checks the slides first, before anything changes: each folder a display type of `SIZES`, 1 to
10 files, each a PNG of one of that type's sizes (portrait or landscape) with no alpha channel or
transparency, as App Store Connect demands. Then it finds the app by its bundle id, its iOS version
in an editable state (Prepare for Submission, or rejected) and that version's LOCALE (en-US)
localization. Without --upload it stops there and lists the screenshot sets the version has, the
folders SLIDES has and any problem with them, changing nothing (a missing SLIDES is fine then).
With --upload, for each folder it replaces that display type's set, unless the set already holds
these files in this order (their MD5s): deletes the screenshots in it, reserves each file, sends
its parts where App Store Connect says, commits it with its MD5, puts the set in file order. Then
it waits for App Store Connect to process the images and fails naming any it refused. A creative
asset goes to the app's Asset Library (its reference name carrying its MD5, which is how a re-run
knows it is there already), then onto the version's localization as its placement, replacing the
one there; Apple reviews it with the version. The dry run also prints what App Store Connect says
the creative placements take.

The appScreenshotSets and appScreenshots endpoints are marked deprecated (API 4.5, in favour of
the App Asset Library) but still served; if they go, this is the script to move.

The repository's logs are public: nothing here prints a secret, an image or an upload URL (those
are signed). Needs `cryptography` (ES256 tokens, through ci/testflight_testers.py's client).
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from testflight_testers import APIError, Client, find_app, private_key, summarize

# The states in which a version's metadata can still be changed.
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")
# The sizes App Store Connect takes for each display type, in portrait (landscape is the same
# turned): Apple's screenshot specifications, as fastlane maps them to the API's types.
SIZES = {
    "APP_IPHONE_61": {(1179, 2556), (1206, 2622)},
    "APP_IPHONE_67": {(1260, 2736), (1290, 2796), (1320, 2868)},
    "APP_IPAD_PRO_3GEN_129": {(2048, 2732), (2064, 2752)},
}
# The creative assets (the product page header and the search results card, iOS 27 and later),
# each one image a folder, landscape only: the sizes of Apple's creative assets specifications.
CREATIVE = {"PRODUCT_PAGE_HEADER_ASSET": "Header", "APP_STORE_SEARCH_RESULTS_ASSET": "Search results"}
# How long App Store Connect may take to process the images once they are sent.
PROCESSING_MINUTES = 15


def creative_size_ok(kind, width, height):
    if (width, height) == (5244, 2950):  # the universal 16:9 image, either placement
        return True
    if kind == "PRODUCT_PAGE_HEADER_ASSET":
        return (width, height) == (3840, 1646)
    return width * 2 == height * 3 and 1920 <= width <= 3840


def editable_version(client, app_id):
    versions = client.call("GET", f"/apps/{app_id}/appStoreVersions", query={
        "filter[platform]": "IOS", "filter[appVersionState]": ",".join(EDITABLE), "limit": "10"})["data"]
    if not versions:
        raise APIError("no iOS version is in a state whose screenshots can be changed")
    return versions[0]


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


def png_problem(path, kind):
    """Why App Store Connect would refuse this file for `kind`, or None."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return f"{path.name} is not a PNG"
    width, height = int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
    if kind in CREATIVE:
        if not creative_size_ok(kind, width, height):
            return f"{path.name} is {width} x {height}, not a size {kind} takes"
    elif (width, height) not in SIZES[kind] and (height, width) not in SIZES[kind]:
        return f"{path.name} is {width} x {height}, not a size {kind} takes"
    # Colour types 4 and 6 carry alpha; a tRNS chunk makes a colour transparent.
    if data[25] in (4, 6) or b"tRNS" in data[:data.find(b"IDAT")]:
        return f"{path.name} has an alpha channel or transparency"
    return None


def problems(found):
    """Everything wrong with the slides, checked before anything is changed."""
    found_problems = []
    for kind, files in found.items():
        if kind not in SIZES and kind not in CREATIVE:
            found_problems.append(f"{kind} is not a display or placement type this script knows "
                                  f"({', '.join([*SIZES, *CREATIVE])})")
            continue
        if kind in CREATIVE and len(files) != 1:
            found_problems.append(f"{kind} has {len(files)} files; it takes one, 1.png")
        if len(files) > 10:
            found_problems.append(f"{kind} has {len(files)} files; a set holds at most 10")
        found_problems += [f"{kind}: {p}" for p in (png_problem(f, kind) for f in files) if p]
    return found_problems


def unchanged(client, set_id, files):
    """Whether the set already holds these files, processed, in this order."""
    existing = client.call("GET", f"/appScreenshotSets/{set_id}/appScreenshots", query={
        "fields[appScreenshots]": "sourceFileChecksum,assetDeliveryState", "limit": "50"})["data"]
    return (len(existing) == len(files)
            and all((e["attributes"].get("assetDeliveryState") or {}).get("state") == "COMPLETE" for e in existing)
            and [e["attributes"].get("sourceFileChecksum") for e in existing]
            == [hashlib.md5(f.read_bytes()).hexdigest() for f in files])


def send_parts(operations, data):
    """Sends the file's parts to the signed URLs App Store Connect gave; never prints them."""
    for operation in operations:
        offset, length = operation["offset"], operation["length"]
        request = urllib.request.Request(operation["url"], data=data[offset:offset + length], method=operation["method"])
        headers = {h["name"]: h["value"] for h in operation.get("requestHeaders") or []}
        if not any(name.lower() == "content-type" for name in headers):
            headers["Content-Type"] = "image/png"  # urllib would otherwise send a form's type
        for name, value in headers.items():
            request.add_header(name, value)
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
    if kind in sets and unchanged(client, set_id, files):
        print(f"{kind}: already these {len(files)} screenshots, left as is.", flush=True)
        return []
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


def creative_specs(client):
    """What App Store Connect says the creative placements take, for the dry run's log."""
    try:
        data = client.call("GET", "/appAssetLibraryRefData",
                           query={"filter[placementTypes]": ",".join(CREATIVE)})["data"]
    except APIError as error:
        return [f"Creative asset specs: unavailable ({error})"]
    lines = []
    for datum in data:
        attributes = datum["attributes"]
        for spec in attributes.get("imageSpecs") or []:
            if set(spec.get("compatiblePlacementTypes") or []) & set(CREATIVE):
                lines.append(f"Spec {spec.get('specId')} {spec.get('shortName')}: {json.dumps(spec.get('dimensions'))} "
                             f"{spec.get('aspectRatio')} alpha={spec.get('alphaAllowed')} max={spec.get('maxFileSize')} "
                             f"{','.join(spec.get('fileExtensions') or [])} universal={spec.get('universalAsset')} "
                             f"for {','.join(spec.get('compatiblePlacementTypes') or [])}")
        for feature in attributes.get("features") or []:
            for policy in feature.get("placementPolicies") or []:
                if policy.get("placementType") in CREATIVE:
                    lines.append(f"Policy {feature.get('featureId')} {policy['placementType']}: "
                                 f"{json.dumps(policy.get('groupLimits'))}")
    return lines or ["Creative asset specs: none listed"]


def placements(client, localization_id, kind):
    """The version's placements of `kind`, each with its image's reference name."""
    found = client.call("GET", f"/appStoreVersionLocalizations/{localization_id}/placements", query={
        "filter[placementType]": kind, "include": "image", "limit": "50"})
    names = {i["id"]: i["attributes"].get("referenceName") for i in found.get("included") or []
             if i["type"] == "appAssetLibraryImages"}
    return [(p, names.get(((p.get("relationships") or {}).get("image") or {}).get("data", {}).get("id")))
            for p in found["data"]]


def replace_creative(client, app_id, localization_id, kind, path):
    """Puts the image on the version as its `kind` placement, unless it is already there (its
    reference name carries its MD5); returns the new placement's id, or None."""
    data = path.read_bytes()
    reference = f"{CREATIVE[kind]} {hashlib.md5(data).hexdigest()[:12]}"
    file_name = CREATIVE[kind].lower().replace(" ", "-") + path.suffix  # how the Asset Library lists it
    existing = placements(client, localization_id, kind)
    if len(existing) == 1 and existing[0][1] == reference and existing[0][0]["attributes"].get("state") != "FAILED":
        print(f"{kind}: already {path.name} ({reference}), left as is.", flush=True)
        return None
    for placement, _ in existing:
        client.call("DELETE", f"/appAssetLibraryPlacements/{placement['id']}")
    library = client.call("GET", f"/apps/{app_id}/assetLibrary")["data"]["id"]
    image = client.call("POST", "/appAssetLibraryImages", {"data": {
        "type": "appAssetLibraryImages",
        "attributes": {"category": "CREATIVE_ASSETS", "fileName": file_name, "fileSize": len(data), "referenceName": reference},
        "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": library}}}}})["data"]
    send_parts(image["attributes"]["uploadOperations"], data)
    client.call("PATCH", f"/appAssetLibraryImages/{image['id']}", {"data": {
        "type": "appAssetLibraryImages", "id": image["id"], "attributes": {"uploaded": True}}})
    print(f"{kind}: sent {path.name} ({len(data) // 1024} KB) as {reference!r}.", flush=True)
    deadline = time.time() + PROCESSING_MINUTES * 60
    while True:
        attributes = client.call("GET", f"/appAssetLibraryImages/{image['id']}")["data"]["attributes"]
        state = attributes.get("state")
        if state == "FAILED":
            reasons = "; ".join(f"{d.get('code')}: {d.get('description')}" for d in attributes.get("stateDetails") or [])
            raise APIError(f"App Store Connect refused {kind} {path.name}: {reasons or 'failed'}")
        if state not in ("AWAITING_UPLOAD", "UPLOAD_COMPLETE"):
            break
        if time.time() >= deadline:
            raise APIError(f"{kind} {path.name} still processing after {PROCESSING_MINUTES} minutes")
        print(f"Waiting for App Store Connect to process {kind} ({state})…", flush=True)
        time.sleep(15)
    placement = client.call("POST", "/appAssetLibraryPlacements", {"data": {
        # DEFAULT_PROFILE: the one placement group the reference data lists for these (one each).
        "type": "appAssetLibraryPlacements", "attributes": {"placementType": kind, "placementGroup": "DEFAULT_PROFILE"},
        "relationships": {"image": {"data": {"type": "appAssetLibraryImages", "id": image["id"]}},
                          "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations",
                                                                   "id": localization_id}}}}})["data"]
    return placement["id"]


def wait_until_placed(client, ids_by_kind):
    """Fails naming each placement App Store Connect refused; returns once none is processing."""
    deadline = time.time() + PROCESSING_MINUTES * 60
    pending = dict(ids_by_kind)
    while pending:
        for kind, placement_id in list(pending.items()):
            attributes = client.call("GET", f"/appAssetLibraryPlacements/{placement_id}")["data"]["attributes"]
            state = attributes.get("state")
            if state == "FAILED":
                reasons = "; ".join(f"{d.get('code')}: {d.get('description')}" for d in attributes.get("stateDetails") or [])
                raise APIError(f"App Store Connect refused the {kind} placement: {reasons or 'failed'}")
            if state != "ASSET_PROCESSING":
                print(f"{kind}: placed ({state}).", flush=True)
                del pending[kind]
        if pending:
            if time.time() >= deadline:
                raise APIError(f"{', '.join(pending)} still processing after {PROCESSING_MINUTES} minutes")
            time.sleep(15)


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
        raise APIError("App Store Connect refused " + " | ".join(refused))


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
    app = find_app(client)
    found = slides(args.slides)
    wrong = problems(found)
    version = editable_version(client, app["id"])
    name = version["attributes"].get("versionString")
    target = localization(client, version["id"], args.locale)
    sets = screenshot_sets(client, target["id"])
    placed = {kind: [f"{p['attributes'].get('state')} {name or '?'}" for p, name in placements(client, target["id"], kind)]
              for kind in CREATIVE}
    print(f"Version {name}, {args.locale}: sets {', '.join(sorted(sets)) or 'none'}.")
    for kind, now in placed.items():
        print(f"{kind}: {', '.join(now) or 'none'}.")
    print(f"Slides: {', '.join(f'{k} ({len(v)})' for k, v in found.items()) or 'none found'}.")
    for problem in wrong:
        print(f"Problem: {problem}")
    if not args.upload:
        specs = creative_specs(client)
        for line in specs:
            print(line)
        summarize([f"### Version {name}, {args.locale} (dry run, nothing changed)",
                   f"Screenshot sets now: {', '.join(sorted(sets)) or 'none'}."]
                  + [f"{kind} now: {', '.join(now) or 'none'}." for kind, now in placed.items()]
                  + [f"Slides found: {', '.join(f'{k} ({len(v)})' for k, v in found.items()) or 'none'}."]
                  + [f"- Problem: {p}" for p in wrong] + [f"- {line}" for line in specs])
        if wrong:
            sys.exit(f"{len(wrong)} problems with the slides")
        return
    if not found:
        sys.exit(f"No slides under {args.slides}: one folder per display type, each with 1.png, 2.png, …")
    if wrong:
        sys.exit(f"{len(wrong)} problems with the slides, nothing changed")
    ids_by_kind = {kind: replace_set(client, target["id"], sets, kind, files)
                   for kind, files in found.items() if kind in SIZES}
    placed = {kind: replace_creative(client, app["id"], target["id"], kind, files[0])
              for kind, files in found.items() if kind in CREATIVE}
    wait_until_processed(client, ids_by_kind)
    wait_until_placed(client, {kind: i for kind, i in placed.items() if i})
    lines = [f"{kind}: {len(found[kind])} screenshots{'' if ids else ', unchanged'}" for kind, ids in ids_by_kind.items()]
    lines += [f"{kind}: {found[kind][0].name}{'' if i else ', unchanged'}" for kind, i in placed.items()]
    print("Done. " + "; ".join(lines) + ".")
    summarize([f"### Screenshots on version {name}, {args.locale}"] + [f"- {line}" for line in lines])


if __name__ == "__main__":
    try:
        main()
    except APIError as error:
        sys.exit(f"Store screenshots: {error}")
