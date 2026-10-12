#!/usr/bin/env python3
"""Import approved Marginarium Markdown without changing the identity of other blocks.

    python3 tools/marginarium.py import chapter.md --id lampBrush
    python3 tools/marginarium.py check
    python3 -m unittest discover -s tools/tests -p 'test_marginarium.py'

Stdlib only. The import writes docs/marginarium/<id>.md (the editable source, NOT bundled),
Resources/marginarium.json (ordered chapters/blocks, version 1), and Localizable.xcstrings.
--root DIR selects a repository, including a temporary one for tests. Importing does not
constitute editorial approval: only import text Paul has approved.

Format: a # title, a subtitle paragraph, then ATX headings (# through ######), paragraphs,
> quotes (including multiple paragraphs), bullet items (-, * or +; two-space nesting), and
standalone ![VoiceOver description](asset-name) images from Assets.xcassets, or
![VoiceOver description](pet:pip) pets. Each bullet item
is a block. Continuation lines in an item are indented two spaces beyond its bullet. Quotes
contain paragraphs, not nested block structures. Emphasis, strong emphasis, inline code and
inline links stay as Markdown in catalog values for Foundation's AttributedString parser.
Line breaks and inline spelling are preserved; only block syntax is removed. Unsupported
block syntax fails with a line number rather than silently losing structure. Images require
a nonempty plain-text description and bundled art; no remote images are fetched. Pets are Pip,
Colophon, or a v2 atlas named Resources/pet-<id>.webp (lowercase alphanumeric/hyphen id).
Atlas pets idle and wave on tap. The app validates the 1536 × 2288 sheet before slicing it.

Every block in the saved source has a <!-- marginarium: <key> --> marker. KEEP that marker
with its block when editing or moving it; delete both together. New unmarked blocks get UUID
keys, never ordinal keys. The manifest records those keys. Reimporting unmarked text recovers
unique exact matches from the previous manifest; ambiguous duplicate matches fail and ask
for markers. Markers let even identical paragraphs retain their separate identities.

New keys are marginarium.<id>.block.<uuid>. Explicit markers may reuse the entry's existing
title/subtitle/passage keys if their text matches exactly. Those legacy entries (including
their translator comments) are never rewritten or deleted. Import only removes stale keys
in its own .block. namespace; translations of unchanged blocks are retained, and translations
of edited blocks are marked needs_review. New comments name the chapter and block kind.

check is read-only: source order, kind, key, heading level, bullet depth and image/pet name must
exactly match the manifest, and every English value must equal the Markdown block, including
inline markup and whitespace. It also rejects missing/unlisted sources, reused or stale keys,
missing images, and non-manual entries. strings_check.py calls the same validation and counts
each manifest key as a runtime localization use (like sample.<id>).
"""

import argparse
from collections import Counter, defaultdict
from copy import deepcopy
from dataclasses import dataclass, field
import json
from pathlib import Path
import re
import sys
import uuid

CATALOG = Path("App/PaintByNumber/Resources/Localizable.xcstrings")
MANIFEST = Path("App/PaintByNumber/Resources/marginarium.json")
SOURCES = Path("docs/marginarium")
ASSETS = Path("App/PaintByNumber/Resources/Assets.xcassets")
RESOURCES = ASSETS.parent
# These shipped imageset pets keep their existing playback plans in Marginarium.swift.
PET_IMAGESETS = {"pip": {"idle": 6, "wave": 4}, "colophon": {"idle": 6, "review": 6}}
MARKER = re.compile(r"<!-- marginarium: ([A-Za-z0-9_.-]+) -->")
HEADING = re.compile(r"(#{1,6}) (.+)")
BULLET = re.compile(r"( *)([-+*]) (.+)")
IMAGE = re.compile(r"!\[([^\[\]\n]+)\]\((pet:[a-z0-9]+(?:-[a-z0-9]+)*|[A-Za-z0-9][A-Za-z0-9_.-]*)\)")
ENTRY_ID = re.compile(r"[A-Za-z][A-Za-z0-9]*")


