#!/usr/bin/env python3
"""The app's translations: what each language still needs, and putting new ones in (stdlib only).

    tools/l10n.py status                       counts per catalog and language
    tools/l10n.py todo <lang> [--all] [--out F] what <lang> lacks or has stale, as JSON to translate
    tools/l10n.py apply <lang> <file.json> [--dry-run]  checks each translation, writes it into its catalog
    tools/l10n.py check                        every translation well formed (strings_check.py runs it)

The string catalogs are English first (`tools/strings_check.py` keeps them in step with the
sources); every language in `LANGUAGES` is a translation of them, written straight into the
catalogs as `localizations.<lang>`. A key with no translation shows its English, so a missing one
never breaks anything, but it does leave a German painter reading English: a change that adds or
rewords a string runs `todo` for each language and `apply`s the translations in the same change.

`todo` writes a list of {"catalog", "key", "english", "comment", "plural"[, "was"]}: "english" is
the text (for a plural, its forms by CLDR category), "was" the English the stale translation was
made from. `apply` reads a list of {"catalog", "key", "value"}, a string or, for a plural, its
forms by the language's categories (`PLURALS`). A translation is refused, and nothing of the file
written, when its placeholders differ from the English (same arguments, same types; `%@` may
become `%1$@` to move), a plural lacks a category the language needs, or the Tool Guide's
`(guide:…)` links differ.

Stale: `tools/l10n/translated-from.json` records, per key and language, a hash of the English the
translation was made from; when the English changes, `todo` offers the key again. Catalog layout
is Xcode's (each file's own separators), so a diff is only the translations.

The App Store listing's translations are `ci/store-listing.json`'s `locales` (`ci/store_listing.py`).
"""

import argparse
import hashlib
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The languages the app speaks besides English. A new one: add it here and to the project's
# knownRegions, then `todo`/`apply` it whole.
LANGUAGES = ("de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans", "zh-Hant")

# CLDR plural categories for integers, as iOS picks them. "many" (es, fr, it, pt: a million and
# up) is optional: without it iOS uses "other".
PLURALS = {
    "de": ("one", "other"), "nl": ("one", "other"),
    "es": ("one", "many", "other"), "fr": ("one", "many", "other"),
    "it": ("one", "many", "other"), "pt-BR": ("one", "many", "other"),
    "ja": ("other",), "ko": ("other",), "zh-Hans": ("other",), "zh-Hant": ("other",),
}
OPTIONAL_PLURALS = {"many"}

# name: (path, the separator Xcode's layout of that file uses)
CATALOGS = OrderedDict([
    ("app", ("App/PaintByNumber/Resources/Localizable.xcstrings", " : ")),
    ("mosaic", ("App/RavennaResources/Localizable.xcstrings", ": ")),
    ("infoplist", ("App/PaintByNumber/Resources/InfoPlist.xcstrings", " : ")),
    ("widgets", ("App/MoonlightWidgets/Localizable.xcstrings", " : ")),
    ("stickers", ("App/MoonlightStickers/Localizable.xcstrings", " : ")),
])
SOURCES = "tools/l10n/translated-from.json"

SPECIFIER = re.compile(r"%(?:(\d+)\$)?(lld|ld|d|lf|f|@)")
# Any conversion String(format:) would read, to catch one SPECIFIER doesn't allow.
ANY_PERCENT = re.compile(r"%%|%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[a-zA-Z@]|%")
GUIDE_LINK = re.compile(r"\]\((guide:[^)]*)\)")


def load(name, root=ROOT):
    path, _ = CATALOGS[name]
    return json.loads((root / path).read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)


def save(name, catalog, root=ROOT):
    path, sep = CATALOGS[name]
    text = json.dumps(catalog, indent=2, separators=(",", sep), ensure_ascii=False) + "\n"
    (root / path).write_text(text, encoding="utf-8")


def read_unit(loc):
    """A localization as text, {category: text} for a plural, or None where it isn't one of those."""
    if not isinstance(loc, dict):
        return None
    if "variations" in loc:
        plural = loc["variations"].get("plural") if isinstance(loc["variations"], dict) else None
        if not isinstance(plural, dict) or set(loc["variations"]) != {"plural"}:
            return None
        forms = OrderedDict((c, (v.get("stringUnit") or {}).get("value") if isinstance(v, dict) else None)
                            for c, v in plural.items())
        return None if any(not isinstance(t, str) for t in forms.values()) else forms
    value = (loc.get("stringUnit") or {}).get("value")
    return value if isinstance(value, str) else None


