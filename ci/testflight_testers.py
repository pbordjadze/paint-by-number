#!/usr/bin/env python3
"""Puts a TestFlight build in front of external testers, through the App Store Connect API.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8=… [BUILD=6.1] python3 ci/testflight_testers.py

Run by `.github/workflows/testflight-testers.yml`. It finds the app by its bundle id and the build
(BUILD, the CFBundleVersion, or the newest processed one), makes the external group
"Friends & Family" the first time (its public link on, limited to `LINK_LIMIT` testers) or turns
an existing one's link on, adds the build to it with its What to Test, and submits the build for
Beta App Review. Every step is idempotent: a second run changes nothing it already did.

The group's public link is never printed in the clear (the repository's logs are public): copy
it from App Store Connect › TestFlight › Friends & Family once Apple approves the build, or put
an RSA public key at LINK_RECIPIENT_FILE and the link is printed encrypted to it (RSA-OAEP,
SHA-256, base64), for whoever holds the private key. The Test Information
(description, feedback email, privacy policy, review contact) is filled in App Store Connect.
Needs `cryptography` (ES256 tokens).
"""

import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.pbordjadze.paintbynumber"
GROUP = "Friends & Family"
LINK_LIMIT = 100
WHAT_TO_TEST = (
    "Thanks for trying Paint by Moonlight! Make a painting from one of your photos (New Painting → "
    "Choose Photo) or a sample, then paint it. Tell us anything that felt confusing, slow or broken, "
    "and what you loved — the feedback button in a painting's top bar lets you mark the spot."
)


class APIError(Exception):
    pass


def private_key():
    """The .p8 key, rebuilt from its base64 alone (a key pasted on a phone loses line breaks)."""
    body = re.sub(r"-----[A-Z ]+-----|\s", "", os.environ["ASC_KEY_P8"])
    pem = "-----BEGIN PRIVATE KEY-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64))
    return serialization.load_pem_private_key((pem + "\n-----END PRIVATE KEY-----\n").encode(), None)


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(key):
    """An ES256 JWT for the App Store Connect API, good for ten minutes."""
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    signing = b64(json.dumps(header).encode()) + "." + b64(json.dumps(payload).encode())
    r, s = decode_dss_signature(key.sign(signing.encode(), ec.ECDSA(hashes.SHA256())))
    return signing + "." + b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))


class Client:
    def __init__(self, key):
        self.key = key

    def call(self, method, path, body=None, query=None):
        url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", "Bearer " + token(self.key))
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            # Apple's errors say what is wrong and carry no secrets.
            try:
                errors = json.loads(error.read()).get("errors", [])
                detail = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in errors)
            except ValueError:
                detail = error.reason
            raise APIError(f"{method} {path}: {error.code} {detail}") from None


def find_build(client, app_id, wanted):
    query = {"filter[app]": app_id, "sort": "-uploadedDate", "limit": "20",
             "fields[builds]": "version,processingState,uploadedDate,expired"}
    if wanted:
        query["filter[version]"] = wanted
    builds = client.call("GET", "/builds", query=query)["data"]
    usable = [b for b in builds if b["attributes"]["processingState"] == "VALID" and not b["attributes"]["expired"]]
    if not usable:
        states = ", ".join(f"{b['attributes']['version']}: {b['attributes']['processingState']}" for b in builds)
        raise APIError(f"no processed build{' ' + wanted if wanted else ''} ({states or 'none uploaded'})")
    return usable[0]


def ensure_group(client, app_id, build_id):
    groups = client.call("GET", f"/apps/{app_id}/betaGroups", query={"limit": "200"})["data"]
    link = {"publicLinkEnabled": True, "publicLinkLimitEnabled": True, "publicLinkLimit": LINK_LIMIT}
    group = next((g for g in groups if g["attributes"]["name"] == GROUP and not g["attributes"].get("isInternalGroup")), None)
    if group is None:
        body = {"data": {"type": "betaGroups", "attributes": {"name": GROUP, "feedbackEnabled": True, **link},
                         "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}
        group = client.call("POST", "/betaGroups", body)["data"]
        print(f"Made the external group {GROUP!r}, its public link on (at most {LINK_LIMIT} testers).")
    elif not group["attributes"].get("publicLinkEnabled"):
        client.call("PATCH", f"/betaGroups/{group['id']}", {"data": {"type": "betaGroups", "id": group["id"], "attributes": link}})
        print(f"Turned on {GROUP!r}'s public link (at most {LINK_LIMIT} testers).")
    else:
        print(f"{GROUP!r} exists with its public link on.")
    client.call("POST", f"/betaGroups/{group['id']}/relationships/builds",
                {"data": [{"type": "builds", "id": build_id}]})
    return group


def ensure_what_to_test(client, build_id):
    existing = client.call("GET", f"/builds/{build_id}/betaBuildLocalizations")["data"]
    english = next((l for l in existing if l["attributes"]["locale"] == "en-US"), None)
    if english is None:
        client.call("POST", "/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": WHAT_TO_TEST},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    elif english["attributes"].get("whatsNew") != WHAT_TO_TEST:
        client.call("PATCH", f"/betaBuildLocalizations/{english['id']}", {"data": {
            "type": "betaBuildLocalizations", "id": english["id"], "attributes": {"whatsNew": WHAT_TO_TEST}}})


def ensure_submitted(client, build_id):
    submission = client.call("GET", f"/builds/{build_id}/betaAppReviewSubmission").get("data")
    if submission:
        return submission["attributes"].get("betaReviewState")
    body = {"data": {"type": "betaAppReviewSubmissions",
                     "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}}
    return client.call("POST", "/betaAppReviewSubmissions", body)["data"]["attributes"].get("betaReviewState")


def main():
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"):
        if not os.environ.get(name):
            sys.exit(f"{name} is not set")
    client = Client(private_key())
    apps = client.call("GET", "/apps", query={"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"No App Store Connect app has the bundle id {BUNDLE_ID}")
    app_id = apps[0]["id"]
    build = find_build(client, app_id, os.environ.get("BUILD", "").strip())
    version = build["attributes"]["version"]
    print(f"Build {version} ({build['attributes']['processingState']}).")
    group = ensure_group(client, app_id, build["id"])
    print(f"Build {version} is in {GROUP!r}.")
    ensure_what_to_test(client, build["id"])
    print("What to Test is set.")
    state = ensure_submitted(client, build["id"])
    print(f"Beta App Review: {state}.")
    print(f"Once approved, copy the public link from App Store Connect › TestFlight › {GROUP}.")
    recipient = os.environ.get("LINK_RECIPIENT_FILE", "")
    if recipient and os.path.exists(recipient):
        link = client.call("GET", f"/betaGroups/{group['id']}")["data"]["attributes"].get("publicLink") or ""
        with open(recipient, "rb") as file:
            sealed = serialization.load_pem_public_key(file.read()).encrypt(link.encode(), padding.OAEP(
                mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
        print("Public link, encrypted: " + base64.b64encode(sealed).decode())


if __name__ == "__main__":
    try:
        main()
    except APIError as error:
        sys.exit(f"App Store Connect refused: {error}")