@dataclass
class Block:
    kind: str
    text: str
    start: int
    key: str | None = None
    metadata: dict = field(default_factory=dict)

    def record(self):
        return {"kind": self.kind, "key": self.key, **self.metadata}


def parse(source):
    """Parse the supported Markdown block grammar; offsets allow adding markers losslessly."""
    lines = source.splitlines()
    blocks = []
    pending = None
    i = 0

    def fail(message):
        raise ValueError(f"line {i + 1}: {message}")

    def special(line):
        return (MARKER.fullmatch(line) or HEADING.fullmatch(line) or BULLET.fullmatch(line)
                or line.startswith((">", "![", "<!--")))

    def plain(line):
        if (line.startswith(("```", "~~~", "<", "    ", "\t"))
                or re.match(r"^\s*(?:\d+[.)]\s|[-*_]{3,}\s*$|=+\s*$|\|)", line)
                or re.match(r"^\s*\[[^]]+\]:", line)):
            fail("unsupported block syntax")
        if "![" in line:
            fail("images must be standalone ![plain description](asset-name) or (pet:id) blocks")

    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        marker = MARKER.fullmatch(line)
        if marker:
            if pending:
                fail("two markers before one block")
            pending = marker[1]
            i += 1
            continue
        start = i
        metadata = {}
        if match := HEADING.fullmatch(line):
            kind, text = "heading", re.sub(r"[ \t]+#+[ \t]*$", "", match[2])
            plain(text)
            metadata["level"] = len(match[1])
            i += 1
        elif line.startswith(">"):
            kind, content = "quote", []
            while i < len(lines) and lines[i].startswith(">"):
                inner = lines[i][1:]
                if inner.startswith(" "):
                    inner = inner[1:]
                if special(inner):
                    fail("quotes support paragraphs and inline Markdown only")
                plain(inner)
                content.append(inner)
                i += 1
            text = "\n".join(content)
        elif match := BULLET.fullmatch(line):
            kind = "bullet"
            indent = len(match[1])
            if indent % 2:
                fail("bullet nesting uses two spaces per level")
            metadata["depth"] = indent // 2
            plain(match[3])
            content = [match[3]]
            i += 1
            while i < len(lines) and lines[i].strip() and not special(lines[i]):
                continuation = lines[i]
                if not continuation.startswith(" " * (indent + 2)):
                    fail("bullet continuation needs two spaces beyond its bullet")
                inner = continuation[indent + 2:]
                plain(inner)
                content.append(inner)
                i += 1
            text = "\n".join(content)
        elif match := IMAGE.fullmatch(line):
            kind, text = "image", match[1]
            if any(c in text for c in "*_`<>") or not text.strip():
                fail("image descriptions must be nonempty plain text")
            if match[2].startswith("pet:"):
                kind = "pet"
                metadata["pet"] = match[2][4:]
            else:
                metadata["image"] = match[2]
            i += 1
        else:
            kind, content = "paragraph", []
            while i < len(lines) and lines[i].strip():
                if special(lines[i]):
                    if content:
                        break
                    fail("invalid block or marker syntax")
                plain(lines[i])
                content.append(lines[i])
                i += 1
            text = "\n".join(content)
        if not text.strip():
            fail("empty block")
        blocks.append(Block(kind, text, start, pending, metadata))
        pending = None
    if pending:
        fail("marker without a block")
    if len(blocks) < 2 or blocks[0].kind != "heading" or blocks[0].metadata["level"] != 1:
        raise ValueError("a chapter starts with a # title and a subtitle paragraph")
    if blocks[1].kind != "paragraph":
        raise ValueError("the block after the title must be a subtitle paragraph")
    blocks[0].kind, blocks[0].metadata = "title", {}
    blocks[1].kind = "subtitle"
    return blocks


def english(entry):
    return entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")


def prefix(entry_id):
    return f"marginarium.{entry_id}.block."


