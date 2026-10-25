#!/usr/bin/env bash
# Prints one "<kind> <udid> <model> <runtime>" line per simulator wanted.
#   ci/simulators.sh [iphone|ipad ...]   (default: both)
# Picks the iOS runtime of the selected Xcode's simulator SDK (ci/xcode.sh; the newest such
# runtime, so 26.4.1 over 26.4, else the newest older one, with a warning), never one newer: a
# runner image with a later Xcode installed beside ours carries a later runtime too. Then the newest iPhone Pro / largest iPad Pro
# device types, using the runner image's device of that type if it has one, else creating a
# PBN-<kind>.
set -euo pipefail
python3 - "$@" <<'PY'
import json, subprocess, re, sys
wanted = sys.argv[1:] or ["iphone", "ipad"]
def sim(*a): return subprocess.run(["xcrun", "simctl", *a], check=True, capture_output=True, text=True).stdout
runtimes = [r for r in json.loads(sim("list", "runtimes", "-j"))["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
sdk = subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], check=True, capture_output=True, text=True).stdout.strip()
def key(v): return [int(x) for x in v.split(".")]
# A patch runtime (26.4.1) is still the SDK's; one newer than the SDK never is.
fitting = [r for r in runtimes if key(r["version"])[:2] <= key(sdk)[:2]]
if not fitting:
    raise SystemExit("no iOS runtime up to %s, this Xcode's simulator SDK; installed: %s" % (sdk, ", ".join(r["version"] for r in runtimes)))
runtime = sorted(fitting, key=lambda r: key(r["version"]))[-1]
if key(runtime["version"])[:2] != key(sdk)[:2]:
    print("::warning::no iOS %s runtime for this Xcode's simulator SDK; using %s" % (sdk, runtime["version"]), file=sys.stderr)
types = runtime.get("supportedDeviceTypes") or json.loads(sim("list", "devicetypes", "-j"))["devicetypes"]
names = [t["name"] for t in types]
def pick(patterns):
    for p in patterns:
        c = [t for t in types if re.fullmatch(p, t["name"])]
        if c: return c[-1]
    raise SystemExit("no device type for %s in %s" % (patterns, names))
phone = pick([r"iPhone 17 Pro", r"iPhone 1\d Pro", r"iPhone .*Pro"])
pad = pick([r"iPad Pro 13-inch \(M5\)", r"iPad Pro 13-inch \(M\d\)", r"iPad Pro 13-inch.*", r"iPad Pro.*"])
devices = json.loads(sim("list", "devices", "available", "-j"))["devices"].get(runtime["identifier"], [])
for kind, t in (("iphone", phone), ("ipad", pad)):
    if kind not in wanted: continue
    # Reuse a device the runner image already created (its data container exists, so the
    # first boot is much faster than for a brand-new device).
    existing = [d for d in devices if d["deviceTypeIdentifier"] == t["identifier"]]
    if existing:
        print(kind, existing[0]["udid"], t["name"].replace(" ", "_"), runtime["version"])
        continue
    name = "PBN-" + kind
    udid = sim("create", name, t["identifier"], runtime["identifier"]).strip()
    print(kind, udid, t["name"].replace(" ", "_"), runtime["version"])
PY
