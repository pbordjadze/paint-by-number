#!/usr/bin/env python3
"""Makes sure the App Store's identifiers carry what the app and its extensions are signed with.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8=… python3 ci/asc_identifiers.py

Run by `.github/workflows/testflight.yml` before the export, whose cloud signing makes the App
Store profiles from these identifiers: the app (`com.pbordjadze.paintbynumber`) and its widgets
and stickers (`.widgets`, `.stickers`, from 1.3), each with App Groups. It registers a missing
bundle id and turns on a missing capability; a second run changes nothing. The API can't do the
rest, which is done once in the developer website (Certificates, Identifiers & Profiles): the
group `group.com.pbordjadze.paintbynumber` registered and chosen for all three identifiers, and
the app's Group Activities (Paint Together's SharePlay) turned on. Uses ci/testflight_testers.py's client.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from testflight_testers import APIError, Client, private_key  # noqa: E402

APP = "com.pbordjadze.paintbynumber"
WANTED = {
    APP: ("Paint by Moonlight", ["APP_GROUPS"]),
    APP + ".widgets": ("Paint by Moonlight Widgets", ["APP_GROUPS"]),
    APP + ".stickers": ("Paint by Moonlight Stickers", ["APP_GROUPS"]),
}


def bundle_id(client, identifier, name):
    for item in client.call("GET", "/bundleIds", query={"filter[identifier]": identifier, "limit": 50})["data"]:
        if item["attributes"]["identifier"] == identifier:
            return item["id"]
    made = client.call("POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": identifier, "name": name, "platform": "IOS"}}})
    print(f"Registered {identifier}.")
    return made["data"]["id"]


def main():
    client = Client(private_key())
    for identifier, (name, capabilities) in WANTED.items():
        bid = bundle_id(client, identifier, name)
        have = {c["attributes"]["capabilityType"]
                for c in client.call("GET", f"/bundleIds/{bid}/bundleIdCapabilities")["data"]}
        for capability in capabilities:
            if capability in have:
                continue
            client.call("POST", "/bundleIdCapabilities", {"data": {
                "type": "bundleIdCapabilities", "attributes": {"capabilityType": capability},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
            print(f"{identifier}: turned on {capability}.")
        print(f"{identifier}: {', '.join(sorted(have | set(capabilities)))}.")


if __name__ == "__main__":
    try:
        main()
    except APIError as error:
        sys.exit(f"App Store Connect refused: {error}")
