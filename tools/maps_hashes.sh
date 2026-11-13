#!/usr/bin/env bash
# Whether a change left the line-art maps the app makes byte for byte as they were (painting-company row 292):
# the two models' maps of a picture and what Vision finds in it (eyes, subjects, writing). Nothing else pins
# them: the tests compare a run with itself, and with PyTorch within two levels.
#   tools/maps_hashes.sh <path/to/PaintByNumber.app> <simulator udid> <out.txt> [<reference.txt>]
# The app is a build with the demo scenarios in (Debug or ReleaseTests), for the simulator. Its caches of maps
# and of demo templates are cleared on that simulator, CI's warm-up scenarios run (ci/screenshots.sh: they seed
# the bundled pictures, whose maps the app computes and keeps, `LineArtMapsCache`), and every kept file is
# hashed: a line a picture (sha1, bytes, the file's name, which is the picture's own hash). With a reference
# (the same from the build before the change, same Mac, same simulator runtime) it says whether every picture's
# maps are the same and exits 1 if not. A few minutes; the simulator is this run's alone meanwhile.
set -euo pipefail
APP="$1"; UDID="$2"; OUT="$3"; REF="${4:-}"
# The output and the reference may be given relative to where this was called from.
[[ "$OUT" == /* ]] || OUT="$PWD/$OUT"
[[ -z "$REF" || "$REF" == /* ]] || REF="$PWD/$REF"
cd "$(dirname "$0")/.."
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun simctl boot "$UDID" 2> /dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2> /dev/null || true
caches="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Library/Caches"
rm -rf "$caches/LineArtMaps" "$caches/DemoTemplates"
scratch="$(mktemp -d)"
ci/screenshots.sh "$APP" "$scratch" ipad "$UDID" gallery@300 gallery-favorites@300 create-preview@180 create-from-file@180 \
  > "$scratch/warm-up.log" 2>&1 || { tail -5 "$scratch/warm-up.log"; echo "the warm-up failed"; exit 1; }
caches="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Library/Caches"
[[ -d "$caches/LineArtMaps" ]] || { echo "the app kept no maps"; exit 1; }
(cd "$caches/LineArtMaps" && for f in *.maps; do echo "$(shasum "$f" | cut -c1-40) $(stat -f %z "$f") $f"; done | sort -k3) > "$OUT"
echo "$(wc -l < "$OUT" | tr -d ' ') pictures' maps hashed"
rm -rf "$scratch"
if [[ -n "$REF" ]]; then
  if diff -q "$REF" "$OUT" > /dev/null; then
    echo "every picture's maps are byte for byte the reference's"
  else
    diff "$REF" "$OUT" | head -20
    echo "the maps differ from the reference"
    exit 1
  fi
fi