def allowed_key(key, entry_id):
    legacy = {f"marginarium.{part}{entry_id}.{suffix}"
              for part in ("", "appendix.") for suffix in ("title", "subtitle", "passage")}
    return bool(key and (key in legacy or (key.startswith(prefix(entry_id))
                                         and re.fullmatch(r"[A-Za-z0-9_-]+", key[len(prefix(entry_id)):]))))


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def load_manifest(root):
    manifest = load_json(root / MANIFEST)
    if manifest.get("version") != 1 or not isinstance(manifest.get("chapters"), list):
        raise ValueError("manifest must have version 1 and chapters")
    seen = set()
    for chapter in manifest["chapters"]:
        entry_id = chapter["id"]
        if not ENTRY_ID.fullmatch(entry_id) or entry_id in seen:
            raise ValueError(f"invalid or duplicate chapter id: {entry_id}")
        seen.add(entry_id)
        if chapter["source"] != str(SOURCES / f"{entry_id}.md"):
            raise ValueError(f"{entry_id}: unexpected source path")
    return manifest


def check_art(root, block):
    if block.kind == "pet":
        pet = block.metadata["pet"]
        if pet in PET_IMAGESETS:
            for row, count in PET_IMAGESETS[pet].items():
                for index in range(count):
                    check_art(root, Block("image", block.text, block.start,
                                          metadata={"image": f"{pet}-{row}-{index}"}))
        elif not (root / RESOURCES / f"pet-{pet}.webp").is_file():
            raise ValueError(f"pet {pet}: expected a bundled pet-{pet}.webp atlas")
    if block.kind == "image":
        matches = list((root / ASSETS).rglob(f"{block.metadata['image']}.imageset/Contents.json"))
        if len(matches) != 1:
            raise ValueError(f"image {block.metadata['image']}: expected one bundled image set")
        images = load_json(matches[0]).get("images", [])
        files = [image["filename"] for image in images if image.get("filename")]
        if not files or not all((matches[0].parent / name).is_file() for name in files):
            raise ValueError(f"image {block.metadata['image']}: image set has missing files")


def validate(root):
    """Return (manifest, [(key, exact English)]) or fail; used by strings_check as well."""
    manifest = load_manifest(root)
    catalog = load_json(root / CATALOG)["strings"]
    used = {}
    listed = set()
    for chapter in manifest["chapters"]:
        source = root / chapter["source"]
        listed.add(source.resolve())
        blocks = parse(source.read_text(encoding="utf-8"))
        if [block.record() for block in blocks] != chapter["blocks"]:
            raise ValueError(f"{chapter['source']}: manifest differs from Markdown; run import")
        for block in blocks:
            if not allowed_key(block.key, chapter["id"]):
                raise ValueError(f"{source.name}: missing or invalid block key {block.key}")
            if block.key in used:
                raise ValueError(f"reused block key: {block.key}")
            entry = catalog.get(block.key, {})
            if english(entry) != block.text:
                raise ValueError(f"{block.key}: catalog English differs from Markdown")
            if entry.get("extractionState") != "manual" or not entry.get("comment", "").strip():
                raise ValueError(f"{block.key}: needs manual extraction and a translator comment")
            if block.key.startswith(prefix(chapter["id"])) and entry["comment"] != comment(chapter["id"], blocks[0].text, block):
                raise ValueError(f"{block.key}: comment must name the chapter and block kind")
            check_art(root, block)
            used[block.key] = block.text
    actual = {path.resolve() for path in (root / SOURCES).glob("*.md")}
    if actual != listed or not listed:
        raise ValueError("Markdown sources and manifest chapter list differ or are empty")
    for key in catalog:
        if re.fullmatch(r"marginarium\.[A-Za-z][A-Za-z0-9]*\.block\..+", key) and key not in used:
            raise ValueError(f"stale catalog block key: {key}")
    return manifest, list(used.items())


def comment(entry_id, title, block):
    detail = f"{block.kind} description for VoiceOver" if block.kind in ("image", "pet") else block.kind
    return f"The Marginarium: {title} ({entry_id}); {detail} block. Preserve inline Markdown."


def write_json(path, value, *, catalog=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2,
                               separators=(",", " : " if catalog else ": ")) + "\n", encoding="utf-8")


