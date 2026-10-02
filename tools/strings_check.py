#!/usr/bin/env python3
"""Keeps the app's string catalog and its sources in step (stdlib only; runs on Linux CI).

    python3 tools/strings_check.py [--root DIR] [--list] [--self-test]

Every user-facing string of the app target is looked up by a key in
`App/PaintByNumber/Resources/Localizable.xcstrings`. A key that is missing there falls back to
English silently, and Xcode (which would extract strings) is not available on CI's Linux job, so
this script reads the Swift sources itself and fails when sources and catalog disagree:

* a literal in a SwiftUI position is missing from the catalog (or interpolates, see below),
* an explicit key's English default differs from the catalog's English value,
* a catalog key is not used by any source,
* a catalog entry is malformed (no comment, wrong placeholders, a plural without one/other, ...),
* `InfoPlist.xcstrings` drifted from the `INFOPLIST_KEY_*` build settings or from the document
  type names in `Config/Info.plist` (the system localizes a `CFBundleTypeName` by looking up its
  English text as the key),
* a string that reads like prose is not routed through any localization form.

Forms scanned (comments and string contents are skipped by a small Swift lexer):

1. SwiftUI literals, whose key is the literal itself (no interpolation: it would need a type
   specifier the script can't know, so interpolated text uses form 2):
   `Text("..")`, `Label`, `Button`, `Toggle`, `Picker`, `Section`, `NavigationLink`,
   `LabeledContent`, `ContentUnavailableView`, `TextField`, `ProgressView`, `Menu`, `ShareLink`,
   `SharePreview`, `Link`, `CommandMenu`, `LocalizedStringKey(..)`, and the modifiers
   `.navigationTitle`, `.navigationSubtitle`, `.help`, `.alert`, `.confirmationDialog`,
   `.accessibilityLabel/Hint/Value`, plus the helper views registered in `WRAPPERS` that forward
   a `LocalizedStringKey` parameter to `Text`. A conditional or concatenation of literals inside
   one of these is an error: write one call per literal.
2. `String(localized: "key", defaultValue: "English \\(x)", comment: "...")` and
   `LocalizedStringResource("key", defaultValue: ...)`: the key is the first argument; the
   catalog's English value must equal `defaultValue` with each interpolation replaced by a
   specifier (`%@` for strings, `%lld` for integers, `%1$@ %2$lld` when there are several).
3. `String(localized: "literal")` without `defaultValue`: the literal is the key, like form 1.

`Text(verbatim:)`, `Text(someString)` and other non-literal arguments are not localized by
SwiftUI and are not scanned: build such strings with form 2 or 3 first.
"""

import argparse
import json
import plistlib
import re
import sys
from pathlib import Path

APP_SOURCES = "App/PaintByNumber"
CATALOG = "App/PaintByNumber/Resources/Localizable.xcstrings"
INFOPLIST_CATALOG = "App/PaintByNumber/Resources/InfoPlist.xcstrings"
PROJECT = "App/PaintByNumber.xcodeproj/project.pbxproj"
INFOPLIST_FILE = "App/Config/Info.plist"

# Developer tooling compiled only into Debug builds: its text is never shown to a user.
DEBUG_ONLY_FILES = {
    "Features/PipelineCheckView.swift",
    "Features/Paint/PaintDemoView.swift",
    "App/DemoMode.swift",
    "App/ShellDemo.swift",
    "Canvas/SyntheticTemplate.swift",
}

