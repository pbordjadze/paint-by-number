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
    availability         {"territories": "all", "availableInNewTerritories": true}: set only
                         while the app has none (later changes are App Store Connect's)
    otherLocales         {"en-GB": {"keywords": …}, …}: other English storefronts' listings,
                         LOCALE's app info and version text respelled (colour), with their own
                         keywords, promotional text or subtitle; made when missing
    inAppPurchases       {product id: {"reviewNote": …}}: written only where App Store Connect
                         has none
    nomination           a featuring nomination for Apple's editors (Nomination's attributes):
                         kept as a draft until "submit" is true, then left as it is

It finds the app by its bundle id, its iOS version in an editable state and the app info being
prepared with it, and checks the fields and their lengths before anything changes. Without
--apply it lists each field that differs from what App Store Connect holds, changing nothing; with
--apply it sends only those. An accessibility answer is sent as a new draft declaration, which is
then published: that is what the product page shows. It also says what it leaves to App Store
Connect: App Privacy (not in the API), price, and App Review's contact, whose name, phone and
email are not this public repository's to hold. Each change is printed as it is found (as it is
sent, with --apply), so a run that fails part way has said what it sent; the field names and
values are checked against the API's before anything is.

Run by `.github/workflows/store-listing.yml`. The logs are public: it prints the listing's own
fields (what the store shows, and the notes for App Review), never a secret or the contact.
Needs `cryptography` (ES256 tokens, through ci/testflight_testers.py's client).
"""

import argparse
import datetime
import json
import os
import re
import sys
from pathlib import Path

from store_screenshots_upload import editable_version, localization
from testflight_testers import APIError, Client, find_app, private_key, summarize

# The app info states whose fields can still be changed.
EDITABLE_INFO = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED")
# App Store Connect's limits, in characters.
LIMITS = {"name": 30, "subtitle": 30, "promotionalText": 170, "keywords": 100, "description": 4000,
          "notes": 4000, "copyright": 200}
ACCESSIBILITY = ("supportsVoiceover", "supportsVoiceControl", "supportsLargerText", "supportsDarkInterface",
                 "supportsDifferentiateWithoutColorAlone", "supportsSufficientContrast",
                 "supportsReducedMotion", "supportsCaptions", "supportsAudioDescriptions")
FAMILIES = ("IPHONE", "IPAD", "APPLE_TV", "APPLE_WATCH", "MAC", "VISION")
LEVEL = ("NONE", "INFREQUENT_OR_MILD", "FREQUENT_OR_INTENSE", "INFREQUENT", "FREQUENT")
# The fields each section may set and what each takes (str, bool, or its values), from the API's
# update requests (4.5). App Review's contact is left out on purpose.
FIELDS = {
    "app": {"contentRightsDeclaration": ("DOES_NOT_USE_THIRD_PARTY_CONTENT", "USES_THIRD_PARTY_CONTENT"),
            "accessibilityUrl": str},
    "appInfo": {"primaryCategory": str, "secondaryCategory": str},
    "appInfoLocalization": {"name": str, "subtitle": str, "privacyPolicyUrl": str, "privacyChoicesUrl": str},
    "ageRating": {**{k: LEVEL for k in (
        "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
        "horrorOrFearThemes", "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
        "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy", "violenceRealistic",
        "violenceRealisticProlongedGraphicOrSadistic")},
                  **{k: bool for k in (
        "advertising", "ageAssurance", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat",
        "parentalControls", "socialMedia", "socialMediaAgeRestricted", "unrestrictedWebAccess",
        "userGeneratedContent")}},
    "version": {"copyright": str, "releaseType": ("MANUAL", "AFTER_APPROVAL", "SCHEDULED")},
    "versionLocalization": {"description": str, "keywords": str, "marketingUrl": str, "promotionalText": str,
                            "supportUrl": str},
    "review": {"notes": str, "demoAccountRequired": bool},
}
# The other English storefronts' locales, and what each may say in its own words; the rest is
# LOCALE's, respelled.
OTHER_LOCALES = ("en-GB", "en-AU", "en-CA")
LOCALE_FIELDS = ("keywords", "promotionalText", "subtitle")
# The prose respelled for them (never a URL).
PROSE = ("name", "subtitle", "description", "keywords", "promotionalText")
NOMINATION = {"name": str, "type": ("APP_LAUNCH", "APP_ENHANCEMENTS", "NEW_CONTENT"), "description": str,
              "publishStartDate": str, "deviceFamilies": list, "locales": list, "supplementalMaterialsUris": list,
              "hasInAppEvents": bool, "launchInSelectMarketsFirst": bool, "preOrderEnabled": bool, "notes": str,
              "submit": bool}
SECTIONS = (*FIELDS, "accessibility", "availability", "otherLocales", "inAppPurchases", "nomination")


def read_listing(path):
    listing = json.loads(path.read_text())
    unknown = set(listing) - set(SECTIONS)
    if unknown:
        raise APIError(f"{path.name}: unknown sections {', '.join(sorted(unknown))}")
    def joined(section, field, value):
        text = (FIELDS.get(section, {}).get(field) is str or (section == "nomination" and NOMINATION.get(field) is str)
                or field in LOCALE_FIELDS or field == "reviewNote")
        return "\n".join(value) if text and isinstance(value, list) else value
    def each(section, fields):
        if section in FIELDS or section == "nomination":
            return {field: joined(section, field, value) for field, value in fields.items()}
        if section in ("otherLocales", "inAppPurchases"):
            return {key: {field: joined(section, field, value) for field, value in own.items()} for key, own in fields.items()}
        return fields
    return {section: each(section, fields) for section, fields in listing.items()}


def problems(listing):
    """Everything App Store Connect would refuse, found before anything changes."""
    found = []
    for section, fields in listing.items():
        if section == "otherLocales":
            for locale in fields:
                if locale not in OTHER_LOCALES:
                    found.append(f"otherLocales: {locale} is not one of {', '.join(OTHER_LOCALES)}")
                for field, value in locale_listing(listing, locale).items():
                    if value is not None and not isinstance(value, str):
                        found.append(f"otherLocales {locale}.{field} should be text")
                    elif value and field in LIMITS and len(value) > LIMITS[field]:
                        found.append(f"otherLocales {locale}.{field} is {len(value)} characters, over {LIMITS[field]}")
                found += [f"otherLocales {locale}.{k} is not one of {', '.join(LOCALE_FIELDS)}"
                          for k in fields[locale] if k not in LOCALE_FIELDS]
            continue
        if section == "inAppPurchases":
            found += [f"inAppPurchases {product}: only reviewNote is set here, as text" for product, own in fields.items()
                      if set(own) != {"reviewNote"} or not isinstance(own["reviewNote"], str)]
            continue
        if section == "nomination":
            for field, value in fields.items():
                kind = NOMINATION.get(field)
                if kind is None or (isinstance(kind, tuple) and value not in kind) or (isinstance(kind, type) and not isinstance(value, kind)):
                    found.append(f"nomination.{field}: not a field, or not a value, this script sends")
            found += [f"nomination.{field} is required" for field in ("name", "type", "description", "publishStartDate")
                      if not fields.get(field)]
            try:
                datetime.datetime.fromisoformat(str(fields.get("publishStartDate")))
            except ValueError:
                found.append("nomination.publishStartDate should be a time, like 2026-10-27T00:00:00Z")
            found += [f"nomination.deviceFamilies: {f} is not one of {', '.join(FAMILIES)}"
                      for f in fields.get("deviceFamilies", []) if f not in FAMILIES]
            continue
        if section == "availability":
            if fields != {"territories": "all", "availableInNewTerritories": True}:
                found.append('availability: the one choice this script makes is {"territories": "all", '
                             '"availableInNewTerritories": true}')
            continue
        if section == "accessibility":
            for family, answers in fields.items():
                if family not in FAMILIES:
                    found.append(f"accessibility: {family} is not a device family ({', '.join(FAMILIES)})")
                if set(answers) != set(ACCESSIBILITY) or not all(isinstance(v, bool) for v in answers.values()):
                    found.append(f"accessibility {family}: give each of {', '.join(ACCESSIBILITY)} as true or false")
            continue
        for field, value in fields.items():
            kind = FIELDS[section].get(field)
            limit = LIMITS.get(field)
            if kind is None:
                found.append(f"{section}.{field} is not a field this script sets ({', '.join(FIELDS[section])})")
            elif isinstance(kind, tuple) and value not in kind:
                found.append(f"{section}.{field} is {value!r}, not one of {', '.join(kind)}")
            elif value is None and kind is str:
                pass  # clears the field (a secondary category, a URL)
            elif isinstance(kind, type) and not isinstance(value, kind):
                found.append(f"{section}.{field} should be a {kind.__name__}")
            elif limit and isinstance(value, str) and len(value) > limit:
                found.append(f"{section}.{field} is {len(value)} characters, over {limit}")
    return found


def shown(value, private=False):
    """The value for the public log; a private one (what App Store Connect holds for App Review,
    which may be anything typed there) only by its length."""
    if private and value is not None:
        return f"{len(str(value))} characters" if isinstance(value, str) else "set"
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= 80 else f"{len(value) if isinstance(value, str) else len(text)} characters, {text[:60]}…"


class Listing:
    """Compares what App Store Connect holds with the listing, and sends what differs."""

    def __init__(self, client, apply):
        self.client, self.apply, self.changes = client, apply, []

    def compare(self, label, current, wanted, private=False):
        """The fields of `wanted` that differ from `current`, each noted and printed as found, so a
        run that fails part way has said what it sent before."""
        differ = {k: v for k, v in wanted.items() if current.get(k) != v}
        for field, value in differ.items():
            change = f"{label}.{field}: {shown(current.get(field), private)} → {shown(value)}"
            self.changes.append(change)
            print(f"  {'Sending' if self.apply else 'Differs'}: {change}", flush=True)
        return differ

    def patch(self, label, kind, item, wanted, private=False):
        differ = self.compare(label, item["attributes"], wanted, private)
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
            return self.patch("review", "appStoreReviewDetails", detail, wanted, private=True)
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


def availability(client, work, app_id, wanted):
    """Every territory, and new ones as they come, when the app has no availability yet; one it
    has is App Store Connect's to change (its territories' release dates and pre-orders)."""
    try:
        current = client.call("GET", f"/apps/{app_id}/appAvailabilityV2").get("data")
    except APIError as error:
        if ": 404 " not in str(error):
            raise
        current = None
    if current:
        return
    territories = client.call("GET", "/territories", query={"limit": "200"})["data"]
    work.compare("availability", {}, {"territories": f"all {len(territories)}",
                                      "availableInNewTerritories": wanted["availableInNewTerritories"]})
    if not work.apply:
        return
    ids = [f"${{{t['id']}}}" for t in territories]  # inline creates take local ids
    client.call("POST", "/v2/appAvailabilities", {
        "data": {"type": "appAvailabilities",
                 "attributes": {"availableInNewTerritories": wanted["availableInNewTerritories"]},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                                   "territoryAvailabilities": {"data": [
                                       {"type": "territoryAvailabilities", "id": i} for i in ids]}}},
        "included": [{"type": "territoryAvailabilities", "id": i, "attributes": {"available": True},
                      "relationships": {"territory": {"data": {"type": "territories", "id": t["id"]}}}}
                     for i, t in zip(ids, territories)]})


def respelled(text):
    """American English in British, Australian and Canadian spelling, for the words the listing
    uses (color, coloring, colors and their capitals)."""
    return re.sub(r"\b([Cc])olor", r"\1olour", text)


def locale_listing(listing, locale):
    """One other locale's fields, app info's and version's together: LOCALE's, its prose
    respelled, then its own words."""
    base = {**listing.get("appInfoLocalization", {}), **listing.get("versionLocalization", {})}
    merged = {k: respelled(v) if k in PROSE and isinstance(v, str) else v for k, v in base.items()}
    return {**merged, **listing.get("otherLocales", {}).get(locale, {})}


def other_locales(client, work, version, info, listing):
    """Each other English locale's listing: LOCALE's own, respelled, with its own keywords; created
    when the version or the app info has none for that locale yet."""
    version_found = {i["attributes"]["locale"]: i for i in
                     client.call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]}
    info_found = {i["attributes"]["locale"]: i for i in
                  client.call("GET", f"/appInfos/{info['id']}/appInfoLocalizations")["data"]}
    for locale, own in listing["otherLocales"].items():
        fields = locale_listing(listing, locale)
        wanted_info = {k: v for k, v in fields.items() if k in listing.get("appInfoLocalization", {}) or k in own
                       and k in FIELDS["appInfoLocalization"]}
        wanted_version = {k: v for k, v in fields.items() if k in listing.get("versionLocalization", {}) or k in own
                          and k in FIELDS["versionLocalization"]}
        for kind, parent, found, wanted, label in (
                ("appInfoLocalizations", ("appInfo", "appInfos", info["id"]), info_found, wanted_info, "appInfoLocalization"),
                ("appStoreVersionLocalizations", ("appStoreVersion", "appStoreVersions", version["id"]), version_found,
                 wanted_version, "versionLocalization")):
            if locale in found:
                work.patch(f"{label} {locale}", kind, found[locale], wanted)
                continue
            work.compare(f"{label} {locale} (new)", {}, wanted)
            if work.apply:
                relation, parent_type, parent_id = parent
                client.call("POST", f"/{kind}", {"data": {
                    "type": kind, "attributes": {"locale": locale, **wanted},
                    "relationships": {relation: {"data": {"type": parent_type, "id": parent_id}}}}})


def in_app_purchases(client, work, app_id, wanted):
    """Each purchase's App Review note, written only where it is empty: one written in App Store
    Connect stays. Also reports each purchase's state."""
    for product, own in wanted.items():
        found = client.call("GET", f"/apps/{app_id}/inAppPurchasesV2", query={"filter[productId]": product})["data"]
        purchase = next((p for p in found if p["attributes"].get("productId") == product), None)
        if purchase is None:
            print(f"In-app purchase {product}: not in App Store Connect yet, left for later.")
            continue
        attributes = purchase["attributes"]
        print(f"In-app purchase {product}: {attributes.get('state')}.")
        if attributes.get("reviewNote"):
            if attributes["reviewNote"] != own["reviewNote"]:
                print(f"In-app purchase {product}: its App Review note is already written, left as is.")
            continue
        differ = work.compare(f"inAppPurchase {product}", attributes, own)
        if differ and work.apply:
            client.call("PATCH", f"/v2/inAppPurchases/{purchase['id']}", {"data": {
                "type": "inAppPurchases", "id": purchase["id"], "attributes": differ}})


