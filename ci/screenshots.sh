#!/usr/bin/env bash
# Installs the built app on a simulator and captures one screenshot per demo scenario.
#   ci/screenshots.sh <path/to/PaintByNumber.app> <outdir> <kind> <udid> [scenario...]
# Each scenario is passed to the app as `-demo <scenario>`; the app renders that state
# deterministically. "<scenario>@<seconds>" overrides the settle delay (default 8 s).
# Scenarios whose name contains "dark" are captured in dark appearance.
set -euo pipefail
APP="$1"; OUT="$2"; KIND="$3"; UDID="$4"; shift 4
SCENARIOS=("$@")
[[ ${#SCENARIOS[@]} -eq 0 ]] && SCENARIOS=(pipeline)
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
mkdir -p "$OUT"
step() { echo "$(date +%T) $KIND: $*"; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null; step booted
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"; step installed
appearance=light
for entry in "${SCENARIOS[@]}"; do
  scenario="${entry%@*}"; delay=8
  [[ "$entry" == *@* ]] && delay="${entry#*@}"
  want=light; [[ "$scenario" == *dark* ]] && want=dark
  if [[ "$want" != "$appearance" ]]; then
    xcrun simctl ui "$UDID" appearance "$want" || true
    appearance="$want"
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -demo "$scenario" > /dev/null
  sleep "$delay"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/${KIND}-${scenario}.png" 2>/dev/null
  step "captured $scenario"
done
xcrun simctl spawn "$UDID" log show --last 15m --style compact --predicate 'process == "PaintByNumber"' > "$OUT/${KIND}-app.log" 2>/dev/null || true
# Crash reports of the app (a simulator app's crashes land in the host's DiagnosticReports).
find "$HOME/Library/Logs/DiagnosticReports" -name 'PaintByNumber*' -newer "$APP" -exec cp {} "$OUT/" \; 2>/dev/null || true
