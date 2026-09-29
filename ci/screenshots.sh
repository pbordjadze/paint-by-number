#!/usr/bin/env bash
# Installs the built app on fresh simulators and captures one screenshot per demo scenario.
#   ci/screenshots.sh <path/to/PaintByNumber.app> <outdir> [scenario...]
# Each scenario is passed to the app as `-demo <scenario>`; the app renders that state
# deterministically. Optional "<scenario>@<seconds>" overrides the settle delay.
set -euo pipefail
APP="$1"; OUT="$2"; shift 2
SCENARIOS=("$@")
[[ ${#SCENARIOS[@]} -eq 0 ]] && SCENARIOS=(pipeline)
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
mkdir -p "$OUT"
DIR="$(cd "$(dirname "$0")" && pwd)"
# Reuse simulators created (and already booting) earlier in the job when available.
if [[ -n "${DEVICES_FILE:-}" && -s "${DEVICES_FILE}" ]]; then cp "$DEVICES_FILE" "$OUT/devices.txt"
else "$DIR/simulators.sh" > "$OUT/devices.txt"; fi
cat "$OUT/devices.txt"
exec 3< "$OUT/devices.txt"
while read -r -u 3 kind udid model runtime; do
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
  xcrun simctl install "$udid" "$APP"
  for entry in "${SCENARIOS[@]}"; do
    scenario="${entry%@*}"; delay=8
    [[ "$entry" == *@* ]] && delay="${entry#*@}"
    for appearance in light dark; do
      [[ "$appearance" == dark && "$scenario" != *dark* && "${SCREENSHOT_DARK:-0}" != 1 ]] && continue
      xcrun simctl ui "$udid" appearance "$appearance" || true
      xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
      xcrun simctl launch "$udid" "$BUNDLE_ID" -demo "$scenario" > /dev/null
      sleep "$delay"
      xcrun simctl io "$udid" screenshot --type=png "$OUT/${kind}-${scenario}-${appearance}.png"
      echo "captured ${kind}-${scenario}-${appearance}"
    done
  done
  xcrun simctl spawn "$udid" log show --last 5m --style compact --predicate 'process == "PaintByNumber"' > "$OUT/${kind}-app.log" 2>/dev/null || true
  xcrun simctl shutdown "$udid" || true
done < "$OUT/devices.txt"