# Calls whose first unlabeled string literal is a SwiftUI LocalizedStringKey.
IMPLICIT_CALLS = {
    "Text", "Label", "Button", "Toggle", "Picker", "Section", "NavigationLink", "LabeledContent",
    "ContentUnavailableView", "TextField", "ProgressView", "Menu", "ShareLink", "SharePreview", "Link",
    "CommandMenu", "LocalizedStringKey",
}
IMPLICIT_MODIFIERS = {
    "navigationTitle", "navigationSubtitle", "help", "alert", "confirmationDialog",
    "accessibilityLabel", "accessibilityHint", "accessibilityValue",
}
# Helper views and functions that take a `LocalizedStringKey`: callee -> label of the argument
# ("" for the first unlabeled one). The declaration of each is counted in KEY_TYPE_DECLARATIONS.
WRAPPERS = {
    "section": "",              # GalleryView.section(_:count:content:)
    "SettingSlider": "title",   # TemplatePreviewView
    "SectionTitle": "",         # PhotoSourceView
    "GlassIconButton": "label", # PaintView
}
# How often each file mentions the `LocalizedStringKey` type (a parameter or property of a
# wrapper above). A new wrapper changes a count, which fails the check until WRAPPERS lists it.
KEY_TYPE_DECLARATIONS = {
    "Features/Gallery/GalleryView.swift": 1,
    "Features/Paint/PaintView.swift": 2,
    "Features/Create/TemplatePreviewView.swift": 1,
    "Features/Create/PhotoSourceView.swift": 2,
}
# Calls that never carry user-facing text: logging, assertions, decoding diagnostics, file and
# asset names.
NON_UI_CALLS = {
    "error", "notice", "info", "debug", "warning", "fault", "trace", "critical", "Logger", "assertionFailure",
    "fatalError", "precondition", "preconditionFailure", "assert", "print", "NSPredicate", "appending",
    "UserDefaults", "Color", "Image", "URL", "forResource", "url", "CTFontCreateWithName", "contentsOfDirectory",
    "UIImage", "Bundle", "dataCorruptedError",
}
# Strings that read like prose but are not shown to people: (file relative to the app sources,
# text). Each needs a reason.
ALLOWED_LITERALS = {
    # The PDF's "Creator" metadata names the app; it is not displayed text.
    ("Export/PDFExporter.swift", "Paint by Moonlight"),
    # A label Xcode's GPU debugger shows for a Metal pass.
    ("Canvas/RenderContext.swift", "Outline coverage"),
    # Diagnostics of failed file decoding: logged, never shown (the person sees the recovery screen).
    ("Model/Artwork.swift", "invalid artwork dimensions"),
    ("Model/ArtworkStore.swift", "template decompression"),
}
# Files whose text is shown verbatim in every language: license texts, and credits (names,
# copyright lines and paper citations). Their localizable sentences still go through the forms.
VERBATIM_FILES = {"Features/Settings/License.swift", "Features/Settings/Acknowledgements.swift"}
# Properties of Info.plist that Xcode localizes through InfoPlist.xcstrings.
LOCALIZED_INFOPLIST_KEY = re.compile(r"^(CFBundleDisplayName|CFBundleName|NS\w+UsageDescription)$")

SPECIFIER = re.compile(r"%(?:(\d+)\$)?(?:lld|ld|d|lf|f|@)")
PLACEHOLDER = "\x00"


# ----------------------------------------------------------------------------------------------
# A minimal Swift lexer: identifiers, punctuation and string literals (with interpolations).

class Str:
    """A string literal: `text` has each interpolation replaced by PLACEHOLDER."""

    def __init__(self, text, interpolations, line, multiline):
        self.text = text
        self.interpolations = interpolations
        self.line = line
        self.multiline = multiline

    kind = "str"


class Tok:
    def __init__(self, kind, value, line):
        self.kind = kind
        self.value = value
        self.line = line


ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}


class Lexer:
    def __init__(self, source):
        self.s = source
        self.i = 0
        self.line = 1

    def tokens(self):
        out = []
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c == "\n":
                self.line += 1
                self.i += 1
            elif c.isspace():
                self.i += 1
            elif s.startswith("//", self.i):
                while self.i < len(s) and s[self.i] != "\n":
                    self.i += 1
            elif s.startswith("/*", self.i):
                self.block_comment()
            elif c == '"' or (c == "#" and self.raw_string_ahead()):
                out.append(self.string())
            elif c.isalpha() or c == "_":
                j = self.i
                while j < len(s) and (s[j].isalnum() or s[j] == "_"):
                    j += 1
                out.append(Tok("id", s[self.i:j], self.line))
                self.i = j
            else:
                out.append(Tok("p", c, self.line))
                self.i += 1
        return out

    def block_comment(self):
        s = self.s
        depth = 0
        while self.i < len(s):
            if s.startswith("/*", self.i):
                depth += 1
                self.i += 2
            elif s.startswith("*/", self.i):
                depth -= 1
                self.i += 2
                if depth == 0:
                    return
            else:
                if s[self.i] == "\n":
                    self.line += 1
                self.i += 1

    def raw_string_ahead(self):
        j = self.i
        while j < len(self.s) and self.s[j] == "#":
            j += 1
        return j < len(self.s) and self.s[j] == '"'

    def string(self):
        s = self.s
        start_line = self.line
        hashes = 0
        while s[self.i] == "#":
            hashes += 1
            self.i += 1
        multiline = s.startswith('"""', self.i)
        self.i += 3 if multiline else 1
        closing = '"""' if multiline else '"'
        closing += "#" * hashes
        escape = "\\" + "#" * hashes
        text = []
        interpolations = []
        while True:
            if self.i >= len(s):
                raise ValueError(f"unterminated string literal starting on line {start_line}")
            if s.startswith(closing, self.i):
                self.i += len(closing)
                break
            if s.startswith(escape, self.i):
                self.i += len(escape)
                nxt = s[self.i]
                if nxt == "(":
                    self.i += 1
                    interpolations.append(self.interpolation())
                    text.append(PLACEHOLDER)
                elif nxt == "u" and s.startswith("{", self.i + 1):
                    end = s.index("}", self.i)
                    text.append(chr(int(s[self.i + 2:end], 16)))
                    self.i = end + 1
                elif nxt == "\n":
                    self.line += 1
                    self.i += 1
                else:
                    text.append(ESCAPES.get(nxt, nxt))
                    self.i += 1
                continue
            if s[self.i] == "\n":
                self.line += 1
            text.append(s[self.i])
            self.i += 1
        value = "".join(text)
        if multiline:
            value = dedent_multiline(value)
        return Str(value, interpolations, start_line, multiline)

    def interpolation(self):
        """Skips to the `)` closing an interpolation; returns its source."""
        s = self.s
        begin = self.i
        depth = 1
        while self.i < len(s):
            c = s[self.i]
            if c == '"' or (c == "#" and self.raw_string_ahead()):
                self.string()
                continue
            if s.startswith("//", self.i):
                while self.i < len(s) and s[self.i] != "\n":
                    self.i += 1
                continue
            if s.startswith("/*", self.i):
                self.block_comment()
                continue
            if c == "\n":
                self.line += 1
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    self.i += 1
                    return s[begin:self.i - 1]
            self.i += 1
        raise ValueError("unterminated string interpolation")


