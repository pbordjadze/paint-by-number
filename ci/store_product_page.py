#!/usr/bin/env python3
"""Makes an App Store custom product page and sends it for review, through the App Store Connect
API (painting-company row 387).

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8=… python3 ci/store_product_page.py PAGE [--apply] [--submit]

PAGE is one page's folder, as the private feedback repository keeps it (`product-pages/<page>/`
on its `store-slides` branch, since the slides show the painter's own photos): `page.json` and one
folder of screenshots per display type, as ci/store_screenshots_upload.py takes them
(APP_IPHONE_67/1.png …, APP_IPHONE_61/, APP_IPAD_PRO_3GEN_129/). `page.json`:

    {"name": "Gift", "locale": "en-US", "promotionalText": "…",
     "keywords": ["gift", "custom"], "deepLink": null}

`name` is the page's reference name in App Store Connect, how a re-run finds it. `keywords` must be
among the app's keywords for that locale (Apple's rule: a page takes them from the latest approved
version, and each keyword leads to one page only); the dry run lists them.

Without --apply it changes nothing: it checks the slides and page.json, finds the page by name, and
prints its state and the app's keywords. With --apply it makes the page when there is none (one
version, one localization), and on its version that is still editable sets the promotional text
and deep link, replaces each display type's screenshot set unless it already holds these files in
this order (their MD5s), waits until App Store Connect has processed them, and links the keywords
(unlinking any page.json no longer names). With --submit too, it adds the version to a new review
submission of its own and submits it; App Review reviews the page apart from any app version, and
once approved it has its own URL (printed) and, made visible, shows in search for its keywords.
A draft review submission already open for the app stops it before anything is submitted, since
submitting it would send whatever else it holds.

The logs are public: nothing here prints a secret, an image or an upload URL. Needs `cryptography`,
like ci/store_screenshots_upload.py, whose checks and uploads it reuses.
"""

import argparse
import json
import os
import sys
from pathlib import Path

from store_screenshots_upload import SIZES, problems, replace_set, slides, wait_until_processed
from testflight_testers import APIError, Client, find_app, private_key, summarize

