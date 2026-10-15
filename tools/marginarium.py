#!/usr/bin/env python3
"""Import approved Marginarium Markdown without changing the identity of other blocks.

    python3 tools/marginarium.py import chapter.md --id lampBrush
    python3 tools/marginarium.py from-docs view.json --out chapter.md
    python3 tools/marginarium.py check
    python3 tools/marginarium.py check --docs view.json --id marginarium
    python3 -m unittest discover -s tools/tests -p 'test_marginarium.py'

Stdlib only. The import writes docs/marginarium/<id>.md (the editable source, NOT bundled),
Resources/marginarium.json (ordered chapters/blocks, version 1), and Localizable.xcstrings.
--root DIR selects a repository, including a temporary one for tests. Importing does not
constitute editorial approval: only import text Paul has approved.

Format: a # title, a subtitle paragraph, then ATX headings (# through ######), paragraphs,
> quotes (including multiple paragraphs), bullet items (-, * or +; two-space nesting),
ordered items (1., 2., ...), two-column pipe tables with a header/separator row, and
standalone ![VoiceOver description](asset-name) images from Assets.xcassets, or
![VoiceOver description](pet:pip) pets. Each list item
is a block. Continuation lines in an item are indented two spaces beyond its indent. Quotes
contain paragraphs, not nested block structures. Emphasis, strong emphasis, inline code and
inline links stay as Markdown in catalog values for Foundation's AttributedString parser.
Line breaks and inline spelling are preserved; only block syntax is removed. Unsupported
block syntax fails with a line number rather than silently losing structure. Images require
a nonempty plain-text description and bundled art; no remote images are fetched. Pets are Pip,
Colophon, or a v2 atlas named Resources/pet-<id>.webp (lowercase alphanumeric/hyphen id).
Atlas pets idle and wave on tap. The app validates the 1536 × 2288 sheet before slicing it.

An *In the margin* paragraph followed by ordered items becomes marginHeading and marginNote
blocks. Notes keep their numbering and full signatures; speaker is the italic name after the
last "— ", even when prose follows it (a plain signature at the end is also accepted);
speakers lists every name signed that way in the note, in order, because one note can carry
several voices and the reader shows each guardian's drawing beside it.

A note says which words of the story it is about with an <!-- anchor: phrase --> line just
before it (beside its marker); several phrases are separated by " | ", for a note whose voices
answer different words. Each phrase is plain text (no Markdown, pipes or backslashes) found
exactly once in the paragraphs, quotes and list items between the previous margin group and
this one. The manifest records the block holding each phrase (anchorBlocks), and the phrases go
to the catalog under the note's key plus ".anchor", so a translation can move them with its
words. The reader highlights them; a note without an anchor stays a card.
Tables become tableCell blocks in row-major order, with row/column (zero-based) and header
metadata. Each cell has its own catalog key and an inline marker inside the pipe cell.
The reader groups these cells into responsive tables and
margin headings/notes into asides. This keeps localization and stable identity per text unit.

from-docs converts data.xml in a Docs JSON reply, ignoring ids/hashes and dropping only the
paragraph containing both date and mention chips. It rejects unsupported structure. Adjacent
runs with the same styling are merged (a name split across italic runs stays one name).
check --docs additionally compares the imported chapter against that original Docs reply.

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

check is read-only: source order, kind, key and rendering metadata must
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
import xml.etree.ElementTree as ET

CATALOG = Path("App/PaintByNumber/Resources/Localizable.xcstrings")
MANIFEST = Path("App/PaintByNumber/Resources/marginarium.json")
SOURCES = Path("docs/marginarium")
ASSETS = Path("App/PaintByNumber/Resources/Assets.xcassets")
# Pip's and Colophon's frames: a catalog of their own, which Release builds leave out.
MARGINARIUM_ASSETS = Path("App/PaintByNumber/Resources/Marginarium.xcassets")
RESOURCES = ASSETS.parent
# These shipped imageset pets keep their existing playback plans in Marginarium.swift.
PET_IMAGESETS = {"pip": {"idle": 6, "wave": 4}, "colophon": {"idle": 6, "review": 6}}
MARKER = re.compile(r"<!-- marginarium: ([A-Za-z0-9_.-]+) -->")
ANCHOR = re.compile(r"<!-- anchor: (.+) -->")
# The kinds of story block whose words a margin note can point at.
ANCHORABLE = ("paragraph", "quote", "bullet", "ordered")
HEADING = re.compile(r"(#{1,6}) (.+)")
BULLET = re.compile(r"( *)([-+*]) (.+)")
ORDERED = re.compile(r"( *)(\d+)\. (.+)")
IMAGE = re.compile(r"!\[([^\[\]\n]+)\]\((pet:[a-z0-9]+(?:-[a-z0-9]+)*|[A-Za-z0-9][A-Za-z0-9_.-]*)\)")
ENTRY_ID = re.compile(r"[A-Za-z][A-Za-z0-9]*")


@dataclass
class Block:
    kind: str
    text: str
    start: int
    key: str | None = None
    metadata: dict = field(default_factory=dict)
    # Tables put each marker inside its cell, rather than on a separate line.
    column_offset: int | None = None
    # A margin note's phrases of the story (its anchor line), linked to their blocks by link_anchors.
    anchors: list = field(default_factory=list)

    def record(self):
        return {"kind": self.kind, "key": self.key, **self.metadata}


def parse(source):
    """Parse the supported Markdown block grammar; offsets allow adding markers losslessly."""
    lines = source.splitlines()
    blocks = []
    pending = None
    pending_anchors = None
    i = 0

    def fail(message):
        raise ValueError(f"line {i + 1}: {message}")

    def special(line):
        return (MARKER.fullmatch(line) or HEADING.fullmatch(line) or BULLET.fullmatch(line)
                or ORDERED.fullmatch(line) or line.startswith((">", "![", "<!--", "|")))

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
        if anchor := ANCHOR.fullmatch(line):
            if pending_anchors is not None:
                fail("two anchor lines before one block")
            pending_anchors = anchor[1].split(" | ")
            if any(not phrase.strip() or phrase != phrase.strip() or re.search(r"[*_`\[\]\\<>|]", phrase)
                   for phrase in pending_anchors):
                fail("anchor phrases are plain text without Markdown, separated by \" | \"")
            i += 1
            continue
        start = i
        metadata = {}
        if line.startswith("|"):
            if pending or pending_anchors is not None:
                fail("table markers belong inside their cells, and tables take no anchors")
            row = 0
            while i < len(lines) and lines[i].startswith("|"):
                cells = table_cells(lines[i])
                if len(cells) != 2:
                    fail("tables need exactly two columns")
                for column, (content, offset) in enumerate(cells):
                    key = None
                    if marker := MARKER.match(content):
                        key = marker[1]
                        content = content[marker.end():].lstrip(" ")
                    if not content.strip() or MARKER.search(content):
                        fail("table cells need nonempty text and at most one leading marker")
                    blocks.append(Block("tableCell", content, i, key,
                                        {"row": row, "column": column, "header": row == 0}, offset))
                i += 1
                if row == 0:
                    if i >= len(lines) or not re.fullmatch(r"\| *:?-{3,}:? *\| *:?-{3,}:? *\|", lines[i]):
                        fail("table needs a two-column header separator")
                    i += 1
                row += 1
            if row < 2:
                fail("table needs a body row")
            continue
        elif match := HEADING.fullmatch(line):
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
        elif match := BULLET.fullmatch(line) or ORDERED.fullmatch(line):
            kind = "ordered" if match[2].isdigit() else "bullet"
            indent = len(match[1])
            if indent % 2:
                fail("bullet nesting uses two spaces per level")
            metadata["depth"] = indent // 2
            if kind == "ordered":
                metadata["number"] = int(match[2])
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
        blocks.append(Block(kind, text, start, pending, metadata, anchors=pending_anchors or []))
        pending = None
        pending_anchors = None
    if pending or pending_anchors is not None:
        fail("marker or anchor without a block")
    if len(blocks) < 2 or blocks[0].kind != "heading" or blocks[0].metadata["level"] != 1:
        raise ValueError("a chapter starts with a # title and a subtitle paragraph")
    if blocks[1].kind != "paragraph":
        raise ValueError("the block after the title must be a subtitle paragraph")
    blocks[0].kind, blocks[0].metadata = "title", {}
    blocks[1].kind = "subtitle"
    in_margin = False
    for index, block in enumerate(blocks):
        if (block.kind == "paragraph" and block.text == "*In the margin*"
                and index + 1 < len(blocks) and blocks[index + 1].kind == "ordered"):
            block.kind = "marginHeading"
            in_margin = True
        elif in_margin and block.kind == "ordered":
            if block.metadata["depth"] != 0:
                raise ValueError(f"line {block.start + 1}: margin notes cannot be nested")
            block.kind = "marginNote"
            signature = block.text.rsplit("— ", 1)[-1]
            name = re.match(r"\*([^*]+)\*", signature)
            if name is None:
                name = re.fullmatch(r"([\w ’'-]+)", signature)
            if "— " not in block.text or name is None:
                raise ValueError(f"line {block.start + 1}: margin note needs a final signature")
            block.metadata["speaker"] = unescape(name[1])
            # Every guardian who signed the note, in order, for the pets shown beside it.
            signed = [unescape(n) for n in re.findall(r"— \*([^*]+)\*", block.text)]
            if block.metadata["speaker"] not in signed[-1:]:
                signed.append(block.metadata["speaker"])
            block.metadata["speakers"] = list(dict.fromkeys(signed))
        else:
            in_margin = False
    for block in blocks:
        if block.anchors and block.kind != "marginNote":
            raise ValueError(f"line {block.start + 1}: only margin notes have anchors")
    return blocks


def anchor_key(note_key):
    return f"{note_key}.anchor"


def link_anchors(blocks):
    """Record, on each anchored note, the story block holding each of its phrases: the one
    paragraph, quote or list item since the previous margin group that contains it, once,
    as the reader shows it (emphasis, code and link syntax removed)."""
    story = []
    previous = None
    for block in blocks:
        if block.kind == "marginNote":
            block.metadata.pop("anchorBlocks", None)
            linked = []
            for phrase in block.anchors:
                found = [b for b in story for _ in range(rendered(b.text).count(phrase))]
                if len(found) != 1:
                    raise ValueError(f"line {block.start + 1}: anchor {phrase!r} must appear exactly once "
                                     f"in the story before its margin group, not {len(found)} times")
                linked.append(found[0].key)
            if linked:
                block.metadata["anchorBlocks"] = linked
        elif block.kind != "marginHeading":
            if previous == "marginNote":
                story = []
            if block.kind in ANCHORABLE:
                story.append(block)
        previous = block.kind


def rendered(text):
    """A block's words as the reader shows them, near enough to count an anchor's occurrences."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    return unescape(re.sub(r"(?<!\\)(\*\*|\*|`)", "", text))


def table_cells(line):
    """Split only unescaped pipes; offsets point to each cell's first non-space character."""
    pipes = []
    for index, char in enumerate(line):
        if char == "|" and (len(line[:index]) - len(line[:index].rstrip("\\"))) % 2 == 0:
            pipes.append(index)
    if not pipes or pipes[0] != 0 or pipes[-1] != len(line) - 1:
        raise ValueError("table rows must start and end with unescaped pipes")
    return [(line[left + 1:right].strip(" "), left + 1 + len(line[left + 1:right])
             - len(line[left + 1:right].lstrip(" "))) for left, right in zip(pipes, pipes[1:])]


def unescape(text):
    return re.sub(r"\\([\\`*_{}\[\]()#+.!|<>~-])", r"\1", text)


def docs_inline(element):
    """Serialize styled runs, coalescing editing boundaries that are not prose boundaries."""
    runs = []

    def append(text, styles):
        if text:
            if runs and runs[-1][1] == styles:
                runs[-1] = (runs[-1][0] + text, styles)
            else:
                runs.append((text, styles))

    def visit(node, styles=()):
        if node.tag in ("italic", "bold", "code"):
            styles += (node.tag,)
        elif node.tag not in ("paragraph", "text"):
            raise ValueError(f"unsupported Docs inline element: {node.tag}")
        append(node.text, styles)
        for child in node:
            visit(child, styles)
            append(child.tail, styles)

    def render(parts):
        result = []
        i = 0
        while i < len(parts):
            text, styles = parts[i]
            if not styles:
                result.append(re.sub(r"([\\`*_\[\]|<>#~])", r"\\\1", text))
                i += 1
                continue
            style = styles[0]
            inside = []
            while i < len(parts) and parts[i][1] and parts[i][1][0] == style:
                inside.append((parts[i][0], parts[i][1][1:]))
                i += 1
            if style == "code":
                if any(rest for _, rest in inside):
                    raise ValueError("Docs code cannot contain other styling")
                value = "".join(t for t, _ in inside)
                if "|" in value or "\n" in value:
                    raise ValueError("Docs inline code with pipes or newlines is unsupported")
                ticks = "`" * (1 + max((len(m[0]) for m in re.finditer(r"`+", value)), default=0))
                pad = " " if value.startswith(("`", " ")) or value.endswith(("`", " ")) else ""
                result.append(ticks + pad + value + pad + ticks)
            else:
                value = render(inside)
                # CommonMark emphasis delimiters cannot sit inside the span's edge spaces.
                core = value.strip()
                lead = value[:len(value) - len(value.lstrip())]
                tail = value[len(value.rstrip()):]
                mark = "*" if style == "italic" else "**"
                result.append(lead + mark + core + mark + tail if core else value)
        return "".join(result)

    visit(element)
    return render(runs)


def from_docs(reply):
    """Convert only supported Docs prose, failing rather than silently discarding content."""
    root = ET.fromstring(reply["data"]["xml"])
    if root.tag != "doc":
        raise ValueError("Docs XML must have a doc root")
    parts = []

    def paragraph(node):
        if node.tag != "paragraph" or node.get("heading"):
            raise ValueError("Docs list items and table cells need a single plain paragraph")
        return docs_inline(node)

    for node in root:
        if node.tag == "paragraph":
            if node.find("date") is not None and node.find("mention") is not None:
                continue
            text = docs_inline(node)
            if heading := node.get("heading"):
                if heading not in {str(n) for n in range(1, 7)}:
                    raise ValueError(f"unsupported Docs heading: {heading}")
                text = "#" * int(heading) + " " + text
            parts.append(text)
        elif node.tag == "list":
            kind = node.get("kind")
            if kind not in ("bullet", "ordered"):
                raise ValueError(f"unsupported Docs list kind: {kind}")
            items = []
            for index, item in enumerate(node, 1):
                if item.tag != "listItem" or len(item) != 1:
                    raise ValueError("Docs list items need a single paragraph")
                prefix = "- " if kind == "bullet" else f"{index}. "
                items.append(prefix + paragraph(item[0]).replace("\n", "\n  "))
            parts.append("\n".join(items))
        elif node.tag == "table":
            rows = []
            for index, row in enumerate(node):
                if row.tag != "row" or len(row) != 2:
                    raise ValueError("Docs tables need two-column rows")
                cells = []
                for cell in row:
                    if (cell.tag != "cell" or len(cell) != 1
                            or (cell.get("header") == "true") != (index == 0)):
                        raise ValueError("Docs tables need a header row and single-paragraph cells")
                    value = paragraph(cell[0])
                    if "\n" in value:
                        raise ValueError("Docs table cells with newlines are unsupported")
                    cells.append(value)
                rows.append("| " + " | ".join(cells) + " |")
                if index == 0:
                    rows.append("| --- | --- |")
            parts.append("\n".join(rows))
        else:
            raise ValueError(f"unsupported Docs block: {node.tag}")
    source = "\n\n".join(parts) + "\n"
    parse(source)
    return source


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
        matches = [match for catalog in (ASSETS, MARGINARIUM_ASSETS)
                   for match in (root / catalog).rglob(f"{block.metadata['image']}.imageset/Contents.json")]
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
        link_anchors(blocks)
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
            if block.anchors:
                key, phrases = anchor_key(block.key), " | ".join(block.anchors)
                entry = catalog.get(key, {})
                if english(entry) != phrases:
                    raise ValueError(f"{key}: catalog English differs from the note's anchor line")
                if (entry.get("extractionState") != "manual"
                        or entry.get("comment") != anchor_comment(chapter["id"], blocks[0].text)):
                    raise ValueError(f"{key}: needs manual extraction and the anchor's translator comment")
                used[key] = phrases
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


def anchor_comment(entry_id, title):
    return (f"The Marginarium: {title} ({entry_id}); the words of the story a margin note is about, "
            "highlighted in the reader. Keep each phrase, separated by \" | \", word for word as it "
            "appears once in the translated story before the note's margin group.")


def store(strings, key, value, comment_text):
    """Write one manual English entry; a changed English value asks translations for review."""
    existing = strings.get(key)
    entry = deepcopy(existing) if existing else {}
    if existing and english(existing) != value:
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
    entry.update(comment=comment_text, extractionState="manual")
    entry.setdefault("localizations", {})["en"] = {"stringUnit": {"state": "translated", "value": value}}
    strings[key] = entry


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
        store(strings, block.key, block.text, comment(entry_id, blocks[0].text, block))
    link_anchors(blocks)
    for block in blocks:
        if block.anchors:
            store(strings, anchor_key(block.key), " | ".join(block.anchors), anchor_comment(entry_id, blocks[0].text))
    keys = {block.key for block in blocks} | {anchor_key(block.key) for block in blocks if block.anchors}
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
            marker = f"<!-- marginarium: {block.key} -->"
            if block.column_offset is None:
                lines.insert(block.start, marker)
            else:
                line = lines[block.start]
                offset = block.column_offset
                lines[block.start] = line[:offset] + marker + " " + line[offset:]
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
    converting = commands.add_parser("from-docs")
    converting.add_argument("view", type=Path)
    converting.add_argument("--out", type=Path, help="Markdown output (default: stdout)")
    checking = commands.add_parser("check")
    checking.add_argument("--docs", type=Path, help="also compare with the original Docs JSON reply")
    checking.add_argument("--id", help="chapter to compare with --docs")
    args = parser.parse_args()
    try:
        if args.command == "from-docs":
            source = from_docs(load_json(args.view))
            if args.out:
                args.out.write_text(source, encoding="utf-8")
            else:
                print(source, end="")
        elif args.command == "import":
            chapter = import_chapter(args.root, args.chapter, args.id)
            print(f"marginarium: imported {chapter['id']} ({len(chapter['blocks'])} blocks)")
        else:
            manifest, values = validate(args.root)
            if args.docs:
                if not args.id:
                    raise ValueError("--docs needs --id")
                chapter = next((c for c in manifest["chapters"] if c["id"] == args.id), None)
                if chapter is None:
                    raise ValueError(f"chapter not found: {args.id}")
                actual = parse((args.root / chapter["source"]).read_text(encoding="utf-8"))
                expected = parse(from_docs(load_json(args.docs)))
                signature = lambda b: (b.kind, b.text, b.metadata)
                if list(map(signature, actual)) != list(map(signature, expected)):
                    raise ValueError(f"{args.id}: source differs from Docs prose")
            print(f"marginarium: ok ({len(manifest['chapters'])} chapters, {len(values)} blocks)")
    except (OSError, ValueError, KeyError, TypeError, ET.ParseError) as error:
        print(f"marginarium: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