def dedent_multiline(value):
    lines = value.split("\n")
    if lines and lines[0] == "":
        lines = lines[1:]
    if not lines:
        return ""
    indent = re.match(r"[ \t]*", lines[-1]).group(0)
    if lines[-1].strip() == "":
        lines = lines[:-1]
    return "\n".join(line[len(indent):] if line.startswith(indent) else line for line in lines)


# ----------------------------------------------------------------------------------------------
# Calls: identifier followed by a parenthesised argument list.

class Call:
    def __init__(self, name, member, qualifier, args, line, enclosing):
        self.name = name              # last identifier before "("
        self.member = member          # preceded by "."
        self.qualifier = qualifier    # identifier before the "." of a type/module path
        self.args = args              # [(label or None, [tokens])]
        self.line = line
        self.enclosing = enclosing    # name of the nearest enclosing call, or None


def find_calls(tokens):
    """All calls in `tokens`, nested ones included, each with its arguments split at top-level commas."""
    calls = []
    closers = {}

    def parse(open_index, name, member, qualifier, enclosing):
        depth = 0
        args = []
        current = []
        i = open_index
        end = None
        while i < len(tokens):
            t = tokens[i]
            if t.kind == "p" and t.value in "([{":
                depth += 1
                if depth > 1:
                    current.append(t)
            elif t.kind == "p" and t.value in ")]}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
                current.append(t)
            elif t.kind == "p" and t.value == "," and depth == 1:
                args.append(current)
                current = []
            else:
                current.append(t)
            i += 1
        if current or args:
            args.append(current)
        labeled = []
        for arg in args:
            if len(arg) >= 2 and arg[0].kind == "id" and arg[1].kind == "p" and arg[1].value == ":":
                labeled.append((arg[0].value, arg[2:]))
            else:
                labeled.append((None, arg))
        return Call(name, member, qualifier, labeled, tokens[open_index - 1].line, enclosing), end

    # Walk tokens keeping a stack of (callee name, index of its closing paren).
    stack = []
    for i, t in enumerate(tokens):
        while stack and stack[-1][1] is not None and i > stack[-1][1]:
            stack.pop()
        if t.kind == "p" and t.value == "(" and i > 0 and tokens[i - 1].kind == "id":
            name = tokens[i - 1].value
            member = i >= 2 and tokens[i - 2].kind == "p" and tokens[i - 2].value == "."
            qualifier = tokens[i - 3].value if member and i >= 3 and tokens[i - 3].kind == "id" else None
            enclosing = stack[-1][0] if stack else None
            call, end = parse(i, name, member, qualifier, enclosing)
            calls.append(call)
            stack.append((name, end))
    return calls


def depth_zero_strings(arg_tokens):
    """String tokens of an argument that are not inside a nested call or collection."""
    depth = 0
    found = []
    for t in arg_tokens:
        if t.kind == "p" and t.value in "([{":
            depth += 1
        elif t.kind == "p" and t.value in ")]}":
            depth -= 1
        elif t.kind == "str" and depth == 0 and re.search(r"[A-Za-z]", t.text):
            found.append(t)
    return found


# ----------------------------------------------------------------------------------------------
# Scanning sources for localization forms.

class Finding:
    def __init__(self, path, line, message):
        self.path, self.line, self.message = path, line, message

    def __str__(self):
        return f"{self.path}:{self.line}: {self.message}"


class Usage:
    """A key the sources look up, where, and (for explicit keys) the English default."""

    def __init__(self, key, path, line, default=None, interpolations=0, comment=None):
        self.key, self.path, self.line = key, path, line
        self.default, self.interpolations, self.comment = default, interpolations, comment