def import_chapter(root, source, entry_id):
    if not ENTRY_ID.fullmatch(entry_id):
        raise ValueError("entry id must be an alphanumeric identifier starting with a letter")
    original = source.read_text(encoding="utf-8")
    blocks = parse(original)
    catalog = load_json(root / CATALOG)
    strings = catalog["strings"]
    manifest = load_manifest(root) if (root / MANIFEST).exists() else {"version": 1, "chapters": []}
    old = next((c for c in manifest["chapters"] if c["id"] == entry_id), None)
    marked = [block.key for block in blocks if block.key]
    if len(set(marked)) != len(marked):
        raise ValueError("duplicate block marker; give the new block its own marker or remove its marker")
    available = defaultdict(list)
    unmarked = Counter((block.kind, block.text) for block in blocks if block.key is None)
    for record in old["blocks"] if old else []:
        if record["key"] not in marked:
            signature = (record["kind"], english(strings.get(record["key"], {})))
            available[signature].append(record["key"])
    for block in blocks:
        check_art(root, block)
        if block.key is None:
            signature = (block.kind, block.text)
            candidates = available[signature]
            if candidates and (len(candidates) > 1 or unmarked[signature] > 1):
                raise ValueError("ambiguous repeated text; keep the markers from docs/marginarium with their blocks")
            block.key = candidates.pop() if candidates else prefix(entry_id) + uuid.uuid4().hex
        if not allowed_key(block.key, entry_id):
            raise ValueError(f"{block.key}: key does not belong to {entry_id}")
        existing = strings.get(block.key)
        if not block.key.startswith(prefix(entry_id)):
            if existing is None or english(existing) != block.text:
                raise ValueError(f"{block.key}: existing title/subtitle/passage must stay word for word")
            continue
        entry = deepcopy(existing) if existing else {}
        if existing and english(existing) != block.text:
            for language, translation in entry.get("localizations", {}).items():
                if language != "en":
                    # Translation catalogs may carry variations as well as plain string units.
                    def review(value):
                        if isinstance(value, dict):
                            if "stringUnit" in value:
                                value["stringUnit"]["state"] = "needs_review"
                            for child in value.values():
                                review(child)
                    review(translation)
        entry.update(comment=comment(entry_id, blocks[0].text, block), extractionState="manual")
        entry.setdefault("localizations", {})["en"] = {"stringUnit": {"state": "translated", "value": block.text}}
        strings[block.key] = entry
    keys = {block.key for block in blocks}
    for key in list(strings):
        if key.startswith(prefix(entry_id)) and key not in keys:
            del strings[key]
    chapter = {"id": entry_id, "source": str(SOURCES / f"{entry_id}.md"),
               "blocks": [block.record() for block in blocks]}
    if old:
        manifest["chapters"][manifest["chapters"].index(old)] = chapter
    else:
        manifest["chapters"].append(chapter)
    lines = original.splitlines()
    # Only add missing markers; preserve the author's Markdown spelling and layout.
    for block in reversed(blocks):
        if block.key not in marked:
            lines.insert(block.start, f"<!-- marginarium: {block.key} -->")
    canonical = root / chapter["source"]
    canonical.parent.mkdir(parents=True, exist_ok=True)
    canonical.write_text("\n".join(lines) + "\n", encoding="utf-8")
    if catalog != load_json(root / CATALOG):
        write_json(root / CATALOG, catalog, catalog=True)
    write_json(root / MANIFEST, manifest)
    return chapter


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    commands = parser.add_subparsers(dest="command", required=True)
    importing = commands.add_parser("import")
    importing.add_argument("chapter", type=Path)
    importing.add_argument("--id", required=True)
    commands.add_parser("check")
    args = parser.parse_args()
    try:
        if args.command == "import":
            chapter = import_chapter(args.root, args.chapter, args.id)
            print(f"marginarium: imported {chapter['id']} ({len(chapter['blocks'])} blocks)")
        else:
            manifest, values = validate(args.root)
            print(f"marginarium: ok ({len(manifest['chapters'])} chapters, {len(values)} blocks)")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"marginarium: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
