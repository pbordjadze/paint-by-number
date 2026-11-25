#!/usr/bin/env bash
# The stutter check (painting-company row 392): main's build played on Paul's wired iPad Air 5, timed, and
# judged before TestFlight may upload it. Polish rounds judged stills and the simulator; a menu caught
# mid-close or dropped frames only show in motion, on the device.
#   tools/stutter-gate/gate.sh [--force] [--no-status] [-n <runs>] [<commit or ref>]   (default: origin/main)
# Runs on the MacBook the iPad is wired to, as Paul (a LaunchAgent, com.pbm.ipad-stutter-gate, at 2:15 and
# 5:15 AM ET, before the nightly's 3:17 and its 5:47 second try; or by hand before a release upload).
#  1. Skips a commit already judged (a success or failure `ipad-stutter` status on it) unless --force.
#  2. Builds the commit as the nightly ships it (UNRELEASED, its files in) in ReleaseTests, optimized with
#     the tour log, signed for the iPad. Xcode signs only in Paul's unlocked GUI session.
#  3. Waits for the iPad up to 40 min: the lock ~/pbm-out/ipad.lock (a folder; its `owner` file says who,
#     with a pid: a lock whose pid is gone is taken over), and no other process naming the iPad's UDID.
#  4. tools/perf-tour/run.sh plays each scenario in limits.json <runs> times (default 2), unrecorded.
#  5. verdict.py holds every number to limits.json and writes report.md.
#  6. Sets the commit's `ipad-stutter` status (success, failure, or error when the check itself couldn't
#     run: the Mac's screen or the iPad locked, the iPad gone, the build failed) with the headline, and
#     pushes the report to refs/stutter/<commit>, which the status links to. TestFlight's workflow
#     uploads only a commit whose status is success.
# Everything stays in ~/pbm-out/stutter-gate/runs/<time>-<commit>/ (report.md, summary.txt, the logs).
# --no-status: judge without setting a status or pushing (a try-out). Exits 0 pass, 1 stutter, 2 error.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=pbordjadze/paint-by-number
UDID="${IPAD_UDID:-00008103-001D311E21FB001E}"
ROOT="$HOME/pbm-out/stutter-gate"
LOCK="$HOME/pbm-out/ipad.lock"
GUI_RUN="$HOME/pbm-out/tools/dispatcher/gui-run/gui-run.sh"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.2.0.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"
FORCE=0; STATUS=1; RUNS=2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1 ;;
    --no-status) STATUS=0 ;;
    -n) RUNS="$2"; shift ;;
    -*) sed -n '2,22p' "$0"; exit 2 ;;
    *) break ;;
  esac
  shift
done
WANT="${1:-origin/main}"
mkdir -p "$ROOT/runs"; touch "$ROOT/.keep"   # the nightly ~/pbm-out sweep keeps a folder with .keep

# The build's own checkout, apart from the one this script runs from.
SRC="$ROOT/src"
[[ -d "$SRC/.git" ]] || git clone -q "https://github.com/$REPO.git" "$SRC" || { echo "can't clone $REPO"; exit 2; }
git -C "$SRC" fetch -q origin '+refs/heads/*:refs/remotes/origin/*' || { echo "can't fetch $REPO"; exit 2; }
SHA="$(git -C "$SRC" rev-parse --verify -q "$WANT^{commit}")" || { echo "no commit $WANT"; exit 2; }
SHORT="${SHA:0:8}"
OUT="$ROOT/runs/$(date -u +%Y%m%d-%H%M)-$SHORT"; mkdir -p "$OUT"
exec > >(tee -a "$OUT/gate.log") 2>&1
echo "stutter check of $SHA ($WANT) at $(date)"

status() {  # <state> <description> [<url>]
  [[ $STATUS == 1 ]] || return 0
  gh api -X POST "repos/$REPO/statuses/$SHA" -f state="$1" -f context=ipad-stutter \
    -f description="${2:0:139}" ${3:+-f target_url="$3"} > /dev/null || echo "couldn't set the status"
}
# The report as a commit of its own on refs/stutter/<commit> (no branch, so no CI), its link printed.
publish() {
  [[ $STATUS == 1 ]] || return 0
  local entries="" f blob tree commit
  for f in report.md verdict.json summary.txt gate.log build.log; do
    [[ -f "$OUT/$f" ]] || continue
    blob=$(git -C "$SRC" hash-object -w "$OUT/$f") && entries+="100644 blob $blob	$f"$'\n'
  done
  tree=$(printf '%s' "$entries" | git -C "$SRC" mktree) || return 0
  commit=$(git -C "$SRC" -c user.name="stutter check" -c user.email=noreply@users.noreply.github.com \
    commit-tree "$tree" -m "Stutter check of $SHA") || return 0
  git -C "$SRC" push -q -f origin "$commit:refs/stutter/$SHA" > /dev/null 2>&1 || { echo "couldn't push the report" >&2; return 0; }
  echo "https://github.com/$REPO/blob/$commit/report.md"
}
# The check couldn't judge: an error status (the upload holds), the reason in its description.
trouble() {
  echo "ERROR: $1"
  printf '# Stutter check of %s\n\n**ERROR**: %s\n' "$SHORT" "$1" > "$OUT/report.md"
  status error "Stutter check couldn't run: $1" "$(publish)"
  exit 2
}

if [[ $FORCE == 0 && $STATUS == 1 ]]; then
  judged=$(gh api "repos/$REPO/commits/$SHA/statuses" --jq '[.[] | select(.context == "ipad-stutter")][0].state // empty' 2>/dev/null)
  if [[ "$judged" == success || "$judged" == failure ]]; then
    echo "already judged: $judged (--force to judge again)"; rm -rf "$OUT"; exit 0
  fi
