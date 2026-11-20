#!/usr/bin/env bash
# Paint Together end to end, hands free (painting-company row 350): this Mac runs the app as
# "Designed for iPad" on the owner's Apple ID, a cabled iPad runs it on a second Apple ID (FaceTime
# signed in to it), and both keep their -tourLog for summary.py: hitches on each side and how long a
# fill takes to reach the friend.
#
#   tools/together-e2e/run.sh build  <ipad udid>         # signed Debug builds for the Mac and the iPad
#                                                         # (REGISTER_MAC=1 the first time: registers this Mac)
#   tools/together-e2e/run.sh mac                        # launch the Mac's app (-tourLog, -playHarness)
#   tools/together-e2e/run.sh ipad   <ipad udid> <out>   # the iPad's side: TogetherE2ETests.testGuest
#   tools/together-e2e/run.sh collect <ipad udid> <out>  # both logs into <out>, then summary.py
#
# Between `mac` and `ipad`'s first minutes, someone (a person or computer use) on the Mac calls the
# iPad's Apple ID in FaceTime, opens a painting in the Mac's app and picks More > Paint Together,
# then paints in it; the iPad's test answers, joins, waits for the painting and paints its own
# areas (TogetherE2ETests' header: its knobs). The Mac's side is not a UI test: XCUITest on a Mac
# can't reach FaceTime, so it stays with whoever drives the Mac.
#
# Builds sign with the Xcode account on this Mac, so they run in its GUI session: GUI_RUN (default
# ~/pbm-out/tools/dispatcher/gui-run/gui-run.sh) wraps each xcodebuild (an xcodebuild over SSH or
# Remote Control finds no account). They are made from a scratch copy of HEAD (WORK, default
# ~/pbm-out/e2e/src), whose project prepare.py edits: the app's Debug signs with SharePlay's
# entitlement (AppStore.entitlements) and, for the Mac, runs as Designed for iPad. The repository's
# own project is never edited. Installing the Debug build on the iPad replaces its TestFlight app
# (its paintings stay); TestFlight puts it back.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORK="${WORK:-$HOME/pbm-out/e2e/src}"
DD="${DD:-$HOME/pbm-out/e2e/dd}"
GUI_RUN="${GUI_RUN:-$HOME/pbm-out/tools/dispatcher/gui-run/gui-run.sh}"
TEAM="${TEAM:-G4RX7UK5MJ}"   # the project sets no DEVELOPMENT_TEAM: automatic signing needs one
BUNDLE=com.pbordjadze.paintbynumber
XB_ENV=()
cmd="${1:-}"; shift || true

copy() { # <dir> [--mac]: the scratch copy at this checkout's HEAD, prepared
  rm -rf "$1"; mkdir -p "$(dirname "$1")"
  git -C "$REPO" worktree prune
  git -C "$REPO" worktree add --detach "$1" HEAD > /dev/null
  python3 "$HERE/prepare.py" "$1/App/PaintByNumber.xcodeproj/project.pbxproj" ${2:-}
}

# xb <log> <xcodebuild args>: gui-run takes the log first and writes the build's output there; it
# passes only PATH, HOME and DEVELOPER_DIR on, so the test's TEST_RUNNER_* go through env.
xb() { local log="$1"; shift; "$GUI_RUN" "$log" env ${XB_ENV[@]+"${XB_ENV[@]}"} xcodebuild DEVELOPMENT_TEAM="$TEAM" "$@"; }

case "$cmd" in
  build)
    UDID="$1"
    copy "$WORK"
    copy "$WORK-mac" --mac
    xb "$DD-ipad-build.log" -project "$WORK/App/PaintByNumber.xcodeproj" -scheme PaintByNumber -configuration Debug \
      -destination "id=$UDID" -derivedDataPath "$DD/ipad" -allowProvisioningUpdates build-for-testing \
      || { tail -40 "$DD-ipad-build.log"; exit 1; }
    # The Mac must be a registered device of the team (once, the owner's call: it takes a slot).
    xb "$DD-mac-build.log" -project "$WORK-mac/App/PaintByNumber.xcodeproj" -scheme PaintByNumber -configuration Debug \
      -destination 'platform=macOS,variant=Designed for iPad' -derivedDataPath "$DD/mac" \
      -allowProvisioningUpdates ${REGISTER_MAC:+-allowProvisioningDeviceRegistration} build \
      || { tail -40 "$DD-mac-build.log"; exit 1; }
    for app in "$DD"/ipad/Build/Products/Debug-iphoneos/PaintByNumber.app "$DD"/mac/Build/Products/Debug-iphoneos/PaintByNumber.app; do
      codesign -d --entitlements - "$app" 2>/dev/null | grep -q group-session \
        || { echo "$app lacks the group-session entitlement"; exit 1; }
    done
    echo "built: $DD/ipad, $DD/mac" ;;
  mac)
    APP="$DD/mac/Build/Products/Debug-iphoneos/PaintByNumber.app"
    pkill -f "$APP/PaintByNumber" 2>/dev/null || true
    open -n "$APP" --args -tourLog YES -playHarness
    echo "launched $APP" ;;
  ipad)
    UDID="$1"; OUT="$2"; mkdir -p "$OUT"
    XB_ENV=(TEST_RUNNER_TOGETHER_E2E=guest $(env | grep '^TEST_RUNNER_' || true))
    : > "$OUT/ipad-test.log"
    tail -f "$OUT/ipad-test.log" | grep --line-buffered -E "TOGETHER|error|failed|passed" & watcher=$!
    xb "$OUT/ipad-test.log" -project "$WORK/App/PaintByNumber.xcodeproj" -scheme PaintByNumber \
      -destination "id=$UDID" -derivedDataPath "$DD/ipad" -resultBundlePath "$OUT/ipad.xcresult" \
      -only-testing:PaintByNumberUITests/TogetherE2ETests test-without-building || status=$?
    kill "$watcher" 2>/dev/null || true
    exit "${status:-0}" ;;
  collect)
    UDID="$1"; OUT="$2"; mkdir -p "$OUT/ipad-tmp"
    xcrun devicectl device copy from --device "$UDID" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
      --source tmp --destination "$OUT/ipad-tmp" > /dev/null
    IPAD_LOG="$(ls -t "$OUT"/ipad-tmp/tour-log-*.tsv 2>/dev/null | head -1)"
    # A Designed for iPad app keeps its data in a container of its own on the Mac.
    MAC_LOG="$(ls -t "$HOME"/Library/Containers/*/Data/tmp/tour-log-*.tsv 2>/dev/null | head -1)"
    [[ -n "$IPAD_LOG" && -n "$MAC_LOG" ]] || { echo "missing a log: ipad=$IPAD_LOG mac=$MAC_LOG"; exit 1; }
    cp "$IPAD_LOG" "$OUT/ipad.tsv"; cp "$MAC_LOG" "$OUT/mac.tsv"; rm -rf "$OUT/ipad-tmp"
    python3 "$HERE/summary.py" mac="$OUT/mac.tsv" ipad="$OUT/ipad.tsv" | tee "$OUT/summary.txt" ;;
  *) sed -n '2,26p' "$0"; exit 2 ;;
esac