def literal_of(arg_tokens):
    """The Str of an argument that is exactly one string literal, else None."""
    if len(arg_tokens) == 1 and arg_tokens[0].kind == "str":
        return arg_tokens[0]
    return None


def scan_file(rel, source, usages, findings):
    try:
        tokens = Lexer(source).tokens()
    except ValueError as error:
        findings.append(Finding(rel, 0, str(error)))
        return
    consumed = set()   # id()s of Str tokens that belong to a recognised form

    def implicit(call, arg_tokens, what):
        literal = literal_of(arg_tokens)
        if literal is None:
            stray = depth_zero_strings(arg_tokens)
            if stray:
                findings.append(Finding(rel, stray[0].line, (
                    f"{what}: a conditional or concatenation of literals is not extractable; "
                    "write one call per literal (or build the text with String(localized:))")))
                consumed.update(id(t) for t in stray)
            return
        consumed.add(id(literal))
        if literal.interpolations:
            findings.append(Finding(rel, literal.line, (
                f"{what}: \"{shorten(literal.text)}\" interpolates; use "
                'String(localized: "key", defaultValue: "...", comment: "...") with an explicit key')))
        elif "%" in literal.text:
            findings.append(Finding(rel, literal.line, f"{what}: a literal '%' needs an explicit key"))
        else:
            usages.append(Usage(literal.text, rel, literal.line))

    for call in find_calls(tokens):
        positional = [a for a in call.args if a[0] is None]
        labels = {label: arg for label, arg in call.args if label is not None}
        # Translator comments are text for translators, never shown.
        if "comment" in labels:
            consumed.update(id(t) for t in labels["comment"] if t.kind == "str")
        if call.name == "Text" and not call.member and call.args and call.args[0][0] == "verbatim":
            consumed.update(id(t) for t in depth_zero_strings(call.args[0][1]))
        elif call.name == "String" and not call.member and call.args and call.args[0][0] == "localized":
            explicit(rel, call, call.args[0][1], labels, usages, findings, consumed)
        elif call.name == "LocalizedStringResource" and not call.member and positional:
            explicit(rel, call, positional[0][1], labels, usages, findings, consumed)
        elif call.name in IMPLICIT_CALLS and not call.member or (
                call.name in IMPLICIT_CALLS and call.qualifier == "SwiftUI"):
            if call.args and call.args[0][0] is None:
                implicit(call, call.args[0][1], f"{call.name}(...)")
        elif call.name in IMPLICIT_MODIFIERS and call.member:
            if call.args and call.args[0][0] is None:
                implicit(call, call.args[0][1], f".{call.name}(...)")
        elif call.name in WRAPPERS and call.args:
            label = WRAPPERS[call.name]
            if label == "":
                target = call.args[0][1] if call.args[0][0] is None else None
            else:
                target = labels.get(label)
            if target is not None:
                implicit(call, target, f"{call.name}(...)")

    # Prose that no recognised form claims.
    if rel not in VERBATIM_FILES:
        contexts = string_contexts(tokens)
        for t in tokens:
            if t.kind != "str" or id(t) in consumed:
                continue
            if looks_like_prose(t) and contexts.get(id(t)) not in NON_UI_CALLS and (rel, t.text) not in ALLOWED_LITERALS:
                findings.append(Finding(rel, t.line, (
                    f"\"{shorten(t.text)}\" reads like user-facing text but is not localized; "
                    "use String(localized:) / a SwiftUI literal, or add it to ALLOWED_LITERALS with a reason")))


def string_contexts(tokens):
    """Maps each string token to the name of the call it is an argument of (None outside calls)."""
    contexts = {}
    stack = []
    for i, t in enumerate(tokens):
        if t.kind == "p" and t.value in "([{":
            name = tokens[i - 1].value if t.value == "(" and i > 0 and tokens[i - 1].kind == "id" else None
            stack.append(name)
        elif t.kind == "p" and t.value in ")]}":
            if stack:
                stack.pop()
        elif t.kind == "str":
            names = [n for n in stack if n]
            contexts[id(t)] = names[-1] if names else None
    return contexts


def looks_like_prose(literal):
    text = literal.text.replace(PLACEHOLDER, "")
    return bool(re.search(r"\s", text.strip())) and bool(re.search(r"[A-Za-z]{2,}", text)) and not literal.multiline