def nomination(client, work, app_id, wanted):
    """The featuring nomination for Apple's editors, kept as a draft in App Store Connect (matched
    by name) until `submit` is true; a submitted one is left as it is."""
    wanted = dict(wanted)
    submit = wanted.pop("submit", False)
    found = [n for state in ("DRAFT", "SUBMITTED")  # the API takes one state a call
             for n in client.call("GET", "/nominations", query={
                 "filter[relatedApps]": app_id, "filter[state]": state, "limit": "50"})["data"]]
    existing = next((n for n in found if n["attributes"].get("name") == wanted["name"]), None)
    if existing and existing["attributes"].get("state") != "DRAFT":
        print(f"Nomination {wanted['name']!r}: {existing['attributes'].get('state')}, left as is.")
        return
    current = dict(existing["attributes"]) if existing else {}
    # The same time however App Store Connect writes it, and the same lists in any order.
    try:
        if datetime.datetime.fromisoformat(current.get("publishStartDate") or "") == \
                datetime.datetime.fromisoformat(wanted["publishStartDate"]):
            current["publishStartDate"] = wanted["publishStartDate"]
    except ValueError:
        pass
    for field in ("deviceFamilies", "locales", "supplementalMaterialsUris"):
        if sorted(current.get(field) or []) == sorted(wanted.get(field) or []):
            current[field] = wanted.get(field)
    # Whatever was typed into the draft in App Store Connect shows in the public log only by length.
    differ = work.compare("nomination" + ("" if existing else " (new draft)"), current, wanted, private=True)
    if submit:
        work.compare("nomination", {"submitted": False}, {"submitted": True})
    if not work.apply or not (differ or submit):
        return
    if existing:
        client.call("PATCH", f"/nominations/{existing['id']}", {"data": {
            "type": "nominations", "id": existing["id"], "attributes": {**differ, "submitted": submit}}})
    else:
        client.call("POST", "/nominations", {"data": {
            "type": "nominations", "attributes": {**wanted, "submitted": submit},
            "relationships": {"relatedApps": {"data": [{"type": "apps", "id": app_id}]}}}})


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
    def state(path):
        try:
            return "set" if client.call("GET", path).get("data") else "not set yet"
        except APIError as error:
            return "not set yet" if ": 404 " in str(error) else f"unknown ({error})"
    return [f"Price: {state(f'/apps/{app_id}/appPriceSchedule')} (App Store Connect › Pricing and Availability)",
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
    app = find_app(client)
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
    if "availability" in listing:
        availability(client, work, app["id"], listing["availability"])
    if "otherLocales" in listing:
        other_locales(client, work, version, info, listing)
    if "inAppPurchases" in listing:
        in_app_purchases(client, work, app["id"], listing["inAppPurchases"])
    if "nomination" in listing:
        nomination(client, work, app["id"], listing["nomination"])
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
