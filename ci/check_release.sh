#!/usr/bin/env bash
# Checks a built Release app for what a shipped build must (and must not) contain.
#   ci/check_release.sh <path/to/PaintByNumber.app>
# It carries the privacy manifest and export-compliance answer, and none of the Debug-only
# demo code (`DemoMode`, the demo scenarios, the pipeline check screen, the synthetic
# template): those types are compiled out of Release by `#if DEBUG`.
set -euo pipefail
APP="$1"
BINARY="$APP/$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$APP/Info.plist")"
failed=0
fail() { echo "FAIL: $*"; failed=1; }

[[ -f "$APP/PrivacyInfo.xcprivacy" ]] || fail "PrivacyInfo.xcprivacy is not in the app bundle"
plutil -lint "$APP/PrivacyInfo.xcprivacy" || fail "PrivacyInfo.xcprivacy is not a valid plist"
[[ "$(/usr/libexec/PlistBuddy -c "Print ITSAppUsesNonExemptEncryption" "$APP/Info.plist")" == "false" ]] \
  || fail "ITSAppUsesNonExemptEncryption is not false"

# Type names survive in the binary as mangled metadata (`17PipelineCheckView`), the
# ready-marker and library folder names as plain strings. Stripping first drops the debug
# map, which names every object file whether or not it compiled to anything.
WORK="$(mktemp -d)"
strip -S -x -o "$WORK/binary" "$BINARY"
strings -a "$WORK/binary" > "$WORK/strings.txt"
for symbol in DemoMode ShellDemo PaintDemoView PipelineCheckView SyntheticTemplate demo-ready DemoLibrary; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done
[[ $failed -eq 0 ]] && echo "Release build ok: privacy manifest present, no demo code"
exit $failed
