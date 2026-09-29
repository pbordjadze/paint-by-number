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
exec > >(tee -a "$OUT/${KIND}-steps.log") 2>&1
step() { echo "$(date +%T) $KIND: $*"; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null; step booted
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"; step installed
appearance=light
# `ls` fails while there are no reports; under pipefail that would end the script.
count_reports() { { ls ~/Library/Logs/DiagnosticReports/PaintByNumber* 2>/dev/null || true; } | wc -l | tr -d ' '; }
seen_reports=$(count_reports)
for entry in "${SCENARIOS[@]}"; do
  scenario="${entry%@*}"; delay=8
  [[ "$entry" == *@* ]] && delay="${entry#*@}"
  want=light; [[ "$scenario" == *dark* ]] && want=dark
  if [[ "$want" != "$appearance" ]]; then
    xcrun simctl ui "$UDID" appearance "$want" || true
    appearance="$want"
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  step "launch $scenario: $(xcrun simctl launch "$UDID" "$BUNDLE_ID" -demo "$scenario" 2>&1 | tr '\n' ' ')"
  sleep "$delay"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/${KIND}-${scenario}.png" 2>/dev/null
  # A crash leaves a new report in the host's DiagnosticReports (simulator apps are host processes).
  reports=$(count_reports)
  if [[ "$reports" -gt "${seen_reports:-0}" ]]; then
    step "captured $scenario — CRASH: app crashed (see crashes/)"
  else
    step "captured $scenario"
  fi
  seen_reports=$reports
done
xcrun simctl spawn "$UDID" log show --last 15m --style compact --predicate 'process == "PaintByNumber"' > "$OUT/${KIND}-app.log" 2>/dev/null || true
