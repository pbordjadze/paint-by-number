#!/usr/bin/env bash
# Checks a built Release app for what a shipped build must (and must not) contain.
#   ci/check_release.sh <path/to/PaintByNumber.app>
# It carries the privacy manifest and export-compliance answer, and none of the Debug-only
# code (`DemoMode`, the demo scenarios, the synthetic template, the maps cache of demo and
# test launches): those types are compiled out of Release by `#if DEBUG`.
set -euo pipefail
APP="$1"
BINARY="$APP/$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$APP/Info.plist")"
failed=0
fail() { echo "FAIL: $*"; failed=1; }

[[ -f "$APP/PrivacyInfo.xcprivacy" ]] || fail "PrivacyInfo.xcprivacy is not in the app bundle"
plutil -lint "$APP/PrivacyInfo.xcprivacy" || fail "PrivacyInfo.xcprivacy is not a valid plist"
[[ "$(/usr/libexec/PlistBuddy -c "Print ITSAppUsesNonExemptEncryption" "$APP/Info.plist")" == "false" ]] \
  || fail "ITSAppUsesNonExemptEncryption is not false"

# Type names survive in the binary as mangled metadata (`13PaintDemoView`), the
# ready-marker and folder names as plain strings (`LineArtMaps` is the maps cache's type,
# `LineArtMapsCache`, and its Caches folder). Stripping first drops the debug map, which
# names every object file whether or not it compiled to anything.
WORK="$(mktemp -d)"
strip -S -x -o "$WORK/binary" "$BINARY"
strings -a "$WORK/binary" > "$WORK/strings.txt"
for symbol in DemoMode ShellDemo PaintDemoView SyntheticTemplate demo-ready DemoLibrary LineArtMaps; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done
[[ $failed -eq 0 ]] && echo "Release build ok: privacy manifest present, no Debug-only code"
exit $failed