def english(key, entry):
    """The English: a string, or {category: form} for a plural."""
    en = entry.get("localizations", {}).get("en")
    if en is None:
        return key  # a literal key is its own English
    return read_unit(en)


def fingerprint(text):
    return hashlib.sha1(json.dumps(text, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:10]


def load_sources(root=ROOT):
    path = root / SOURCES
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def save_sources(sources, root=ROOT):
    # One key a line, so a diff reads.
    lines = ["{"]
    names = [n for n in CATALOGS if n in sources]
    for i, name in enumerate(names):
        lines.append(f"  {json.dumps(name)}: {{")
        keys = sorted(sources[name])
        for j, key in enumerate(keys):
            langs = OrderedDict(sorted(sources[name][key].items()))
            tail = "," if j < len(keys) - 1 else ""
            lines.append(f"    {json.dumps(key, ensure_ascii=False)}: {json.dumps(langs, separators=(',', ':'))}{tail}")
        lines.append("  }" + ("," if i < len(names) - 1 else ""))
    lines.append("}")
    path = root / SOURCES
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def translation(entry, lang):
    """The translation as `apply` takes it: a string, {category: form}, or None."""
    return read_unit(entry.get("localizations", {}).get(lang))


def needs_review(entry, lang):
    """Xcode marks a translation so when its English changes in Xcode's editor."""
    loc = entry.get("localizations", {}).get(lang) or {}
    units = [loc.get("stringUnit")] if "stringUnit" in loc else [
        v.get("stringUnit") for v in (loc.get("variations") or {}).get("plural", {}).values() if isinstance(v, dict)]
    return any(isinstance(u, dict) and u.get("state") == "needs_review" for u in units)


# ----------------------------------------------------------------------------------------------
# Checking one translation.

def arguments(text):
    """{argument index: type} of a format string, or a message when it can't be read."""
    found, nextIndex = {}, 1
    numbered = unnumbered = False
    for m in ANY_PERCENT.finditer(text):
        if m.group(0) != "%%" and not SPECIFIER.fullmatch(m.group(0)):
            return f"“{m.group(0)}” is not a placeholder the app passes (write %% for a percent sign)"
    for m in SPECIFIER.finditer(text):
        kind = m.group(2)
        if m.group(1):
            numbered, index = True, int(m.group(1))
        else:
            unnumbered, index = True, nextIndex
            nextIndex += 1
        if found.get(index, kind) != kind:
            return f"argument {index} is used as two types"
        found[index] = kind
    if numbered and unnumbered:
        return "mixes numbered and unnumbered placeholders"
    return found


def problems(english_text, value, lang):
    """What is wrong with one translation (a list of messages, empty when it is fine)."""
    found = []
    if isinstance(english_text, dict):
        forms = value if isinstance(value, dict) else {"other": value}
        if not isinstance(value, dict) and PLURALS[lang] != ("other",):
            return [f"needs plural forms {list(PLURALS[lang])}"]
        allowed = set(PLURALS[lang])
        needed = allowed - OPTIONAL_PLURALS
        if set(forms) - allowed:
            found.append(f"categories {sorted(set(forms) - allowed)} are not {lang}'s ({sorted(allowed)})")
        if needed - set(forms):
            found.append(f"lacks plural categories {sorted(needed - set(forms))}")
        reference = english_text["other"]
        for category, form in forms.items():
            found += [f"{category}: {m}" for m in problems(reference, form, lang)]
        return found
    if not isinstance(value, str) or not value.strip():
        return ["is empty"]
    want, got = arguments(english_text), arguments(value)
    if isinstance(got, str):
        found.append(got)
    elif want != got:
        found.append(f"placeholders {placeholders(value)} differ from the English {placeholders(english_text)}")
    if sorted(GUIDE_LINK.findall(english_text)) != sorted(GUIDE_LINK.findall(value)):
        found.append("its (guide:…) links differ from the English")
    if value != value.strip() and english_text == english_text.strip():
        found.append("has leading or trailing whitespace the English hasn't")
    return found


def placeholders(text):
    return [m.group(0) for m in SPECIFIER.finditer(text)]


def unit(text):
    return OrderedDict([("stringUnit", OrderedDict([("state", "translated"), ("value", text)]))])


def localization(value):
    if isinstance(value, dict):
        return OrderedDict([("variations", OrderedDict([("plural", OrderedDict(
            (c, unit(value[c])) for c in ("zero", "one", "two", "few", "many", "other") if c in value))]))])
    return unit(value)


# ----------------------------------------------------------------------------------------------
# Commands.

def entries(name, root=ROOT):
    catalog = load(name, root)
    return catalog, catalog["strings"]


def state(name, key, entry, lang, sources):
    """"done", "missing" or "stale"."""
    if translation(entry, lang) is None:
        return "missing"
    if needs_review(entry, lang):
        return "stale"
    made_from = sources.get(name, {}).get(key, {}).get(lang)
    if made_from is not None and made_from != fingerprint(english(key, entry)):
        return "stale"
    return "done"


def status(root=ROOT):
    sources = load_sources(root)
    rows = []
    for name in CATALOGS:
        _, strings = entries(name, root)
        for lang in LANGUAGES:
            counts = {"done": 0, "missing": 0, "stale": 0}
            for key, entry in strings.items():
                if entry.get("shouldTranslate") is False:
                    continue
                counts[state(name, key, entry, lang, sources)] += 1
            rows.append((name, lang, counts))
    return rows


def todo(lang, everything=False, root=ROOT):
    sources = load_sources(root)
    out = []
    for name in CATALOGS:
        _, strings = entries(name, root)
        for key, entry in strings.items():
            if entry.get("shouldTranslate") is False:
                continue
            s = state(name, key, entry, lang, sources)
            if s == "done" and not everything:
                continue
            text = english(key, entry)
            item = OrderedDict([("catalog", name), ("key", key), ("english", text),
                                ("comment", entry.get("comment", "")), ("plural", isinstance(text, dict))])
            if s == "stale" or (everything and s == "done"):
                item["was"] = translation(entry, lang)
            out.append(item)
    return out


def apply(lang, items, root=ROOT, dry_run=False):
    if lang not in LANGUAGES:
        return [f"{lang} is not one of {', '.join(LANGUAGES)}"]
    catalogs = {name: load(name, root) for name in CATALOGS}
    sources = load_sources(root)
    errors = []
    for item in items:
        name, key, value = item.get("catalog"), item.get("key"), item.get("value")
        if name not in catalogs or key not in catalogs[name]["strings"]:
            errors.append(f"{name}/{key}: no such key")
            continue
        entry = catalogs[name]["strings"][key]
        text = english(key, entry)
        found = problems(text, value, lang)
        if found:
            errors += [f"{name}/{key}: {m}" for m in found]
            continue
        locs = entry.setdefault("localizations", OrderedDict())
        locs[lang] = localization(value)
        entry["localizations"] = OrderedDict(sorted(locs.items()))
        sources.setdefault(name, {}).setdefault(key, {})[lang] = fingerprint(text)
    if errors or dry_run:
        return errors
    for name, catalog in catalogs.items():
        save(name, catalog, root)
    save_sources(sources, root)
    return []


def check(root=ROOT):
    """(errors, summary): every translation in the catalogs well formed, and how many are missing
    or stale (which only shows English: not an error)."""
    errors = []
    sources = load_sources(root)
    for name, (path, _) in CATALOGS.items():
        try:
            _, strings = entries(name, root)
        except (OSError, json.JSONDecodeError, KeyError) as error:
            errors.append((path, f"can't be read: {error}"))
            continue
        for key, entry in strings.items():
            text = english(key, entry)
            for lang, loc in entry.get("localizations", {}).items():
                if lang == "en":
                    continue
                if lang not in LANGUAGES:
                    errors.append((path, f'"{key}": {lang} is not in tools/l10n.py LANGUAGES'))
                    continue
                if text is None:
                    errors.append((path, f'"{key}": its English is not a string or a plural this tool reads'))
                    break
                value = translation(entry, lang)
                if value is None:
                    errors.append((path, f'"{key}" {lang}: not a string or a plural this tool reads'))
                    continue
                units = [loc.get("stringUnit")] if "stringUnit" in loc else [
                    v.get("stringUnit") for v in loc.get("variations", {}).get("plural", {}).values()]
                if any(u.get("state") not in ("translated", "needs_review") for u in units):
                    errors.append((path, f'"{key}" {lang}: state must be "translated" (or Xcode\'s "needs_review")'))
                errors += [(path, f'"{key}" {lang}: {m}') for m in problems(text, translation(entry, lang), lang)]
        for key in sources.get(name, {}):
            if key not in strings:
                errors.append((SOURCES, f'"{name}/{key}" is no longer in {path}: drop it'))
    summary = {}
    if errors:
        return errors, summary
    for name, lang, counts in status(root):
        for k in ("missing", "stale"):
            summary[k] = summary.get(k, 0) + counts[k]
    return errors, summary


def self_test():
    failures = []

    def expect(ok, message):
        if not ok:
            failures.append(message)

    expect(problems("%lld colors", "%lld Farben", "de") == [], "plain")
    expect(problems("%1$@ of %2$lld", "%2$lld の %1$@", "ja") == [], "reordered")
    expect(problems("Area %lld", "Bereich %1$lld", "de") == [], "numbered one")
    expect(problems("Area %lld", "Bereich %@", "de") != [], "type change")
    expect(problems("Area %lld", "Bereich", "de") != [], "dropped")
    expect(problems("Area %lld", "Bereich %d", "de") != [], "%d for an Int")
    expect(problems("Done", "Fertig 50 %", "de") != [], "stray percent")
    expect(problems("Done", "Fertig 50 %%", "de") == [], "escaped percent")
    expect(problems("See [Merge](guide:merge).", "Siehe [Zusammenführen](guide:merge).", "de") == [], "link")
    expect(problems("See [Merge](guide:merge).", "Siehe [Zusammenführen](guide:merg).", "de") != [], "broken link")
    plural = {"one": "%lld color", "other": "%lld colors"}
    expect(problems(plural, {"one": "%lld Farbe", "other": "%lld Farben"}, "de") == [], "plural")
    expect(problems(plural, {"other": "%lld Farben"}, "de") != [], "plural lacks one")
    expect(problems(plural, "%lld 色", "ja") == [], "ja other only")
    expect(problems(plural, {"one": "%lld色", "other": "%lld 色"}, "ja") != [], "ja has no one")
    expect(problems(plural, {"one": "%lld color", "other": "%lld colores", "many": "%lld de colores"}, "es") == [], "es many")
    for f in failures:
        print("self-test:", f)
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    t = sub.add_parser("todo")
    t.add_argument("lang")
    t.add_argument("--all", action="store_true", help="every key, done ones with their translation as \"was\"")
    t.add_argument("--out")
    a = sub.add_parser("apply")
    a.add_argument("lang")
    a.add_argument("file")
    a.add_argument("--dry-run", action="store_true", help="only check the file")
    sub.add_parser("check")
    sub.add_parser("self-test")
    args = parser.parse_args()
    if args.command == "status":
        for name, lang, c in status():
            print(f"{name:10} {lang:8} done {c['done']:4}  missing {c['missing']:4}  stale {c['stale']:4}")
        return 0
    if args.command == "todo":
        items = todo(args.lang, args.all)
        text = json.dumps(items, indent=1, ensure_ascii=False) + "\n"
        if args.out:
            Path(args.out).write_text(text, encoding="utf-8")
            print(f"{len(items)} strings for {args.lang} in {args.out}", file=sys.stderr)
        else:
            sys.stdout.write(text)
        return 0
    if args.command == "apply":
        errors = apply(args.lang, json.loads(Path(args.file).read_text(encoding="utf-8")), dry_run=args.dry_run)
        for e in errors:
            print(e, file=sys.stderr)
        return 1 if errors else 0
    if args.command == "check":
        errors, summary = check()
        for path, message in errors:
            print(f"{path}: {message}")
        print(f"{len(errors)} problem(s); {summary.get('missing', 0)} missing and {summary.get('stale', 0)} stale "
              f"translations (shown in English)")
        return 1 if errors else 0
    return self_test()


if __name__ == "__main__":
    sys.exit(main())
