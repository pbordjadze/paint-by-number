#!/usr/bin/env bash
# Carries each demo scenario through every pose of the iPhone Duo, the foldable, and shoots each.
#   ci/duo.sh <path/to/PaintByNumber.app> <outdir> <udid> [scenario[@seconds]...]
# CI's `duo` entry runs it (`[duo]` in a branch commit's message) on ci/duo-scenarios.txt. A
# scenario is launched once, closed and upright, as `-demo <scenario>` (ci/screenshots.sh's
# readiness marker and timeout), then folded and turned in place, so each picture after the
# first is the app carried over, as a painter's would be:
#   1-closed        the outer display, upright: compact width, the system's bars on its side
#   2-turned        the outer display on its side: compact both ways
#   3-open          opened flat like a book: the inner display, wide, bars still on the side
#   4-book          half open like a book: the fold down the middle
#   5-open-turned   flat and turned: the inner display upright, its bars across the top
#   6-laptop        half open and turned: the fold across the middle, like a laptop on a table
#   7-closed-again  closed upright again: back on the outer display
# After each pose: duo-<scenario>-<n>-<pose>.png of the display the UI is on, and the layout the
# app wrote (Debug demo launches, `DuoLayoutProbe`) as .json beside it, checked by
# ci/duo/check.py: a control lying on the fold fails the step once every scenario has been shot.
# The fold is ci/duo/hinge.m's HID event, Device Hub's own; the display, devicectl's.
set -euo pipefail
APP="$1"; OUT="$2"; UDID="$3"; shift 3
SCENARIOS=("$@")
[[ ${#SCENARIOS[@]} -eq 0 ]] && SCENARIOS=(paint)
HERE="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
mkdir -p "$OUT"
exec > >(tee -a "$OUT/duo-steps.log") 2>&1
step() { echo "$(date +%T) duo: $*"; }
die() { step "error: $*"; exit 1; }
# Seconds a pose has to settle: the system's fold animation, the backlight, the app's layout.
POSE_SETTLE=${POSE_SETTLE:-3}

HELPER="$OUT/../duo-hinge"
xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -O2 -fobjc-arc -w \
  -o "$HELPER" "$HERE/duo/hinge.m" -framework IOKit -framework CoreFoundation -framework Foundation \
  -framework CoreMotion || die "the hinge helper didn't build"
codesign -f -s - "$HELPER" >/dev/null 2>&1 || die "the hinge helper couldn't be signed"
hinge() { xcrun simctl spawn "$UDID" "$HELPER" "$@"; }

# The orientation as devicectl names it, as Device Hub's event does: "landscape-left".
orientation() {
  xcrun devicectl device orientation get -d "$UDID" -q -j - 2>/dev/null \
    | plutil -extract result.deviceOrientationNonFlat raw -o - - 2>/dev/null \
    | sed -E 's/([a-z])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]' || true
}
turn() {
  local want="$1" event="$1"
  [[ "$want" == portrait-upside-down ]] && event=pud
  hinge orient "$event" || true
  for _ in 1 2 3 4 5 6 7 8; do [[ "$(orientation)" == "$want" ]] && return 0; sleep 0.25; done
  # Not every runtime follows the event: devicectl's own call.
  local name
  case "$want" in
    portrait) name=portrait ;; landscape-left) name=landscapeLeft ;; landscape-right) name=landscapeRight ;;
    *) name=portraitUpsideDown ;;
  esac
  xcrun devicectl device orientation set "$name" -d "$UDID" -q >/dev/null 2>&1 || true
  [[ "$(orientation)" == "$want" ]] || step "warning: the orientation is '$(orientation)', not $want"
}
fold() { hinge set "$1" 4 || die "the hinge didn't reach ${1}°"; }

# The integrated display the UI is on (devicectl's `active`; its lit backlight when it has no
# such flag), as `simctl io --display` names it. Empty when devicectl can't tell.
active_display() {
  local doc i=0 name active backlight
  doc="$(xcrun devicectl device info displays -d "$UDID" -q -j - 2>/dev/null)" || return 0
  while name="$(plutil -extract "result.displays.$i.name" raw -o - - <<< "$doc" 2>/dev/null)"; do
    if plutil -extract "result.displays.$i.type.integrated" raw -o - - <<< "$doc" >/dev/null 2>&1; then
      active="$(plutil -extract "result.displays.$i.active" raw -o - - <<< "$doc" 2>/dev/null || true)"
      backlight="$(plutil -extract "result.displays.$i.backlightState" raw -o - - <<< "$doc" 2>/dev/null || echo unknown)"
      if [[ "$active" == true || ( -z "$active" && "$backlight" != off && "$backlight" != unknown ) ]]; then
        echo "$name"; return 0
      fi
    fi
    i=$((i + 1))
  done
}

