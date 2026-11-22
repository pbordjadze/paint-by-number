#!/usr/bin/env bash
# Renders the hidden modes' sounds (painting-company row 381) off the device, with the app's own
# synthesis: App/PaintByNumber/Feedback/ToneSynth.swift and EraSynth.swift, PaintCore's
# SplitMix64 and render_main.swift, compiled together by swiftc (UNRELEASED defined).
#   tools/sounds/render.sh <out-dir>      WAVs, levels.tsv and reel.wav
#   SWIFTC=/path/to/swiftc tools/sounds/render.sh <out-dir>   (default: swiftc on PATH)
# Then tools/sounds/sheet.py <out-dir> draws each one's waveform and spectrogram.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mkdir -p "${1:-era-sounds}" && cd "${1:-era-sounds}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
for f in App/PaintByNumber/Feedback/ToneSynth.swift App/PaintByNumber/Feedback/EraSynth.swift Sources/PaintCore/Foundation/SplitMix64.swift; do
  sed -e '/^import PaintCore$/d' "$ROOT/$f" > "$WORK/$(basename "$f")"
done
# Compiled with the app's default isolation (MainActor), PaintCore's types are nonisolated as
# they are in their own module.
sed -i 's/^public struct SplitMix64/nonisolated public struct SplitMix64/' "$WORK/SplitMix64.swift"
# The app's Sky (App/Shared/App/Sky.swift) reads UserDefaults through the eras' seams; the
# sounds need only its two cases.
printf 'nonisolated enum Sky: String, Sendable { case sun, moon }\n' > "$WORK/Sky.swift"
cp "$ROOT/tools/sounds/render_main.swift" "$WORK/main.swift"
"${SWIFTC:-swiftc}" -O -D UNRELEASED -swift-version 6 -default-isolation MainActor "$WORK"/*.swift -o "$WORK/render"
"$WORK/render" "$OUT"