def explicit(rel, call, key_tokens, labels, usages, findings, consumed):
    """`String(localized: key, defaultValue:, comment:)` and `LocalizedStringResource(key, ...)`."""
    what = f"{call.name}(localized:)" if call.name == "String" else "LocalizedStringResource"
    key = literal_of(key_tokens)
    if key is None:
        findings.append(Finding(rel, call.line, f"{what}: the key must be a string literal"))
        return
    consumed.add(id(key))
    for forbidden in ("table", "bundle", "locale"):
        if forbidden in labels:
            findings.append(Finding(rel, call.line, f"{what}: `{forbidden}:` is not supported (the app uses Localizable.xcstrings in the main bundle)"))
    if key.interpolations:
        findings.append(Finding(rel, key.line, f"{what}: \"{shorten(key.text)}\" interpolates; give it an explicit key and defaultValue"))
        return
    default = labels.get("defaultValue")
    if default is None:
        if "%" in key.text:
            findings.append(Finding(rel, key.line, f"{what}: a literal '%' needs an explicit key"))
        else:
            usages.append(Usage(key.text, rel, key.line))
        return
    default_literal = literal_of(default)
    if default_literal is None:
        findings.append(Finding(rel, call.line, f"{what}: defaultValue must be a string literal"))
        return
    consumed.add(id(default_literal))
    if "comment" not in labels:
        findings.append(Finding(rel, call.line, f"{what}: \"{key.text}\" needs a comment for translators"))
    comment = literal_of(labels["comment"]) if "comment" in labels else None
    usages.append(Usage(key.text, rel, key.line, default_literal.text, len(default_literal.interpolations),
                        comment.text if comment is not None else None))


def shorten(text, limit=60):
    text = text.replace(PLACEHOLDER, "\\(…)").replace("\n", "\\n")
    return text if len(text) <= limit else text[:limit - 1] + "…"


def swift_sources(root):
    base = root / APP_SOURCES
    for path in sorted(base.rglob("*.swift")):
        rel = path.relative_to(base).as_posix()
        if rel not in DEBUG_ONLY_FILES:
            yield rel, path


def scan_sources(sources):
    """sources: {relative path: text}. Returns (usages, findings)."""
    usages, findings = [], []
    for rel, text in sources.items():
        scan_file(rel, text, usages, findings)
        declared = count_key_type_mentions(text)
        expected = KEY_TYPE_DECLARATIONS.get(rel, 0)
        if declared != expected:
            findings.append(Finding(rel, 0, (
                f"mentions LocalizedStringKey/LocalizedStringResource {declared} time(s), expected {expected}: "
                "a helper that forwards a key to Text must be listed in WRAPPERS and counted in KEY_TYPE_DECLARATIONS")))
    return usages, findings


def count_key_type_mentions(text):
    """How often the source names LocalizedStringKey/LocalizedStringResource as a type (constructor
    calls such as `LocalizedStringResource("k")` are scanned as forms instead)."""
    try:
        tokens = Lexer(text).tokens()
    except ValueError:
        return 0
    count = 0
    for i, t in enumerate(tokens):
        if t.kind == "id" and t.value in ("LocalizedStringKey", "LocalizedStringResource"):
            following = tokens[i + 1] if i + 1 < len(tokens) else None
            if not (following is not None and following.kind == "p" and following.value == "("):
                count += 1
    return count


# ----------------------------------------------------------------------------------------------
# The catalog.

def normalize_default(text):
    """A Swift defaultValue (interpolations already PLACEHOLDER) as a comparable string."""
    return text


def normalize_catalog(value):
    return SPECIFIER.sub(PLACEHOLDER, value).replace("%%", "%")


def specifiers(value):
    return [m.group(0) for m in SPECIFIER.finditer(value)]


def check_specifiers(path, key, label, value, expected_count, findings):
    found = specifiers(value)
    if len(found) != expected_count:
        findings.append(Finding(path, 0, f'"{key}" {label}: {len(found)} placeholder(s) in "{value}", the code passes {expected_count}'))
        return
    if expected_count > 1:
        positions = []
        for m in SPECIFIER.finditer(value):
            if m.group(1) is None:
                findings.append(Finding(path, 0, f'"{key}" {label}: use numbered placeholders (%1$@, %2$lld) with several arguments'))
                return
            positions.append(int(m.group(1)))
        if sorted(positions) != list(range(1, expected_count + 1)):
            findings.append(Finding(path, 0, f'"{key}" {label}: placeholders must number 1…{expected_count} once each'))


