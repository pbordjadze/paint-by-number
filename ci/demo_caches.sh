#!/usr/bin/env bash
# Moves the app's demo caches between a simulator and a folder that actions/cache keeps from
# run to run.
#   ci/demo_caches.sh in  <udid> <path/to/PaintByNumber.app> <dir>   (installs the app first)
#   ci/demo_caches.sh out <udid> <path/to/PaintByNumber.app> <dir>
# The caches are the DEBUG `LineArtMapsCache` (each picture's maps: the line-art models take
# 10 to 40 s a picture on CI's simulators) and `DemoTemplateCache` (the templates the demos
# and tests seed), in the app's Library/Caches; installing the app again keeps them. Their
# entries are keyed by what made them, and the workflow's cache key hashes the code and files
# that make them besides, so a change to the pipeline, the models or the pictures starts empty.
set -euo pipefail
MODE="$1"; UDID="$2"; APP="$3"; DIR="$4"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
FOLDERS=(LineArtMaps DemoTemplates)
case "$MODE" in
  in)
    xcrun simctl install "$UDID" "$APP"
    CACHES="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Library/Caches"
    mkdir -p "$CACHES"
    for folder in "${FOLDERS[@]}"; do
      if [[ -d "$DIR/$folder" ]]; then cp -R "$DIR/$folder" "$CACHES/"; fi
    done
    ;;
  out)
    CACHES="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Library/Caches"
    rm -rf "$DIR" && mkdir -p "$DIR"
    for folder in "${FOLDERS[@]}"; do
      if [[ -d "$CACHES/$folder" ]]; then cp -R "$CACHES/$folder" "$DIR/"; fi
    done
    ;;
  *)
    echo "usage: $0 in|out <udid> <app> <dir>" >&2
    exit 2
    ;;
esac
echo "demo caches $MODE: $(find "$DIR" -type f 2>/dev/null | wc -l | tr -d ' ') files, $(du -sh "$DIR" 2>/dev/null | cut -f1)"