shoot() {
  local base="$1" display="" args=()
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    display="$(active_display)"; [[ -n "$display" ]] && break; sleep 0.25
  done
  [[ -n "$display" ]] && args=(--display="$display")
  xcrun simctl io "$UDID" screenshot --type=png ${args[@]+"${args[@]}"} "$base.png" >/dev/null 2>&1 \
    || xcrun simctl io "$UDID" screenshot --type=png "$base.png" >/dev/null 2>&1 \
    || step "warning: no screenshot of ${display:-the default display}" >&2
  echo "${display:-default}"
}

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null; step booted
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
step "hinge at $(hinge get 2>&1 || echo "?")°, orientation '$(orientation)', on $(active_display)"
xcrun simctl install "$UDID" "$APP"; step installed
CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
MARKER="$CONTAINER/tmp/demo-ready"
LAYOUT="$CONTAINER/tmp/duo-layout.json"
SETTLE=${SETTLE:-2}
POSES=("1-closed 0 portrait" "2-turned 0 landscape-left" "3-open 180 portrait" "4-book 90 portrait"
       "5-open-turned 180 landscape-left" "6-laptop 90 landscape-left" "7-closed-again 0 portrait")
count_reports() { { ls ~/Library/Logs/DiagnosticReports/PaintByNumber* 2>/dev/null || true; } | wc -l | tr -d ' '; }
seen_reports=$(count_reports)
on_fold=0
for entry in "${SCENARIOS[@]}"; do
  scenario="${entry%@*}"; delay=8
  [[ "$entry" == *@* ]] && delay="${entry#*@}"
  xcrun simctl ui "$UDID" appearance "$([[ "$scenario" == *dark* ]] && echo dark || echo light)" || true
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  fold 0; turn portrait; sleep 1
  rm -f "$MARKER" "$LAYOUT"
  launch_args=(-demo "$scenario")
  [[ "$scenario" == *long-text* ]] && launch_args+=(-NSDoubleLocalizedStrings YES)
  step "launch $scenario: $(xcrun simctl launch "$UDID" "$BUNDLE_ID" "${launch_args[@]}" 2>&1 | tr '\n' ' ')"
  started=$SECONDS
  while [[ ! -f "$MARKER" && $((SECONDS - started)) -lt $delay ]]; do sleep 0.25; done
  if [[ -f "$MARKER" ]]; then
    step "$scenario ready after $((SECONDS - started)) s"
    sleep "$SETTLE"
  else
    step "$scenario: no ready marker within $delay s"
  fi
  for pose in "${POSES[@]}"; do
    read -r name angle turned <<< "$pose"
    if [[ "$name" != 1-closed ]]; then
      # Turned to the pose's side first, then folded or opened.
      [[ "$(orientation)" == "$turned" ]] || turn "$turned"
      fold "$angle"
      sleep "$POSE_SETTLE"
    fi
    base="$OUT/duo-$scenario-$name"
    display="$(shoot "$base")"
    cp "$LAYOUT" "$base.json" 2>/dev/null || true
    python3 "$HERE/duo/check.py" "$base.json" "$scenario/$name" || on_fold=$((on_fold + 1))
    step "captured $scenario $name (${angle}°, $(orientation), on $display)"
  done
  reports=$(count_reports)
  if [[ "$reports" -gt "${seen_reports:-0}" ]]; then step "captured $scenario — CRASH: app crashed (see crashes/)"; fi
  seen_reports=$reports
done
fold 0; turn portrait
xcrun simctl ui "$UDID" appearance light || true
xcrun simctl spawn "$UDID" log show --last 30m --style compact --predicate 'process == "PaintByNumber"' > "$OUT/duo-app.log" 2>/dev/null || true
[[ $on_fold -eq 0 ]] || die "$on_fold pose(s) with a control on the fold (FOLD lines above)"
step done