def check_catalog(catalog, usages, findings, path=CATALOG):
    if catalog.get("sourceLanguage") != "en" or catalog.get("version") != "1.0":
        findings.append(Finding(path, 0, 'sourceLanguage must be "en" and version "1.0"'))
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        findings.append(Finding(path, 0, "no strings"))
        return
    used = {}
    for u in usages:
        used.setdefault(u.key, []).append(u)

    for key, entry in strings.items():
        if not isinstance(entry, dict):
            findings.append(Finding(path, 0, f'"{key}": entry is not an object'))
            continue
        if not entry.get("comment", "").strip():
            findings.append(Finding(path, 0, f'"{key}": needs a comment telling translators where it appears and what the placeholders are'))
        if entry.get("extractionState") != "manual":
            findings.append(Finding(path, 0, f'"{key}": extractionState must be "manual" (Xcode would mark it stale otherwise)'))
        if key not in used:
            findings.append(Finding(path, 0, f'"{key}": not used by any source (remove it, or restore the code that uses it)'))

    for key, uses in used.items():
        entry = strings.get(key)
        first = uses[0]
        if entry is None:
            findings.append(Finding(first.path, first.line, f'"{key}" is missing from {Path(path).name}'))
            continue
        explicit_uses = [u for u in uses if u.default is not None]
        if explicit_uses and len(uses) != len(explicit_uses):
            findings.append(Finding(first.path, first.line, f'"{key}" is used both with and without a defaultValue'))
        for u in explicit_uses[1:]:
            if (u.default, u.interpolations) != (explicit_uses[0].default, explicit_uses[0].interpolations):
                findings.append(Finding(u.path, u.line, f'"{key}" is used with a different defaultValue than at {explicit_uses[0].path}:{explicit_uses[0].line}'))
        en = entry.get("localizations", {}).get("en") if isinstance(entry, dict) else None
        if not explicit_uses:
            if en is not None:
                findings.append(Finding(path, 0, f'"{key}": a literal key is its own English text; drop localizations.en'))
            continue
        default = explicit_uses[0]
        if en is None:
            findings.append(Finding(path, 0, f'"{key}": explicit key needs localizations.en'))
            continue
        check_entry_value(path, key, en, default, findings)


def check_entry_value(path, key, en, default, findings):
    wanted = normalize_default(default.default)
    unit = en.get("stringUnit")
    variations = en.get("variations")
    if unit is not None and variations is None:
        if unit.get("state") != "translated":
            findings.append(Finding(path, 0, f'"{key}": en state must be "translated"'))
        value = unit.get("value", "")
        check_specifiers(path, key, "en", value, default.interpolations, findings)
        if normalize_catalog(value) != wanted:
            findings.append(Finding(path, 0, f'"{key}": English differs from the code\'s defaultValue: "{value}" vs "{shorten(default.default, 200)}"'))
        return
    plural = (variations or {}).get("plural")
    if plural is None or unit is not None:
        findings.append(Finding(path, 0, f'"{key}": en must be a stringUnit or a plural variation'))
        return
    if not {"one", "other"} <= set(plural):
        findings.append(Finding(path, 0, f'"{key}": plural variations need at least "one" and "other"'))
        return
    unknown = set(plural) - {"zero", "one", "two", "few", "many", "other"}
    if unknown:
        findings.append(Finding(path, 0, f'"{key}": unknown plural categories {sorted(unknown)}'))
    for category, variant in plural.items():
        value = variant.get("stringUnit", {}).get("value", "")
        if variant.get("stringUnit", {}).get("state") != "translated":
            findings.append(Finding(path, 0, f'"{key}" {category}: state must be "translated"'))
        check_specifiers(path, key, category, value, default.interpolations, findings)
        if not any(s.endswith("lld") for s in specifiers(value)):
            findings.append(Finding(path, 0, f'"{key}" {category}: a plural form must contain the %lld count'))
    if normalize_catalog(plural["other"]["stringUnit"]["value"]) != wanted:
        findings.append(Finding(path, 0, f'"{key}": the "other" form must equal the code\'s defaultValue: "{plural["other"]["stringUnit"]["value"]}" vs "{shorten(default.default, 200)}"'))


# ----------------------------------------------------------------------------------------------
# InfoPlist.xcstrings against the project's INFOPLIST_KEY_* settings.

def project_infoplist(text):
    """{key: {value, ...}} over every build configuration."""
    found = {}
    for m in re.finditer(r'^\s*INFOPLIST_KEY_(\w+) = (?:"((?:[^"\\]|\\.)*)"|([^;\s]+));', text, re.M):
        key = m.group(1)
        if LOCALIZED_INFOPLIST_KEY.match(key):
            found.setdefault(key, set()).add(m.group(2) if m.group(2) is not None else m.group(3))
    return found


def document_type_names(plist):
    """The `CFBundleTypeName` of every document type Info.plist declares."""
    return {t["CFBundleTypeName"] for t in plist.get("CFBundleDocumentTypes", []) if "CFBundleTypeName" in t}


