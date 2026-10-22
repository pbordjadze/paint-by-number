#!/usr/bin/env python3
"""Fills in the App Store listing of the version being prepared, through the App Store Connect API.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8=… python3 ci/store_listing.py ci/store-listing.json [--apply]

LISTING (ci/store-listing.json) says what the listing holds, one key per place App Store Connect
keeps it; a key or field left out is left as it is, and a list of strings is its lines joined:

    app                  the app's own fields (contentRightsDeclaration)
    appInfo              primaryCategory, secondaryCategory: App Store Connect's category ids
    appInfoLocalization  name, subtitle, privacyPolicyUrl, in LOCALE
    ageRating            the age rating questionnaire, as ageRatingDeclarations' attributes
    version              copyright, releaseType
    versionLocalization  description, keywords, promotionalText, supportUrl, marketingUrl, in LOCALE
    review               App Review Information: notes, demoAccountRequired
    accessibility        {IPHONE: {…}, IPAD: {…}}: the Accessibility Nutrition Labels, as
                         accessibilityDeclarations' supports* attributes, every one given

It finds the app by its bundle id, its iOS version in an editable state and the app info being
prepared with it, and checks the lengths App Store Connect allows before anything changes. Without
--apply it lists each field that differs from what App Store Connect holds, changing nothing; with
--apply it sends only those. An accessibility answer is sent as a new draft declaration, which is
then published: that is what the product page shows. It also says what it leaves to App Store
Connect: App Privacy (not in the API), availability and price, and App Review's contact, whose
name, phone and email are not this public repository's to hold.

Run by `.github/workflows/store-listing.yml`. The logs are public: it prints the listing's own
fields (what the store shows, and the notes for App Review), never a secret or the contact.
Needs `cryptography` (ES256 tokens, through ci/testflight_testers.py's client).
"""

import argparse
import json
import os
import sys
from pathlib import Path

from store_screenshots_upload import editable_version, localization
from testflight_testers import BUNDLE_ID, APIError, Client, private_key, summarize

# The app info states whose fields can still be changed.
EDITABLE_INFO = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED")
# App Store Connect's limits, in characters.
LIMITS = {"name": 30, "subtitle": 30, "promotionalText": 170, "keywords": 100, "description": 4000,
          "notes": 4000, "copyright": 200}
ACCESSIBILITY = ("supportsVoiceover", "supportsVoiceControl", "supportsLargerText", "supportsDarkInterface",
                 "supportsDifferentiateWithoutColorAlone", "supportsSufficientContrast",
                 "supportsReducedMotion", "supportsCaptions", "supportsAudioDescriptions")
SECTIONS = ("app", "appInfo", "appInfoLocalization", "ageRating", "version", "versionLocalization", "review",
            "accessibility")


def read_listing(path):
    listing = json.loads(path.read_text())
    unknown = set(listing) - set(SECTIONS)
    if unknown:
        raise APIError(f"{path.name}: unknown sections {', '.join(sorted(unknown))}")
    return {section: {field: "\n".join(value) if isinstance(value, list) else value
                      for field, value in fields.items()} if section != "accessibility" else fields
            for section, fields in listing.items()}


def problems(listing):
    """Everything App Store Connect would refuse, found before anything changes."""
    found = []
    for section, fields in listing.items():
        if section == "accessibility":
            for family, answers in fields.items():
                if set(answers) != set(ACCESSIBILITY) or not all(isinstance(v, bool) for v in answers.values()):
                    found.append(f"accessibility {family}: give each of {', '.join(ACCESSIBILITY)} as true or false")
            continue
        for field, value in fields.items():
            limit = LIMITS.get(field)
            if limit and isinstance(value, str) and len(value) > limit:
                found.append(f"{section}.{field} is {len(value)} characters, over {limit}")
    return found


def shown(value):
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= 80 else f"{len(value) if isinstance(value, str) else len(text)} characters, {text[:60]}…"