EDITABLE = ("PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "REJECTED")
# A version in these states holds the page until App Review is done with it.
REVIEWING = ("WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED")
PROMO_LIMIT = 170


def read_page(folder):
    """page.json, and everything wrong with it and the slides beside it."""
    path = folder / "page.json"
    if not path.is_file():
        return None, {}, [f"{path} is missing"]
    page = json.loads(path.read_text())
    page.setdefault("locale", "en-US")
    found = slides(folder)
    wrong = problems(found)
    wrong += [f"{kind} is not a screenshot display type" for kind in found if kind not in SIZES]
    if not isinstance(page.get("name"), str) or not page["name"].strip():
        wrong.append("page.json has no name")
    if len(page.get("promotionalText") or "") > PROMO_LIMIT:
        wrong.append(f"the promotional text is {len(page['promotionalText'])} characters; it takes {PROMO_LIMIT}")
    if not found:
        wrong.append("no screenshots: one folder per display type, each with 1.png, 2.png, …")
    return page, found, wrong


def find_page(client, app_id, name):
    pages = client.call("GET", f"/apps/{app_id}/appCustomProductPages", query={"limit": "200"})["data"]
    return next((p for p in pages if p["attributes"].get("name") == name), None)


def versions(client, page_id):
    return client.call("GET", f"/appCustomProductPages/{page_id}/appCustomProductPageVersions",
                       query={"limit": "50"})["data"]


def make_page(client, app_id, page):
    """The page with its first version and localization, in one request."""
    body = {"data": {"type": "appCustomProductPages", "attributes": {"name": page["name"]},
                     "relationships": {
                         "app": {"data": {"type": "apps", "id": app_id}},
                         "appCustomProductPageVersions": {"data": [{"type": "appCustomProductPageVersions", "id": "${version}"}]}}},
            "included": [
                {"type": "appCustomProductPageVersions", "id": "${version}",
                 "relationships": {"appCustomProductPageLocalizations": {
                     "data": [{"type": "appCustomProductPageLocalizations", "id": "${localization}"}]}}},
                {"type": "appCustomProductPageLocalizations", "id": "${localization}",
                 "attributes": {"locale": page["locale"], "promotionalText": page.get("promotionalText")}}]}
    made = client.call("POST", "/appCustomProductPages", body)["data"]
    print(f"Made the page {page['name']!r}.", flush=True)
    return made


def editable(client, page_id):
    """The page's version that can still change, made from the approved one when there is none."""
    found = versions(client, page_id)
    for version in found:
        if version["attributes"].get("state") in EDITABLE:
            return version
    if busy := [v["attributes"]["state"] for v in found if v["attributes"].get("state") in REVIEWING]:
        raise APIError(f"the page's version is {busy[0]}: it can't change until App Review is done")
    made = client.call("POST", "/appCustomProductPageVersions", {"data": {
        "type": "appCustomProductPageVersions",
        "relationships": {"appCustomProductPage": {"data": {"type": "appCustomProductPages", "id": page_id}}}}})["data"]
    print("Made a new version of the page.", flush=True)
    return made


def localization(client, version_id, page):
    found = client.call("GET", f"/appCustomProductPageVersions/{version_id}/appCustomProductPageLocalizations")["data"]
    for item in found:
        if item["attributes"]["locale"] == page["locale"]:
            if item["attributes"].get("promotionalText") != page.get("promotionalText"):
                client.call("PATCH", f"/appCustomProductPageLocalizations/{item['id']}", {"data": {
                    "type": "appCustomProductPageLocalizations", "id": item["id"],
                    "attributes": {"promotionalText": page.get("promotionalText")}}})
                print("Promotional text set.", flush=True)
            return item
    made = client.call("POST", "/appCustomProductPageLocalizations", {"data": {
        "type": "appCustomProductPageLocalizations",
        "attributes": {"locale": page["locale"], "promotionalText": page.get("promotionalText")},
        "relationships": {"appCustomProductPageVersion": {"data": {"type": "appCustomProductPageVersions", "id": version_id}}}}})["data"]
    print(f"Made the {page['locale']} localization.", flush=True)
    return made


def link_keywords(client, localization_id, wanted):
    path = f"/appCustomProductPageLocalizations/{localization_id}/relationships/searchKeywords"
    linked = {k["id"] for k in client.call("GET", path, query={"limit": "200"})["data"]}
    add, drop = sorted(set(wanted) - linked), sorted(linked - set(wanted))
    if add:
        client.call("POST", path, {"data": [{"type": "appKeywords", "id": k} for k in add]})
    if drop:
        client.call("DELETE", path, {"data": [{"type": "appKeywords", "id": k} for k in drop]})
    print(f"Keywords: {', '.join(wanted) or 'none'}" + (f" (unlinked {', '.join(drop)})" if drop else "") + ".", flush=True)


def submit(client, app_id, version_id):
    open_drafts = client.call("GET", "/reviewSubmissions", query={
        "filter[app]": app_id, "filter[platform]": "IOS", "filter[state]": "READY_FOR_REVIEW", "limit": "10"})["data"]
    if open_drafts:
        raise APIError("a draft review submission is already open for the app; submit or cancel it in "
                       "App Store Connect first (submitting it here would send whatever else it holds)")
    submission = client.call("POST", "/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    try:
        client.call("POST", "/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
                              "appCustomProductPageVersion": {"data": {"type": "appCustomProductPageVersions", "id": version_id}}}}})
        client.call("PATCH", f"/reviewSubmissions/{submission['id']}", {"data": {
            "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})
    except APIError:
        # A draft left open would stop every later run at the check above.
        try:
            client.call("PATCH", f"/reviewSubmissions/{submission['id']}", {"data": {
                "type": "reviewSubmissions", "id": submission["id"], "attributes": {"canceled": True}}})
        except APIError as error:
            print(f"Cancelling the draft submission failed too: {error}", flush=True)
        raise
    print("Submitted for review.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("page", type=Path)
    parser.add_argument("--apply", action="store_true", help="make or update the page (otherwise only list)")
    parser.add_argument("--submit", action="store_true", help="with --apply, send the page's version for review")
    args = parser.parse_args()
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"):
        if not os.environ.get(name):
            sys.exit(f"{name} is not set")
    page, found, wrong = read_page(args.page)
    client = Client(private_key())
    app = find_app(client)
    locale = (page or {}).get("locale", "en-US")
    available = sorted(k["id"] for k in client.call("GET", f"/apps/{app['id']}/searchKeywords", query={
        "filter[platform]": "IOS", "filter[locale]": locale, "limit": "200"})["data"])
    wanted = (page or {}).get("keywords") or []
    wrong += [f"keyword {k!r} is not one of the app's {locale} keywords" for k in wanted if k not in available]
    name = (page or {}).get("name")
    existing = find_page(client, app["id"], name) if name else None
    lines = [f"Page {name or '?'!r}: "
             + (f"exists ({', '.join(v['attributes'].get('state', '?') for v in versions(client, existing['id']))}), "
                f"visible {existing['attributes'].get('visible')}" if existing else "not made yet") + ".",
             f"App keywords ({locale}): {', '.join(available) or 'none'}.",
             f"Slides: {', '.join(f'{k} ({len(v)})' for k, v in found.items()) or 'none'}."]
    lines += [f"Problem: {p}" for p in wrong]
    for line in lines:
        print(line)
    if not args.apply:
        summarize(["### Custom product page (dry run, nothing changed)"] + [f"- {line}" for line in lines])
        if wrong:
            sys.exit(f"{len(wrong)} problems")
        return
    if wrong:
        sys.exit(f"{len(wrong)} problems, nothing changed")
    made = existing or make_page(client, app["id"], page)
    version = editable(client, made["id"])
    if (page.get("deepLink") or None) != (version["attributes"].get("deepLink") or None):
        client.call("PATCH", f"/appCustomProductPageVersions/{version['id']}", {"data": {
            "type": "appCustomProductPageVersions", "id": version["id"], "attributes": {"deepLink": page.get("deepLink")}}})
    target = localization(client, version["id"], page)
    sets = {s["attributes"]["screenshotDisplayType"]: s for s in client.call(
        "GET", f"/appCustomProductPageLocalizations/{target['id']}/appScreenshotSets")["data"]}
    ids = {kind: replace_set(client, target["id"], sets, kind, files, parent="appCustomProductPageLocalization")
           for kind, files in found.items()}
    wait_until_processed(client, ids)
    link_keywords(client, target["id"], wanted)
    if args.submit:
        submit(client, app["id"], version["id"])
    url = client.call("GET", f"/appCustomProductPages/{made['id']}")["data"]["attributes"].get("url")
    done = [f"Page {page['name']!r}: {sum(len(v) for v in found.values())} screenshots in {len(found)} sets, "
            f"keywords {', '.join(wanted) or 'none'}, " + ("submitted for review" if args.submit else "not submitted") + ".",
            f"URL: {url or 'given once approved'}."]
    print("\n".join(done))
    summarize(["### Custom product page"] + [f"- {line}" for line in done])


if __name__ == "__main__":
    try:
        main()
    except APIError as error:
        sys.exit(f"Custom product page: {error}")
