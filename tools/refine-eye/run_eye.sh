#!/usr/bin/env bash
# Builds one worktree's app and UI tests (once, into its build/checks/dd-eye) and runs one of
# EyeCheckUITests' cases on a simulator while recording its screen: Refine's fades and stills
# compared between two builds (painting-company row 338's review).
#   tools/refine-eye/run_eye.sh <worktree> <tag> <simulator udid> <out dir> [test]
# test: testEyeCases (default), testEyeMarkedLook, testEyeStates, testEyeStartFrom, testEyeDrop,
# testEyeRepeat (EYE_SCENARIO, EYE_TIMES in the environment) or testEyeStills.
# Writes <out dir>/eye-<tag>/: screen.mp4, start (the video's 0 as an epoch), test.log; and, for
# testEyeStates, testEyeStartFrom, testEyeRepeat and testEyeStills, <out dir>/shots/<tag>-<name>.png. Then:
#   tools/refine-eye/eye.py marks <out dir>/eye-<tag> <crop w:h:x:y> [name=crop ...]
#   tools/refine-eye/eye.py stills <out dir>/shots <tag A> <tag B>
# Needs App/PaintByNumberUITests/EyeCheckUITests.swift in the worktree (copy it in; the folder is
# synced) and a simulator no other session uses (an iPad Pro 13-inch: the crops in eye.py's
# header are its pixels). Record the two builds back to back: under a heavily loaded Mac the
# recording drops frames and a fade looks like a pop.
set -uo pipefail
[[ $# -ge 4 ]] || { sed -n '2,15p' "$0"; exit 2; }
W="$1"; TAG="$2"; U="$3"; OUT="$(mkdir -p "$4" && cd "$4" && pwd)"; TEST="${5:-testEyeCases}"
DIR="$OUT/eye-$TAG"; mkdir -p "$DIR"
cd "$W"
SETTINGS=(ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO)
xcodebuild build-for-testing -project App/PaintByNumber.xcodeproj -scheme PaintByNumber -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/checks/dd-eye "${SETTINGS[@]}" > "$DIR/build.log" 2>&1 \
  || { echo "build failed: $DIR/build.log"; exit 1; }
xcrun simctl boot "$U" 2> /dev/null || true
xcrun simctl bootstatus "$U" -b > /dev/null
xcrun simctl ui "$U" appearance light
xcrun simctl io "$U" recordVideo --codec=h264 --force "$DIR/screen.mp4" 2> "$DIR/record.log" &
REC=$!
# The video's first frame is about when recordVideo says "Recording started": that moment is its 0.
for _ in $(seq 1 100); do grep -q "Recording started" "$DIR/record.log" && break; sleep 0.05; done
python3 -c 'import time; print("%.3f" % time.time())' > "$DIR/start"
TEST_RUNNER_EYE_OUT="$OUT" TEST_RUNNER_EYE_BUILD="$TAG" TEST_RUNNER_EYE_SCENARIO="${EYE_SCENARIO:-}" TEST_RUNNER_EYE_TIMES="${EYE_TIMES:-}" xcodebuild test-without-building \
  -project App/PaintByNumber.xcodeproj -scheme PaintByNumber -configuration Debug -destination "id=$U" \
  -derivedDataPath build/checks/dd-eye -only-testing:"PaintByNumberUITests/EyeCheckUITests/$TEST" \
  -resultBundlePath "$DIR/$TEST-$(date +%s).xcresult" "${SETTINGS[@]}" > "$DIR/test.log" 2>&1
status=$?
kill -INT $REC; wait $REC
echo "$TAG $TEST: exit $status"
grep -E "^eye|error:|Test Case.*(passed|failed|skipped)" "$DIR/test.log" | head -40
exit $status