fi

# One check at a time on this Mac (the build folder is shared).
holder=$(sed -n 's/.*pid \([0-9]*\).*/\1/p' "$ROOT/gate.lock/owner" 2>/dev/null)
[[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null && rm -rf "$ROOT/gate.lock"
mkdir "$ROOT/gate.lock" 2>/dev/null || { echo "another stutter check is running: $(cat "$ROOT/gate.lock/owner" 2>/dev/null)"; rm -rf "$OUT"; exit 0; }
echo "$SHORT, pid $$, since $(date)" > "$ROOT/gate.lock/owner"
trap 'rm -rf "$ROOT/gate.lock"' EXIT
status pending "Building it for the iPad"

# What only Paul can fix, named before the build spends ten minutes.
ioreg -n Root -d1 | grep -q '"CGSSessionScreenIsLocked"=Yes' && trouble "the Mac's screen is locked, and Xcode can't sign then (unlock it in RustDesk)"

git -C "$SRC" checkout -q --detach -f "$SHA" && git -C "$SRC" clean -qfdx || trouble "can't check out $SHORT"
DD="$ROOT/dd"
BUILD=(xcodebuild build -project "$SRC/App/PaintByNumber.xcodeproj" -scheme PaintByNumber -configuration ReleaseTests
  -destination generic/platform=iOS -derivedDataPath "$DD" -allowProvisioningUpdates -quiet
  ENABLE_TESTABILITY=NO CLANG_COVERAGE_MAPPING=NO DEVELOPMENT_TEAM=G4RX7UK5MJ CODE_SIGNING_ALLOWED=YES
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG UNRELEASED \$(inherited)" EXCLUDED_SOURCE_FILE_NAMES=)
echo "building"
# Signing needs Paul's GUI (Aqua) session: the LaunchAgent is in it; a background session goes through gui-run.
if [[ "$(launchctl managername 2>/dev/null)" == Aqua ]]; then
  (cd "$SRC" && "${BUILD[@]}") > "$OUT/build.log" 2>&1; rc=$?
else
  (cd "$SRC" && "$GUI_RUN" "$OUT/build.log" "${BUILD[@]}"); rc=$?
fi
if [[ $rc == 98 ]]; then trouble "the Mac's screen is locked, and Xcode can't sign then (unlock it in RustDesk)"; fi
if [[ $rc != 0 ]]; then
  grep -q "No Accounts\|No signing certificate\|requires a provisioning profile" "$OUT/build.log" \
    && trouble "Xcode couldn't sign for the iPad (its account, in Xcode's Settings)"
  trouble "the build failed: $(grep -m1 ' error: ' "$OUT/build.log" | sed 's/.*error: //' | cut -c1-80)"
fi
APP="$DD/Build/Products/ReleaseTests-iphoneos/PaintByNumber.app"

# The iPad, one user at a time: our lock, and any other run that names it (the other threads' tours,
# UI tests and installs).
others() { pgrep -fl "$UDID" | grep -v -e "$$" -e stutter-gate | grep -v grep; }
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  holder=$(sed -n 's/.*pid \([0-9]*\).*/\1/p' "$LOCK/owner" 2>/dev/null)
  if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
  if (( waited >= 2400 )); then trouble "the iPad stayed busy for 40 min ($(cat "$LOCK/owner" 2>/dev/null))"; fi
  sleep 30; waited=$((waited + 30))
done
echo "stutter check $SHORT, pid $$, since $(date)" > "$LOCK/owner"
trap 'rm -rf "$LOCK" "$ROOT/gate.lock"' EXIT
while others > /dev/null && (( waited < 2400 )); do sleep 30; waited=$((waited + 30)); done
others > /dev/null && trouble "the iPad stayed busy for 40 min: $(others | head -1 | cut -c1-80)"
status pending "Playing it on the iPad"

xcrun devicectl list devices 2>/dev/null | grep "$UDID" | grep -q connected || trouble "the iPad isn't connected to the Mac"
xcrun devicectl device info lockState --device "$UDID" 2>/dev/null | grep -q 'passcodeRequired: true' && trouble "the iPad is locked (unlock it, and keep it on power)"
PMD="$HOME/.local/share/uv/tools/homescreen-mcp/bin/pymobiledevice3"
if [[ -x "$PMD" ]]; then
  free=$("$PMD" lockdown get com.apple.disk_usage AmountDataAvailable --udid "$UDID" 2>/dev/null | tr -dc 0-9)
  [[ -n "$free" ]] && echo "iPad free space: $((free / 1000000000)) GB"
fi

SCENARIOS=($(python3 -c 'import json,sys; print(" ".join(k for k in json.load(open(sys.argv[1])) if not k.startswith("_")))' "$HERE/limits.json"))
echo "playing ${SCENARIOS[*]}, $RUNS runs each"
"$HERE/../perf-tour/run.sh" device "$UDID" "$OUT" -i "$APP" -n "$RUNS" -m "${SCENARIOS[@]}" > "$OUT/tour.log" 2>&1
grep -q "^install failed" "$OUT/tour.log" && trouble "installing on the iPad failed: $(tail -3 "$OUT/install.log" | tr '\n' ' ' | cut -c1-80)"

python3 "$HERE/verdict.py" "$OUT" "$HERE/limits.json" --title "Stutter check of $SHORT ($(date '+%b %-d, %-I:%M %p %Z'))"; rc=$?
state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$OUT/verdict.json" 2>/dev/null || echo error)
headline=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["headline"])' "$OUT/verdict.json" 2>/dev/null || echo "the verdict failed")
status "$state" "$headline" "$(publish)"
echo "$state: $headline"
echo "report: $OUT/report.md"
exit $rc