def check_infoplist(catalog, project_text, findings, path=INFOPLIST_CATALOG, plist=None):
    settings = project_infoplist(project_text)
    strings = catalog.get("strings", {})
    if catalog.get("sourceLanguage") != "en" or catalog.get("version") != "1.0":
        findings.append(Finding(path, 0, 'sourceLanguage must be "en" and version "1.0"'))
    expected = {}
    for key, values in settings.items():
        if len(values) != 1:
            findings.append(Finding(PROJECT, 0, f"INFOPLIST_KEY_{key} differs between build configurations"))
        else:
            expected[key] = next(iter(values))
    # A document type's name is localized under its own English text.
    expected.update({name: name for name in document_type_names(plist or {})})
    for key, english in expected.items():
        entry = strings.get(key)
        if entry is None:
            findings.append(Finding(path, 0, f'"{key}" is set in the project but missing from the catalog'))
            continue
        value = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
        if value != english:
            findings.append(Finding(path, 0, f'"{key}": English "{value}" differs from the project setting "{english}"'))
        if not entry.get("comment", "").strip():
            findings.append(Finding(path, 0, f'"{key}": needs a comment'))
    for key in strings:
        if key not in settings and key not in expected:
            findings.append(Finding(path, 0, f'"{key}": no INFOPLIST_KEY_{key} build setting or document type name uses it'))


# ----------------------------------------------------------------------------------------------

def run(root):
    findings = []
    sources = {rel: path.read_text(encoding="utf-8") for rel, path in swift_sources(root)}
    if not sources:
        return [Finding(APP_SOURCES, 0, "no Swift sources found")], 0, 0
    usages, scan_findings = scan_sources(sources)
    findings += scan_findings
    catalog_path = root / CATALOG
    keys = 0
    if not catalog_path.exists():
        findings.append(Finding(CATALOG, 0, "missing"))
    else:
        try:
            catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            return findings + [Finding(CATALOG, error.lineno, f"invalid JSON: {error.msg}")], 0, 0
        check_catalog(catalog, usages, findings)
        keys = len(catalog.get("strings", {}))
    info_path = root / INFOPLIST_CATALOG
    if not info_path.exists():
        findings.append(Finding(INFOPLIST_CATALOG, 0, "missing"))
    else:
        try:
            check_infoplist(
                json.loads(info_path.read_text(encoding="utf-8")), (root / PROJECT).read_text(encoding="utf-8"), findings,
                plist=plistlib.loads((root / INFOPLIST_FILE).read_bytes()))
        except json.JSONDecodeError as error:
            findings.append(Finding(INFOPLIST_CATALOG, error.lineno, f"invalid JSON: {error.msg}"))
    return findings, keys, len({u.key for u in usages})


