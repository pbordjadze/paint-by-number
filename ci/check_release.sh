#!/usr/bin/env bash
# Checks a built Release app for what a shipped build must (and must not) contain.
#   ci/check_release.sh <path/to/PaintByNumber.app>
# It carries the privacy manifest and export-compliance answer, the making-of's spec (the screen
# behind Settings' The Making-of ships), none of the Marginarium or Refine's screen, and none of the Debug-only code (`DemoMode`, the demo scenarios, the synthetic template, the maps and
# template caches of demo and test launches, their main-thread watchdog, the feedback upload stub
# and its `-feedback-upload` launch argument): those types are compiled out of Release by
# `#if DEBUG`.
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
# `DemoTemplates`; `FeedbackUploadStub` the feedback stub's, `feedback-upload` the launch argument
# that picks it). Stripping first drops the debug map, which names every object file whether
# or not it compiled to anything.
WORK="$(mktemp -d)"
strip -S -x -o "$WORK/binary" "$BINARY"
strings -a "$WORK/binary" > "$WORK/strings.txt"
for symbol in DemoMode ShellDemo PaintDemoView MakingOfDemoView SyntheticTemplate demo-ready DemoLibrary LineArtMaps DemoTemplate MainThreadWatchdog FeedbackUploadStub feedback-upload; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done

# The Marginarium is in Debug builds only for now: Release leaves out its code, chapters and
# drawings (the target's EXCLUDED_SOURCE_FILE_NAMES). The making-of show draws no guardian, so
# nothing of it reaches the Marginarium's sprite sheets (`MakingOfSprites` is gone). The MakingOf
# package still holds the crew's `Show` and its messages naming `pet-metrics.json`, so only the
# file is checked for that one, not the binary.
for symbol in MarginariumView MarginariumReaderView MarginariumSpritePlayer MarginariumDocument SpriteAtlas MakingOfSprites; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done
# Refine is in SideStore and Debug builds only for now: Release leaves out its screen and the
# gallery's draft row, which continues it (the target's EXCLUDED_SOURCE_FILE_NAMES, every
# Refine*.swift; its edits' model, RefineEdits.swift, is back in by INCLUDED_SOURCE_FILE_NAMES, for
# paintings refined before).
for symbol in RefineView RefineSurfaceView RefineColorsPanel RefineAreaCard RefinePaletteBar DraftRow; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done
for file in marginarium.json pet-metrics.json; do
  [[ ! -e "$APP/$file" ]] || fail "the Release app bundles $file"
done
# The launch screen is the gallery's paper (light or dark), not a white flash before it.
[[ "$(/usr/libexec/PlistBuddy -c "Print UILaunchScreen:UIColorName" "$APP/Info.plist" 2>/dev/null)" == "Paper" ]] \
  || fail "the launch screen isn't the Paper color (UILaunchScreen:UIColorName)"
# The making-of ships behind Settings' The Making-of: its spec is bundled, or the switch would do nothing.
[[ -s "$APP/making-of.json" ]] || fail "the Release app doesn't bundle making-of.json, so The Making-of would do nothing"
if compgen -G "$APP/pet-*.webp" > /dev/null; then fail "the Release app bundles the Marginarium's pet sheets"; fi
if xcrun --find assetutil > /dev/null 2>&1; then
  if xcrun assetutil --info "$APP/Assets.car" 2>/dev/null | grep -qE '"Name" : "(pip|colophon)-'; then
    fail "the Release asset catalog holds Pip's or Colophon's frames"
  fi
fi
[[ $failed -eq 0 ]] && echo "Release build ok: privacy manifest present, paper launch screen, making-of spec bundled, no Debug-only code, no Marginarium, no Refine"
exit $failed
