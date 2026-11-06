#!/usr/bin/env bash
# Prints one "<kind> <udid> <model> <runtime>" line per simulator wanted.
#   ci/simulators.sh [iphone|ipad|duo ...]   (default: iphone and ipad)
# For each kind, the newest iOS runtime of the selected Xcode's simulator SDK (ci/xcode.sh) that
# runs its device (26.4.1 over 26.4), else the newest older one that does, with a warning; never
# one newer than the SDK: a runner image with a later Xcode installed beside ours carries a later
# runtime too. (Xcode 27.1's iOS 27.1 runtime came for the iPhone Duo, and a runtime need not run
# every device.) The devices: the newest iPhone Pro, the largest iPad Pro and the iPhone Duo, the
# foldable (ci/duo.sh folds it), using the runner image's device of that type if it has one, else
# creating a PBN-<kind>.
set -euo pipefail
python3 - "$@" <<'PY'
import json, subprocess, re, sys
wanted = sys.argv[1:] or ["iphone", "ipad"]
def sim(*a): return subprocess.run(["xcrun", "simctl", *a], check=True, capture_output=True, text=True).stdout
runtimes = [r for r in json.loads(sim("list", "runtimes", "-j"))["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
sdk = subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], check=True, capture_output=True, text=True).stdout.strip()
def key(v): return [int(x) for x in v.split(".")]
# A patch runtime (26.4.1) is still the SDK's; one newer than the SDK never is.
fitting = sorted((r for r in runtimes if key(r["version"])[:2] <= key(sdk)[:2]), key=lambda r: key(r["version"]), reverse=True)
if not fitting:
    raise SystemExit("no iOS runtime up to %s, this Xcode's simulator SDK; installed: %s" % (sdk, ", ".join(r["version"] for r in runtimes)))
all_types = None
def types_of(runtime):
    global all_types
    if runtime.get("supportedDeviceTypes"):
        return runtime["supportedDeviceTypes"]
    if all_types is None:
        all_types = json.loads(sim("list", "devicetypes", "-j"))["devicetypes"]
    return all_types
PATTERNS = {
    "iphone": [r"iPhone 17 Pro", r"iPhone 1\d Pro", r"iPhone .*Pro"],
    "ipad": [r"iPad Pro 13-inch \(M5\)", r"iPad Pro 13-inch \(M\d\)", r"iPad Pro 13-inch.*", r"iPad Pro.*"],
    "duo": [r"iPhone Duo.*"],
}
def pick(patterns):
    """The newest fitting runtime with a device type for the first pattern any runtime has."""
    for p in patterns:
        for runtime in fitting:
            c = [t for t in types_of(runtime) if re.fullmatch(p, t["name"])]
            if c: return runtime, c[-1]
    raise SystemExit("no device type for %s in the iOS runtimes %s" % (patterns, ", ".join(r["version"] for r in fitting)))
devices = json.loads(sim("list", "devices", "available", "-j"))["devices"]
for kind in ("iphone", "ipad", "duo"):
    if kind not in wanted: continue
    runtime, t = pick(PATTERNS[kind])
    if key(runtime["version"])[:2] != key(sdk)[:2]:
        print("::warning::no iOS %s runtime runs the %s; using %s" % (sdk, t["name"], runtime["version"]), file=sys.stderr)
    # Reuse a device the runner image already created (its data container exists, so the
    # first boot is much faster than for a brand-new device).
    existing = [d for d in devices.get(runtime["identifier"], []) if d["deviceTypeIdentifier"] == t["identifier"]]
    if existing:
        print(kind, existing[0]["udid"], t["name"].replace(" ", "_"), runtime["version"])
        continue
    name = "PBN-" + kind
    udid = sim("create", name, t["identifier"], runtime["identifier"]).strip()
    print(kind, udid, t["name"].replace(" ", "_"), runtime["version"])
PY
