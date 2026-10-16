#!/usr/bin/env bash
# Checks a built Release app for what a shipped build must (and must not) contain.
#   ci/check_release.sh <path/to/PaintByNumber.app>
# It carries the privacy manifest and export-compliance answer, none of the Marginarium, and none
# of the Debug-only code (`DemoMode`, the demo scenarios, the synthetic template, the maps and
# template caches of demo and test launches, their main-thread watchdog): those types are compiled
# out of Release by `#if DEBUG`.
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
# `LineArtMapsCache`, and its Caches folder; `DemoTemplate` the template cache's and its
# `DemoTemplates`). Stripping first drops the debug map, which names every object file whether
# or not it compiled to anything.
WORK="$(mktemp -d)"
strip -S -x -o "$WORK/binary" "$BINARY"
strings -a "$WORK/binary" > "$WORK/strings.txt"
for symbol in DemoMode ShellDemo PaintDemoView MakingOfDemoView SyntheticTemplate demo-ready DemoLibrary LineArtMaps DemoTemplate MainThreadWatchdog; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done

# The Marginarium is in Debug builds only for now: Release leaves out its code, chapters and
# drawings (the target's EXCLUDED_SOURCE_FILE_NAMES), and the making-of's data until its screen ships.
for symbol in MarginariumView MarginariumReaderView MarginariumSpritePlayer MarginariumDocument SpriteAtlas; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done
for file in marginarium.json making-of.json pet-metrics.json; do
  [[ ! -e "$APP/$file" ]] || fail "the Release app bundles $file"
done
if compgen -G "$APP/pet-*.webp" > /dev/null; then fail "the Release app bundles the Marginarium's pet sheets"; fi
if xcrun --find assetutil > /dev/null 2>&1; then
  if xcrun assetutil --info "$APP/Assets.car" 2>/dev/null | grep -qE '"Name" : "(pip|colophon)-'; then
    fail "the Release asset catalog holds Pip's or Colophon's frames"
  fi
fi
[[ $failed -eq 0 ]] && echo "Release build ok: privacy manifest present, no Debug-only code, no Marginarium"
exit $failed
