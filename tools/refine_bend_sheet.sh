#!/usr/bin/env bash
# Bend Line on the lighthouse, off the device: a pen line down the sky bent 96 points across the
# sky's paints, a short free line bowed, and the lighthouse's side pulled into the sky (its paint
# following), laid by `pbn refine` as the app lays them, then drawn by tools/refine_sheet.py
# (painting-company row 277).
#   tools/refine_bend_sheet.sh <outdir>      (needs a release pbn: tools/swift.sh build -c release
#                                             --static-swift-stdlib; Pillow)
# Writes <outdir>/sheet.png and <outdir>/crops/NN-<tool>.png, the area round the lighthouse after
# each gesture.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: tools/refine_bend_sheet.sh <outdir>}"
mkdir -p "$OUT/in"
PBN="$(find "$ROOT/.build" -path '*release/pbn' -type f | head -1)"
[[ -x "$PBN" ]] || { echo "build pbn first (tools/swift.sh build -c release --static-swift-stdlib)" >&2; exit 1; }
python3 - "$ROOT" "$OUT/in" <<'PY'
import sys
from PIL import Image
root, out = sys.argv[1], sys.argv[2]
Image.open(f"{root}/Tests/Corpus/lighthouse.jpg").convert("RGB").save(f"{out}/photo.ppm")
for kind in ("contours", "drawing"):
    Image.open(f"{root}/tools/baseline/lines/lighthouse-{kind}.png").convert("L").save(f"{out}/{kind}.pgm")
PY
cat > "$OUT/in/gestures.json" <<'JSON'
{"screen": {"width": 960, "zoom": 1},
 "gestures": [
  {"tool": "pen", "points": [[0.68, 0.08], [0.68, 0.14], [0.68, 0.20], [0.68, 0.26], [0.68, 0.32], [0.68, 0.36]], "inked": true, "caption": "a pen line down the sky"},
  {"tool": "reshape", "points": [[0.68, 0.22], [0.78, 0.22]], "target": "ink", "caption": "Bend Line its middle 96 pt right"},
  {"tool": "pen", "points": [[0.497, 0.30], [0.53, 0.30], [0.58, 0.30]], "inked": true, "caption": "a short line beside the lighthouse"},
  {"tool": "reshape", "points": [[0.54, 0.30], [0.54, 0.24]], "target": "ink", "caption": "Bend Line it up"},
  {"tool": "reshape", "points": [[0.497, 0.45], [0.56, 0.45]], "target": "ink", "caption": "Bend the lighthouse's side into the sky"}
 ]}
JSON
"$PBN" refine "$OUT/in/photo.ppm" "$OUT/in/gestures.json" --out "$OUT" \
  --edges "$OUT/in/contours.pgm" --lines "$OUT/in/drawing.pgm" > /dev/null
python3 "$ROOT/tools/refine_sheet.py" "$OUT"
python3 - "$OUT" <<'PY'
import glob, os, sys
from PIL import Image
out = sys.argv[1]
os.makedirs(f"{out}/crops", exist_ok=True)
for path in sorted(glob.glob(f"{out}/steps/*.ppm")):
    if path.endswith("-touches.ppm"):
        continue
    im = Image.open(path)
    w, h = im.size
    name = os.path.basename(path)[:-4]
    im.crop((int(w * 0.40), 0, int(w * 0.85), int(h * 0.55))).save(f"{out}/crops/{name}.png")
PY