def self_test():
    failures = []

    def expect(condition, message):
        if not condition:
            failures.append(message)

    def scan(source, rel="Sample.swift"):
        return scan_sources({rel: source})

    # Lexer: comments, nested interpolation strings, raw and multi-line literals.
    usages, findings = scan('''
        // Text("commented out")
        /* Text("also commented /* nested */ out") */
        struct V: View { var body: some View { Text("Hello") } }
    ''')
    expect([u.key for u in usages] == ["Hello"] and not findings, f"basic Text: {[u.key for u in usages]} {[str(f) for f in findings]}")

    usages, findings = scan('Button(String(localized: "a.b", defaultValue: "Go \\(items.map { "x\\($0)" }.count) now", comment: "c"), role: .destructive) {}')
    expect([(u.key, u.default, u.interpolations) for u in usages] == [("a.b", "Go \x00 now", 1)] and not findings,
           f"nested interpolation: {[(u.key, u.default) for u in usages]} {[str(f) for f in findings]}")

    # Forms: modifiers, SwiftUI.Label, wrappers, plain String(localized:).
    usages, findings = scan('''
        Form {}.navigationTitle("Settings").accessibilityHint("Selects")
        SwiftUI.Label("Haptics", systemImage: "hand")
        SettingSlider(title: "Colors", value: 1)
        let s = String(localized: "Painting")
        Text(verbatim: "7 left")
        Text(model.title)
    ''')
    expect(sorted(u.key for u in usages) == ["Colors", "Haptics", "Painting", "Selects", "Settings"] and not findings,
           f"forms: {sorted(u.key for u in usages)} {[str(f) for f in findings]}")

    # Errors: interpolated literal, conditional literals, missing comment, bad key, prose, '%'.
    _, findings = scan('Text("\\(count) areas")')
    expect(any("interpolates" in f.message for f in findings), "interpolated SwiftUI literal not reported")
    _, findings = scan('Text(flag ? "On" : "Off")')
    expect(any("conditional" in f.message for f in findings), "conditional literals not reported")
    _, findings = scan('let s = String(localized: "k", defaultValue: "v")')
    expect(any("comment" in f.message for f in findings), "missing comment not reported")
    _, findings = scan('let s = String(localized: key)')
    expect(any("literal" in f.message for f in findings), "dynamic key not reported")
    _, findings = scan('let s = "This is shown to people"')
    expect(any("not localized" in f.message for f in findings), "unlocalized prose not reported")
    _, findings = scan('Log.library.error("Opening it failed")')
    expect(not findings, f"log message flagged: {[str(f) for f in findings]}")
    _, findings = scan('Text("100%")')
    expect(any("'%'" in f.message for f in findings), "'%' literal not reported")
    _, findings = scan('struct V { let title: LocalizedStringKey }')
    expect(any("WRAPPERS" in f.message for f in findings), "unregistered LocalizedStringKey wrapper not reported")

    # Catalog checks.
    def catalog(strings):
        return {"sourceLanguage": "en", "version": "1.0", "strings": strings}

    def entry(en=None, plural=None, comment="c"):
        value = {"comment": comment, "extractionState": "manual"}
        if en is not None:
            value["localizations"] = {"en": {"stringUnit": {"state": "translated", "value": en}}}
        if plural is not None:
            value["localizations"] = {"en": {"variations": {"plural": {
                k: {"stringUnit": {"state": "translated", "value": v}} for k, v in plural.items()}}}}
        return value

    def check(strings, source):
        usages, findings = scan(source)
        check_catalog(catalog(strings), usages, findings)
        return [f.message for f in findings]

    expect(check({"Hello": entry()}, 'Text("Hello")') == [], "valid literal entry rejected")
    expect(any("missing" in m for m in check({}, 'Text("Hello")')), "missing key not reported")
    expect(any("not used" in m for m in check({"Hello": entry(), "Gone": entry()}, 'Text("Hello")')), "unused key not reported")
    source = 'String(localized: "k", defaultValue: "\\(n) areas", comment: "c")'
    expect(check({"k": entry(plural={"one": "%lld area", "other": "%lld areas"})}, source) == [], "valid plural rejected")
    expect(any("must equal" in m for m in check({"k": entry(plural={"one": "%lld area", "other": "%lld lots"})}, source)),
           "English drift not reported")
    expect(any("one" in m for m in check({"k": entry(plural={"other": "%lld areas"})}, source)), "plural without one not reported")
    expect(any("placeholder" in m for m in check({"k": entry(en="areas")}, source)), "placeholder mismatch not reported")
    two = 'String(localized: "k", defaultValue: "\\(a) of \\(b)", comment: "c")'
    expect(check({"k": entry(en="%1$lld of %2$lld")}, two) == [], "valid positional rejected")
    expect(any("numbered" in m for m in check({"k": entry(en="%lld of %lld")}, two)), "unnumbered placeholders not reported")
    expect(any("comment" in m for m in check({"Hello": entry(comment="")}, 'Text("Hello")')), "empty comment not reported")

    # InfoPlist.
    project = 'INFOPLIST_KEY_CFBundleDisplayName = "App";\nINFOPLIST_KEY_NSCameraUsageDescription = "Why.";\nINFOPLIST_KEY_UILaunchScreen_Generation = YES;'
    findings = []
    check_infoplist(catalog({"CFBundleDisplayName": entry("App"), "NSCameraUsageDescription": entry("Why.")}), project, findings)
    expect(not findings, f"valid Info.plist catalog rejected: {[str(f) for f in findings]}")
    findings = []
    check_infoplist(catalog({"CFBundleDisplayName": entry("Other")}), project, findings)
    expect(len(findings) >= 2, "Info.plist drift not reported")
    plist = {"CFBundleDocumentTypes": [{"CFBundleTypeName": "Image"}]}
    base = {"CFBundleDisplayName": entry("App"), "NSCameraUsageDescription": entry("Why.")}
    findings = []
    check_infoplist(catalog({**base, "Image": entry("Image")}), project, findings, plist=plist)
    expect(not findings, f"valid document type name rejected: {[str(f) for f in findings]}")
    findings = []
    check_infoplist(catalog(base), project, findings, plist=plist)
    expect(any("Image" in str(f) and "missing" in str(f) for f in findings), "unlocalized document type name not reported")
    findings = []
    check_infoplist(catalog({**base, "Image": entry("Picture")}), project, findings, plist=plist)
    expect(any("differs" in str(f) for f in findings), "document type name drift not reported")
    findings = []
    check_infoplist(catalog({**base, "Image": entry("Image")}), project, findings)
    expect(any("no INFOPLIST_KEY_Image" in str(f) for f in findings), "stale document type entry not reported")

    for failure in failures:
        print("self-test FAILED:", failure)
    if not failures:
        print("self-test passed")
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--root", default=Path(__file__).resolve().parent.parent, type=Path, help="repository root")
    parser.add_argument("--self-test", action="store_true", help="check the checker against synthetic sources")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    findings, keys, used = run(args.root)
    for finding in findings:
        print(finding)
    if findings:
        print(f"strings_check: {len(findings)} problem(s)")
        return 1
    print(f"strings_check: ok ({keys} catalog entries, {used} keys used by the sources)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
