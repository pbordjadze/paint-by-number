#!/usr/bin/env bash
# Every check of the app and its packages, on a Mac with Xcode, in the build of your choice: what a
# change must keep passing where CI isn't run (painting-company row 292).
#   tools/checks.sh [-c Debug|ReleaseTests] [-u] [-s <simulator udid>] [-o <outdir>] [-d <derived data>] [step...]
# Steps (default: all of them, in this order):
#   packages    `swift test` on macOS: PaintCore, MakingOf and the mosaic packages
#   regression  the quality gate (tools/regression.py) on a release `pbn`, its JSON kept
#   release     the Release build with ci/check_release.sh, and the SideStore build (Release with UNRELEASED)
#   build       the app and its tests, built for testing in the chosen build
#   warmup      the demo pictures the UI tests wait for, made once per simulator (as CI's warm-up)
#   unit        PaintByNumberTests
#   ui          PaintByNumberUITests, but PerformanceTour (a measurement, not a check)
# -c  Debug is CI's. ReleaseTests (the default) is Release with the demo and test code in (`DEBUG`) and
#     the app testable: the optimized code a release ships, PaintCore at -Ounchecked.
# -u  adds UNRELEASED to ReleaseTests: the SideStore build's features (Debug always has them).
# -s  the simulator (an iPad Pro 13-inch, as CI's); default: ci/simulators.sh's.
# A failed test runs once more, as on CI; summary.txt names it either way. Compiler warnings fail `build`
# and `release`, as on CI (ci/warnings.sh).
# Results: <outdir>/summary.txt (a line a step, then the failed tests), the logs and .xcresult bundles
# beside it. Exits 1 when a step failed.
set -uo pipefail
cd "$(dirname "$0")/.."
CONFIG=ReleaseTests; UNRELEASED=0; UDID=""; OUT=""; DD=""
while getopts "c:us:o:d:" flag; do
  case "$flag" in
    c) CONFIG="$OPTARG" ;;
    u) UNRELEASED=1 ;;
    s) UDID="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    d) DD="$OPTARG" ;;
    *) sed -n '2,22p' "$0"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