class Listing:
    """Compares what App Store Connect holds with the listing, and sends what differs."""

    def __init__(self, client, apply):
        self.client, self.apply, self.changes = client, apply, []

    def compare(self, label, current, wanted):
        """The fields of `wanted` that differ from `current`, each noted."""
        differ = {k: v for k, v in wanted.items() if current.get(k) != v}
        for field, value in differ.items():
            self.changes.append(f"{label}.{field}: {shown(current.get(field))} → {shown(value)}")
        return differ

    def patch(self, label, kind, item, wanted):
        differ = self.compare(label, item["attributes"], wanted)
        if differ and self.apply:
            self.client.call("PATCH", f"/{kind}/{item['id']}",
                             {"data": {"type": kind, "id": item["id"], "attributes": differ}})

    def categories(self, info, wanted):
        current = {}
        for relation in ("primaryCategory", "secondaryCategory"):
            data = self.client.call("GET", f"/appInfos/{info['id']}/relationships/{relation}").get("data")
            current[relation] = data["id"] if data else None
        differ = self.compare("appInfo", current, wanted)
        if differ and self.apply:
            self.client.call("PATCH", f"/appInfos/{info['id']}", {"data": {
                "type": "appInfos", "id": info["id"],
                "relationships": {k: {"data": {"type": "appCategories", "id": v} if v else None}
                                  for k, v in differ.items()}}})

    def review(self, version, wanted):
        try:
            detail = self.client.call("GET", f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
        except APIError as error:
            if ": 404 " not in str(error):
                raise
            detail = None  # none written yet
        if detail:
            return self.patch("review", "appStoreReviewDetails", detail, wanted)
        differ = self.compare("review", {}, wanted)
        if differ and self.apply:
            self.client.call("POST", "/appStoreReviewDetails", {"data": {
                "type": "appStoreReviewDetails", "attributes": differ,
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})

    def accessibility(self, app_id, family, wanted):
        found = self.client.call("GET", f"/apps/{app_id}/accessibilityDeclarations", query={
            "filter[deviceFamily]": family, "filter[state]": "DRAFT,PUBLISHED", "limit": "10"})["data"]
        by_state = {d["attributes"]["state"]: d for d in found}
        current = by_state.get("PUBLISHED", {}).get("attributes", {})
        if not self.compare(f"accessibility {family}", current, wanted) or not self.apply:
            return
        draft = by_state.get("DRAFT")
        if draft:
            self.client.call("PATCH", f"/accessibilityDeclarations/{draft['id']}", {"data": {
                "type": "accessibilityDeclarations", "id": draft["id"], "attributes": wanted}})
        else:
            draft = self.client.call("POST", "/accessibilityDeclarations", {"data": {
                "type": "accessibilityDeclarations", "attributes": {"deviceFamily": family, **wanted},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        self.client.call("PATCH", f"/accessibilityDeclarations/{draft['id']}", {"data": {
            "type": "accessibilityDeclarations", "id": draft["id"], "attributes": {"publish": True}}})


def editable_info(client, app_id):
    infos = client.call("GET", f"/apps/{app_id}/appInfos")["data"]
    for info in infos:
        if info["attributes"].get("state") in EDITABLE_INFO:
            return info
    raise APIError("no app info is in a state whose fields can be changed "
                   f"({', '.join(i['attributes'].get('state') or '?' for i in infos)})")


def info_localization(client, info_id, locale):
    found = client.call("GET", f"/appInfos/{info_id}/appInfoLocalizations")["data"]
    for item in found:
        if item["attributes"]["locale"] == locale:
            return item
    raise APIError(f"the app info has no {locale} localization")


def left_to_connect(client, app_id):
    """What this leaves to App Store Connect, and whether it has been done there."""
    def is_set(path):
        try:
            return bool(client.call("GET", path).get("data"))
        except APIError:
            return False
    return [f"Availability: {'set' if is_set(f'/apps/{app_id}/appAvailabilityV2') else 'not set yet'} (App Store Connect › Pricing and Availability)",
            f"Price: {'set' if is_set(f'/apps/{app_id}/appPriceSchedule') else 'not set yet'} (App Store Connect › Pricing and Availability)",
            "App Privacy: in App Store Connect only (not in the API)",
            "App Review contact (name, phone, email): in App Store Connect › App Review Information"]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("listing", type=Path)
    parser.add_argument("--apply", action="store_true", help="send what differs (otherwise only list it)")
    parser.add_argument("--locale", default="en-US")
    args = parser.parse_args()
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"):
        if not os.environ.get(name):
            sys.exit(f"{name} is not set")
    listing = read_listing(args.listing)
    wrong = problems(listing)
    for problem in wrong:
        print(f"Problem: {problem}")
    if wrong:
        sys.exit(f"{len(wrong)} problems with {args.listing.name}, nothing changed")
    client = Client(private_key())
    apps = client.call("GET", "/apps", query={"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"No App Store Connect app has the bundle id {BUNDLE_ID}")
    app = apps[0]
    version = editable_version(client, app["id"])
    info = editable_info(client, app["id"])
    name = version["attributes"].get("versionString")
    work = Listing(client, args.apply)
    if "app" in listing:
        work.patch("app", "apps", app, listing["app"])
    if "appInfo" in listing:
        work.categories(info, listing["appInfo"])
    if "appInfoLocalization" in listing:
        work.patch("appInfoLocalization", "appInfoLocalizations",
                   info_localization(client, info["id"], args.locale), listing["appInfoLocalization"])
    if "ageRating" in listing:
        declaration = client.call("GET", f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
        work.patch("ageRating", "ageRatingDeclarations", declaration, listing["ageRating"])
    if "version" in listing:
        work.patch("version", "appStoreVersions", version, listing["version"])
    if "versionLocalization" in listing:
        work.patch("versionLocalization", "appStoreVersionLocalizations",
                   localization(client, version["id"], args.locale), listing["versionLocalization"])
    if "review" in listing:
        work.review(version, listing["review"])
    for family, answers in listing.get("accessibility", {}).items():
        work.accessibility(app["id"], family, answers)
    left = left_to_connect(client, app["id"])
    verb = "Changed" if args.apply else "Would change (dry run, nothing changed)"
    print(f"Version {name}, {args.locale}. {verb}: {len(work.changes) or 'nothing'}.")
    for change in work.changes:
        print(f"  {change}")
    for line in left:
        print(f"Left to App Store Connect: {line}")
    summarize([f"### Listing of version {name}, {args.locale}: {verb.lower()}"]
              + [f"- {c}" for c in work.changes] + ["", "Left to App Store Connect:"] + [f"- {l}" for l in left])


if __name__ == "__main__":
    try:
        main()
    except APIError as error:
        sys.exit(f"Store listing: {error}")
