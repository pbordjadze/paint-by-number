#!/usr/bin/env bash
# Checks a built Release app for what a shipped build must (and must not) contain.
#   ci/check_release.sh <path/to/PaintByNumber.app>
# It carries the privacy manifest and export-compliance answer, the launch screen's paper, the making-of's spec (the screen
# behind Settings' The Making-of ships), nothing of the Marginarium, none of what the project leaves
# out of Release, and none of the Debug-only code. Run from the repository: the types it looks for
# are read from the sources, so a file added to either set is checked without an edit here.
set -euo pipefail
APP="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$APP/$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$APP/Info.plist")"
failed=0
fail() { echo "FAIL: $*"; failed=1; }

[[ -f "$APP/PrivacyInfo.xcprivacy" ]] || fail "PrivacyInfo.xcprivacy is not in the app bundle"
plutil -lint "$APP/PrivacyInfo.xcprivacy" || fail "PrivacyInfo.xcprivacy is not a valid plist"
[[ "$(/usr/libexec/PlistBuddy -c "Print ITSAppUsesNonExemptEncryption" "$APP/Info.plist")" == "false" ]] \
  || fail "ITSAppUsesNonExemptEncryption is not false"

# Strings left after stripping, which drops the debug map (it names every object file whether or
# not it compiled to anything).
WORK="$(mktemp -d)"
strip -S -x -o "$WORK/binary" "$BINARY"
strings -a "$WORK/binary" > "$WORK/strings.txt"

# The top-level types of two sets of files, each line "<name> <file>": the files the app target's
# Release EXCLUDED_SOURCE_FILE_NAMES leaves out (less its INCLUDED_SOURCE_FILE_NAMES: Refine's
# screen and the gallery's draft row, which SideStore builds carry, CLAUDE.md › App rules), and the
# files whose code is wholly inside `#if DEBUG` (the demo and test launches' code).
python3 - "$ROOT" > "$WORK/types.txt" <<'PY'
import fnmatch, pathlib, re, shlex, sys
root = pathlib.Path(sys.argv[1])
project = (root / "App/PaintByNumber.xcodeproj/project.pbxproj").read_text()
sources = sorted((root / "App/PaintByNumber").rglob("*.swift"))
def setting(block, name):
    m = re.search(r"\b%s = (\"[^\"]*\"|[^;]*);" % name, block)
    return shlex.split(m.group(1).strip('"')) if m else []
# Each configuration is `isa`, then its `buildSettings = { … };` (no braces inside), then its name.
configurations = re.findall(r"isa = XCBuildConfiguration;\s*buildSettings = \{([^{}]*)\};\s*name = (\w+);", project)
blocks = [b for b, name in configurations if name == "Release" and "EXCLUDED_SOURCE_FILE_NAMES" in b]
if len(blocks) != 1: sys.exit("expected one Release configuration with EXCLUDED_SOURCE_FILE_NAMES, found %d" % len(blocks))
excluded, included = setting(blocks[0], "EXCLUDED_SOURCE_FILE_NAMES"), setting(blocks[0], "INCLUDED_SOURCE_FILE_NAMES")
def matches(path, patterns): return any(fnmatch.fnmatchcase(path.name, p) for p in patterns)
left_out = [p for p in sources if matches(p, excluded) and not matches(p, included)]
def debug_only(path):
    text = re.sub(r"/\*.*?\*/", "", path.read_text(), flags=re.S)
    lines = [l.split("//")[0].strip() for l in text.splitlines()]
    code = [l for l in lines if l and not l.startswith("import ")]
    depth = 0
    for l in code:
        if depth == 0 and l != "#if DEBUG": return False
        depth += l.startswith("#if ") - (l == "#endif")
    return bool(code) and depth == 0
declaration = re.compile(r"^(?:(?:public|internal|private|fileprivate|final|nonisolated|indirect|@\w+(?:\([^)]*\))?) +)*(?:struct|class|enum|actor|protocol) +(\w+)", re.M)
files = left_out + [p for p in sources if debug_only(p)]
if not left_out or len(files) == len(left_out): sys.exit("found no excluded or no Debug-only files: the check would check nothing")
for path in files:
    for name in declaration.findall(path.read_text()):
        print(name, path.relative_to(root))
PY
# A type's descriptor holds its name as a C string of its own, so a whole line of the strings.
# Mangled names are no test: they abbreviate words already seen (`PaletteBuilder` can hold
# `7Builder`), and a shipped type that merely contains the name (`DemoTemplate` in
# `DemoTemplateCache`) must not count.
while read -r name file; do
  if grep -qxF "$name" "$WORK/strings.txt"; then
    fail "the Release binary contains $name ($file)"
  fi
done < "$WORK/types.txt"
echo "checked $(wc -l < "$WORK/types.txt" | tr -d ' ') types left out of Release"
# The Debug-only launch arguments and folder names (the ready marker, the demo library, the
# caches, the feedback stub's `-feedback-upload` and the App Store stub's `-demo…` arguments).
for symbol in demo-ready DemoLibrary LineArtMaps DemoTemplates feedback-upload demoFreePaintings demoUnlocked demoPurchase; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done

# Paul's decision (October 23): the Marginarium is private for now; it leaves every build and this
# repository. Its archive is in the private painting-company repository. These checks keep any of
# it from coming back into the app, and the making-of show draws no sprites.
for symbol in MarginariumView MarginariumReaderView SpriteAtlas MakingOfSprites; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done
for file in marginarium.json; do
  [[ ! -e "$APP/$file" ]] || fail "the Release app bundles $file"
done
# The launch screen is the gallery's paper (light or dark), not a white flash before it.
[[ "$(/usr/libexec/PlistBuddy -c "Print UILaunchScreen:UIColorName" "$APP/Info.plist" 2>/dev/null)" == "Paper" ]] \
  || fail "the launch screen isn't the Paper color (UILaunchScreen:UIColorName)"
# The making-of ships behind Settings' The Making-of: its spec is bundled, or the switch would do nothing.
[[ -s "$APP/making-of.json" ]] || fail "the Release app doesn't bundle making-of.json, so The Making-of would do nothing"
if compgen -G "$APP/pet-*.webp" > /dev/null; then fail "the Release app bundles the Marginarium's sprite sheets"; fi
if xcrun --find assetutil > /dev/null 2>&1; then
  if xcrun assetutil --info "$APP/Assets.car" 2>/dev/null | grep -qE '"Name" : "(pip|colophon)-'; then
    fail "the Release asset catalog holds the Marginarium's frames"
  fi
fi
[[ $failed -eq 0 ]] && echo "Release build ok: privacy manifest present, paper launch screen, making-of spec bundled, nothing the project leaves out of Release, no Debug-only code, no Marginarium"
exit $failed