STEPS=("$@"); [[ ${#STEPS[@]} -eq 0 ]] && STEPS=(packages regression release build warmup unit ui)
[[ "$CONFIG" == Debug || "$CONFIG" == ReleaseTests ]] || { echo "unknown build: $CONFIG"; exit 2; }
NAME="$CONFIG"; [[ $UNRELEASED == 1 && "$CONFIG" == ReleaseTests ]] && NAME="$CONFIG-unreleased"
OUT="${OUT:-build/checks/$NAME}"; DD="${DD:-build/checks/dd-$NAME}"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
PROJECT=App/PaintByNumber.xcodeproj; SCHEME=PaintByNumber
SETTINGS=(ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO)
[[ "$NAME" == ReleaseTests-unreleased ]] && SETTINGS+=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG UNRELEASED $(inherited)')
SUMMARY="$OUT/summary.txt"
echo "checks of $(git rev-parse --short=8 HEAD)$(git diff --quiet HEAD || echo ' (with uncommitted changes)'), $NAME, $(date '+%Y-%m-%d %H:%M %Z'), $(xcodebuild -version | tr '\n' ' ')" > "$SUMMARY"
failed=0
note() { echo "$*" | tee -a "$SUMMARY"; }
finish() { # <step> <exit status> <seconds> <what>
  local verdict=pass; [[ $2 -ne 0 ]] && { verdict=FAIL; failed=1; }
  note "$1: $verdict ($3 s) $4"
}
simulator() {
  if [[ -z "$UDID" ]]; then read -r _ UDID _ < <(ci/simulators.sh ipad); fi
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b > /dev/null
  # A UI test's `XCUIDevice.shared.appearance` changes nothing on a simulator whose appearance was
  # never set (DarkPaperTests), as on CI.
  xcrun simctl ui "$UDID" appearance dark || true
  xcrun simctl ui "$UDID" appearance light || true
}
# The tests of an .xcresult bundle: counts, each failure, and what passed only when run again.
results() { # <bundle>
  xcrun xcresulttool get test-results summary --path "$1" --compact 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("%s tests: %s passed, %s failed, %s skipped" % (d.get("totalTestCount"), d.get("passedTests"), d.get("failedTests"), d.get("skippedTests")))
for f in d.get("testFailures", []):
    print("  FAILED %s: %s" % (f.get("testIdentifierString") or f.get("testName"), " ".join((f.get("failureText") or "").split())[:300]))
' || echo "no readable results in $1"
  xcrun xcresulttool get test-results tests --path "$1" --compact 2>/dev/null | python3 -c '
import json, sys
def walk(node, path):
    name = node.get("name", "")
    kids = node.get("children", [])
    if node.get("nodeType") == "Test Case":
        runs = [k for k in kids if k.get("nodeType") == "Repetition"]
        if len(runs) > 1 and node.get("result") == "Passed":
            print("  passed when run again: %s" % node.get("nodeIdentifier", name))
        if node.get("result") == "Skipped":
            print("  skipped: %s" % node.get("nodeIdentifier", name))
    for k in kids: walk(k, path + [name])
for n in json.load(sys.stdin).get("testNodes", []): walk(n, [])
' || true
}
run_tests() { # <step> <log name> <selection...>
  local step="$1" log="$OUT/$2.log" bundle="$OUT/$2.xcresult"; shift 2
  simulator
  rm -rf "$bundle"
  local start=$SECONDS
  xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -destination "id=$UDID" -derivedDataPath "$DD" "$@" -retry-tests-on-failure -test-iterations 2 \
    -resultBundlePath "$bundle" "${SETTINGS[@]}" > "$log" 2>&1
  local status=$?
  finish "$step" $status $((SECONDS - start)) "$(results "$bundle" | head -1)"
  results "$bundle" | tail -n +2 | tee -a "$SUMMARY"
}

for step in "${STEPS[@]}"; do
  start=$SECONDS
  case "$step" in
    packages)
      swift test > "$OUT/packages.log" 2>&1; status=$?
      finish packages $status $((SECONDS - start)) "$(grep -E 'Test run with [0-9]+ tests' "$OUT/packages.log" | tail -1 | sed -E 's/^[^T]*//')"
      grep -E 'recorded an issue' "$OUT/packages.log" | sed -E 's/^[^T]*Test /  FAILED /; s/ recorded an issue at /: /' | cut -c1-300 | sort -u | tee -a "$SUMMARY"
      ;;
    regression)
      { swift build -c release --product pbn 2>&1 | tail -3
        python3 tools/regression.py --json "$OUT/regression.json" --sheets "$OUT/regression-sheets"; } > "$OUT/regression.log" 2>&1; status=$?
      finish regression $status $((SECONDS - start)) "$(tail -1 "$OUT/regression.log" | cut -c1-200)"
      ;;
    release)
      status=0
      xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DD-release" -quiet ARCHS=arm64 COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO > "$OUT/release-build.log" 2>&1 || status=1
      ci/check_release.sh "$DD-release/Build/Products/Release-iphonesimulator/PaintByNumber.app" > "$OUT/release-check.log" 2>&1 || status=1
      xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DD-sidestore" -quiet ARCHS=arm64 COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO \
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS=UNRELEASED $(inherited)' EXCLUDED_SOURCE_FILE_NAMES= > "$OUT/sidestore-build.log" 2>&1 || status=1
      ci/warnings.sh "$OUT/release-warnings.txt" "$OUT/release-build.log" "$OUT/sidestore-build.log" > /dev/null || status=1
      finish release $status $((SECONDS - start)) "$(tail -1 "$OUT/release-check.log" | cut -c1-160); $(wc -l < "$OUT/release-warnings.txt" | tr -d ' ') warning(s)"
      ;;
    build)
      xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" "${SETTINGS[@]}" > "$OUT/build.log" 2>&1; status=$?
      ci/warnings.sh "$OUT/build-warnings.txt" "$OUT/build.log" > /dev/null || status=1
      finish build $status $((SECONDS - start)) "$(grep -E '\*\* TEST BUILD' "$OUT/build.log" | tail -1); $(wc -l < "$OUT/build-warnings.txt" | tr -d ' ') warning(s)"
      grep -E ' error: ' "$OUT/build.log" | sed "s#$PWD/##" | sort -u | cut -c1-300 | head -40 | tee -a "$SUMMARY"
      ;;
    warmup)
      simulator
      ci/screenshots.sh "$DD/Build/Products/$CONFIG-iphonesimulator/PaintByNumber.app" "$OUT/warmup" ipad "$UDID" \
        gallery@300 gallery-favorites@300 create-preview@180 create-from-file@180 > "$OUT/warmup.log" 2>&1; status=$?
      finish warmup $status $((SECONDS - start)) ""
      ;;
    unit) run_tests unit unit -only-testing:PaintByNumberTests ;;
    ui) run_tests ui ui -only-testing:PaintByNumberUITests -skip-testing:PaintByNumberUITests/PerformanceTour ;;
    *) note "$step: unknown step"; failed=1 ;;
  esac
done
exit $failed
