#!/usr/bin/env python3
"""The naming graph: what is this already called, and what should it be called?

    tools/naming.py look NAME... [--also WORD,...] [--top N]
    tools/naming.py record FILE.json
    tools/naming.py report CONCEPT NAME... [--also WORD,...] [--out FILE]
    tools/naming.py decide NAME --sense TERM/SLUG --meaning TEXT [--banned WORD,...] --reason TEXT
    tools/naming.py glossary
    tools/naming.py drift [--strict]
    tools/naming.py expand NAME...

One naming question (the naming skill, .claude/skills/naming/SKILL.md, walks an agent through
it): one to five candidate names and a sentence saying what the thing is. `look` expands each
name into its spellings, answers every term the graph holds fresh, and finds the rest in the
code, grouped by identifier; the agent reads that and writes each new term's senses (`record`);
`report` then prints one table per name: each sense, its meaning, how many places use it and two
examples. Paul picks the name; `decide` records his ruling and rewrites GLOSSARY.md. Nothing
renames code.

The graph has four node types and six edge types, and grows only along the terms someone asked
about (never a scan of everything up front):

  term      a word or phrase as code spells it (`region`, `detail area`): its hit count, the
            identifiers it was seen in and the commit
  sense     one meaning of a term: a one-line definition and the identifiers that carry it
  location  where a sense shows up: a file and its outermost symbol (or a pipeline stage), and
            the commit it was seen at
  decision  Paul's ruling on a sense: the name to use, its meaning, the banned synonyms and the
            reason; it never expires (a later decision on the same sense supersedes it)

  term -has_sense-> sense -used_in-> location     sense -alias_of-> sense (one concept, two names)
  decision -settles-> sense, -names-> term        location -flows_to-> location (data-flow layer)

Terms, senses and locations can be rebuilt from the code; decisions hold what the code can't.

Matching: a term matches an identifier when its words are consecutive parts of it (split at
camelCase, PascalCase and snake_case; plurals and ABBREVIATIONS folded), so `region` matches
`RegionSimplifier` and `regions` but not `regional`; in comments, string literals and identifiers
SENTENCE_WORDS long (test names) its words match as prose. Searched: CODE_GLOBS by ripgrep (.gitignore respected); the string catalog's
user-facing text is counted beside, never a location.

Freshness: a recorded term stays fresh while its hit count is within TOLERANCE of the recorded
one (at least TOLERANCE_FLOOR lines); `look` asks for stale terms to be interpreted again and
lists the identifiers new since. `drift` lists identifiers new since each decision that use a
banned word (each still to be checked: the word may name another sense), and new uses of the
decided name.

Storage: an in-memory SQLite (tables `nodes` and `edges`, a JSON column each), loaded from and
saved to GRAPH, one record per line, sorted. It is text so that branches merge: .gitattributes
merges it as a union, and when both sides changed a record the later `at` wins.
"""
import argparse
import datetime
import fnmatch
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAPH = os.path.join("tools", "naming", "graph.jsonl")
GLOSSARY = "GLOSSARY.md"
CATALOG = os.path.join("App", "PaintByNumber", "Resources", "Localizable.xcstrings")
CODE_GLOBS = ["*.swift", "*.metal", "*.py", "*.js", "*.mjs", "*.sh"]
# The tool's own word lists would answer every question with themselves.
EXCLUDE_GLOBS = ["tools/naming.py", "tools/tests/test_naming.py", "**/Fixtures/**"]
TOLERANCE, TOLERANCE_FLOOR = 0.10, 5
# An identifier this many words long is a sentence (Swift Testing's test names): read as prose.
SENTENCE_WORDS = 6
# Only unambiguous ones: `col` (column or color?), `len`, `info` and `pt` would drown their word.
ABBREVIATIONS = {
    "btn": "button", "cfg": "configuration", "clr": "color", "cnt": "count", "colour": "color",
    "coord": "coordinate", "ctx": "context", "dst": "destination", "idx": "index", "img": "image",
    "lbl": "label", "msg": "message", "num": "number", "param": "parameter", "pos": "position",
    "prev": "previous", "rect": "rectangle", "ref": "reference", "rgn": "region", "seg": "segment",
    "src": "source", "tmpl": "template",
}
IRREGULAR = {
    "alias": "alias", "aliases": "alias", "axes": "axis", "caches": "cache", "canvas": "canvas",
    "canvases": "canvas", "children": "child", "data": "data", "ids": "id", "indices": "index",
    "leaves": "leaf", "matrices": "matrix", "people": "person", "series": "series",
    "vertices": "vertex",
}
PLURALS = {singular: plural for plural, singular in IRREGULAR.items() if plural != singular}

NODE_TYPES = ("term", "sense", "location", "decision")
EDGE_TYPES = ("has_sense", "used_in", "alias_of", "flows_to", "settles", "names")
SCHEMA = """
CREATE TABLE nodes (id TEXT PRIMARY KEY, type TEXT NOT NULL, name TEXT NOT NULL,
                    data TEXT NOT NULL, at TEXT NOT NULL);
CREATE TABLE edges (src TEXT NOT NULL, type TEXT NOT NULL, dst TEXT NOT NULL,
                    data TEXT NOT NULL, at TEXT NOT NULL, PRIMARY KEY (src, type, dst));
"""


class UsageError(Exception):
    pass


# Words


IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
PART = re.compile(r"[A-Z]{2,}s(?![a-z])|[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+")


def singular(word):
    if word in IRREGULAR:
        return IRREGULAR[word]
    if len(word) <= 3:
        return word
    if word.endswith("ies"):
        return word[:-3] + "y"
    if word.endswith(("sses", "shes", "ches", "xes")):
        return word[:-2]
    if word.endswith("s") and not word.endswith(("ss", "us", "is")):
        return word[:-1]
    return word


def plural(word):
    if word in PLURALS:
        return PLURALS[word]
    if word.endswith("y") and word[-2:-1] not in "aeiou":
        return word[:-1] + "ies"
    if word.endswith(("s", "x", "ch", "sh")):
        return word + "es"
    return word + "s"


def norm(part):
    word = singular(part.lower())
    return ABBREVIATIONS.get(word, word)


def parts(identifier):
    return [norm(p) for p in PART.findall(identifier)]


def words_of(name):
    """`detail area`, `detailAreas` and `DETAIL_AREA` are all ["detail", "area"]."""
    words = [w for token in name.split() for w in parts(token)]
    if not words:
        raise UsageError(f"no words in {name!r}")
    return words


def term_key(name):
    return " ".join(words_of(name))


def spellings(words):
    """The spelling variants of step 2: plain code, no model."""
    def camel(ws):
        return ws[0] + "".join(w.capitalize() for w in ws[1:])
    forms = []
    for last in (words[-1], plural(words[-1])):
        ws = words[:-1] + [last]
        forms += [camel(ws), "".join(w.capitalize() for w in ws), "_".join(ws)]
    abbreviated = {}
    for short, word in ABBREVIATIONS.items():
        abbreviated.setdefault(word, []).append(short)
    for i, word in enumerate(words):
        for short in abbreviated.get(word, []):
            forms.append(camel(words[:i] + [short] + words[i + 1:]))
    return list(dict.fromkeys(forms))


def contains(seq, words):
    n = len(words)
    return any(seq[i:i + n] == words for i in range(len(seq) - n + 1))


# Sources


class Lang:
    def __init__(self, hash_comments=False, quotes='"', triples=(), docstrings=False,
                 scopes=None, decls=None):
        self.hash_comments, self.quotes, self.triples = hash_comments, quotes, triples
        self.docstrings, self.scopes, self.decls = docstrings, scopes, decls or []


SWIFT_SCOPE = re.compile(r"\b(?:struct|class|enum|protocol|actor|extension|func)\s+([A-Za-z_]\w*)|"
                         r"\b(init)\s*[?!]?\s*[(<]")
SWIFT_EXTENSION = re.compile(r"\bextension\s+([A-Za-z_]\w*)")
LANGS = {
    ".swift": Lang(triples=('"""',), scopes=SWIFT_SCOPE,
                   decls=[re.compile(r"\b(?:var|let|case|typealias|associatedtype)\s+([A-Za-z_]\w*)")]),
    ".metal": Lang(scopes=re.compile(r"\bstruct\s+([A-Za-z_]\w*)")),
    ".py": Lang(hash_comments=True, quotes="\"'", triples=('"""', "'''"), docstrings=True,
                scopes=re.compile(r"^\s*(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)"),
                decls=[re.compile(r"^([A-Za-z_]\w*)\s*(?::[^=]*)?=(?!=)")]),
    ".js": Lang(quotes="\"'`", scopes=re.compile(r"\b(?:function|class)\s+([A-Za-z_$][\w$]*)"),
                decls=[re.compile(r"\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)")]),
    ".sh": Lang(hash_comments=True, quotes="\"'", scopes=re.compile(r"^\s*([A-Za-z_]\w*)\s*\(\)\s*\{"),
                decls=[re.compile(r"^\s*(?:local\s+|export\s+|readonly\s+)?([A-Za-z_]\w*)=")]),
}
LANGS[".mjs"] = LANGS[".js"]
KEYWORDS = {"func", "class", "struct", "enum", "let", "var", "case", "static", "final", "init"}


def segments(line, state, lang):
    """Splits a line into ("code" | "string" | "comment", text) runs. `state` is what the line
    starts inside: None, "/*" or a triple quote; returns the runs and the next line's state."""
    out = []
    i, start, n = 0, 0, len(line)

    def kind(st):
        if st is None:
            return "code"
        return "comment" if st == "/*" or lang.docstrings else "string"

    def emit(k, a, b):
        if b > a:
            out.append((k, line[a:b]))

    while i < n:
        if state == "/*" or state in lang.triples:
            closer = "*/" if state == "/*" else state
            j = line.find(closer, i)
            if j < 0:
                break
            emit(kind(state), start, j + len(closer))
            i = start = j + len(closer)
            state = None
            continue
        if (lang.hash_comments and line[i] == "#") or (not lang.hash_comments and line.startswith("//", i)):
            emit("code", start, i)
            emit("comment", i, n)
            return out, None
        if not lang.hash_comments and line.startswith("/*", i):
            emit("code", start, i)
            start, state, i = i, "/*", i + 2
            continue
        triple = next((t for t in lang.triples if line.startswith(t, i)), None)
        if triple:
            emit("code", start, i)
            start, state, i = i, triple, i + 3
            continue
        if line[i] in lang.quotes:
            j = i + 1
            while j < n and line[j] != line[i]:
                j += 2 if line[j] == "\\" else 1
            emit("code", start, i)
            emit("string", i, min(j + 1, n))
            i = start = min(j + 1, n)
            continue
        i += 1
    emit(kind(state), start, n)
    return out, state


def declared(code, lang):
    """(scope name or None, every name the code declares)."""
    names, scope = set(), None
    if lang.scopes:
        for m in lang.scopes.finditer(code):
            name = next((g for g in m.groups() if g), None)
            if name and (name not in KEYWORDS or name == "init"):
                scope = scope or name
                names.add(name)
    for pattern in lang.decls:
        names.update(m.group(1) for m in pattern.finditer(code) if m.group(1) not in KEYWORDS)
    if lang is LANGS[".swift"]:
        names -= {m.group(1) for m in SWIFT_EXTENSION.finditer(code)}
    return scope, names


class Source:
    """One file: each line's start state and its enclosing symbols (by indentation)."""

    def __init__(self, root, rel):
        self.rel, self.lang = rel, LANGS[os.path.splitext(rel)[1]]
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as f:
            self.lines = f.read().split("\n")
        self.states, self.paths, self.decls = [], [], []
        stack, state = [], None
        for line in self.lines:
            self.states.append(state)
            runs, state = segments(line, state, self.lang)
            code = " ".join(text for k, text in runs if k == "code")
            scope, names = (None, set())
            if code.strip():
                indent = len(line) - len(line.lstrip())
                while stack and stack[-1][0] >= indent:
                    stack.pop()
                scope, names = declared(code, self.lang)
                if scope:
                    stack.append((indent, scope))
            self.paths.append(".".join(name for _, name in stack))
            self.decls.append(names)

    def hits(self, number, words):
        """The term's hits on line `number` (1-based): (kind, identifier or None)."""
        line = self.lines[number - 1]
        runs, _ = segments(line, self.states[number - 1], self.lang)
        found = []
        for kind, text in runs:
            if kind == "code":
                for m in IDENT.finditer(text):
                    ident_parts = parts(m.group())
                    if not contains(ident_parts, words):
                        continue
                    if len(ident_parts) >= SENTENCE_WORDS:
                        found.append(("comment", None))
                    else:
                        found.append(("decl" if m.group() in self.decls[number - 1] else "use", m.group()))
            elif contains(parts(text), words):
                found.append((kind, None))
        return list(dict.fromkeys(found))


class Hit:
    __slots__ = ("file", "line", "kind", "ident", "symbol", "text")

    def __init__(self, file, line, kind, ident, symbol, text):
        self.file, self.line, self.kind, self.ident = file, line, kind, ident
        self.symbol, self.text = symbol, text

    @property
    def top(self):
        return self.symbol.split(".")[0] if self.symbol else "(top level)"

    @property
    def where(self):
        symbol = self.symbol
        if self.kind == "decl" and self.ident and not symbol.endswith(self.ident):
            symbol = f"{symbol}.{self.ident}" if symbol else self.ident
        return f"{self.file}:{self.line}" + (f" {symbol}" if symbol else "")


class Search:
    """Every hit of one term in the code, with the string catalog's matches beside."""

    def __init__(self, root, name, sources):
        self.words = words_of(name)
        self.key = " ".join(self.words)
        self.hits = []
        # ripgrep finds candidate lines by the longest word's spellings; Source.hits decides.
        stem = max(self.words, key=len)
        stems = {stem, plural(stem)} | {s for s, w in ABBREVIATIONS.items() if w == stem}
        stems |= {p for p, s in IRREGULAR.items() if s == stem}
        pattern = "|".join(sorted(re.escape(s) for s in stems))
        command = ["rg", "--no-heading", "--line-number", "--color", "never", "--ignore-case",
                   "--max-columns", "400"]
        for glob in CODE_GLOBS:
            command += ["--glob", glob]
        for glob in EXCLUDE_GLOBS:
            command += ["--glob", "!" + glob]
        try:
            result = subprocess.run(command + ["--", pattern, "."], cwd=root, capture_output=True,
                                    text=True, stdin=subprocess.DEVNULL)
        except FileNotFoundError:
            raise UsageError("ripgrep (rg) is required")
        if result.returncode > 1:
            raise UsageError(result.stderr.strip())
        for row in result.stdout.splitlines():
            file, number, _ = row.split(":", 2)
            file = file[2:] if file.startswith("./") else file
            if file not in sources:
                sources[file] = Source(root, file)
            source = sources[file]
            number = int(number)
            for kind, ident in source.hits(number, self.words):
                self.hits.append(Hit(file, number, kind, ident, source.paths[number - 1],
                                     source.lines[number - 1].strip()))
        # ripgrep searches files in parallel: sort, so examples and assignments repeat.
        self.hits.sort(key=lambda h: (h.file, h.line))
        self.copy = catalog_matches(root, self.words)

    @property
    def lines(self):
        return len({(h.file, h.line) for h in self.hits})

    @property
    def files(self):
        return len({h.file for h in self.hits})

    def identifiers(self):
        counts = defaultdict(set)
        for hit in self.hits:
            if hit.ident:
                counts[hit.ident].add((hit.file, hit.line))
        return {ident: len(lines) for ident, lines in counts.items()}


def excerpt(text, words, width=70):
    """`text` cut to `width` characters around the first of `words`."""
    if len(text) <= width:
        return text
    at = max(0, text.lower().find(words[0][:4]) - width // 3)
    cut = text[at:at + width]
    return ("…" if at else "") + cut + ("…" if at + width < len(text) else "")


def catalog_matches(root, words):
    path = os.path.join(root, CATALOG)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        strings = json.load(f).get("strings", {})
    found = []
    for key, entry in strings.items():
        text = (entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value") or key)
        if contains(parts(text), words):
            found.append(text)
    return sorted(found)


def git_head(root):
    try:
        out = subprocess.run(["git", "-C", root, "rev-parse", "--short=12", "HEAD"],
                             capture_output=True, text=True, check=True)
        return out.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


# The graph


def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def now_eastern():
    try:
        from zoneinfo import ZoneInfo
        return datetime.datetime.now(ZoneInfo("America/New_York")), "ET"
    except Exception:
        return datetime.datetime.now(datetime.timezone.utc), "UTC"


class Graph:
    def __init__(self, root):
        self.path = os.path.join(root, GRAPH)
        self.db = sqlite3.connect(":memory:")
        self.db.executescript(SCHEMA)
        if os.path.exists(self.path):
            with open(self.path, encoding="utf-8") as f:
                for line in f:
                    if line.strip():
                        self._load(json.loads(line))

    def __del__(self):
        self.db.close()

    def _load(self, record):
        # A union merge can leave two versions of one record: the later `at` wins.
        if "node" in record:
            old = self.db.execute("SELECT at FROM nodes WHERE id = ?", (record["node"],)).fetchone()
            if old is None or old[0] <= record["at"]:
                self.db.execute("INSERT OR REPLACE INTO nodes VALUES (?, ?, ?, ?, ?)",
                                (record["node"], record["type"], record["name"],
                                 json.dumps(record.get("data", {}), sort_keys=True), record["at"]))
        else:
            src, kind, dst = record["edge"]
            old = self.db.execute("SELECT at FROM edges WHERE src = ? AND type = ? AND dst = ?",
                                  (src, kind, dst)).fetchone()
            if old is None or old[0] <= record["at"]:
                self.db.execute("INSERT OR REPLACE INTO edges VALUES (?, ?, ?, ?, ?)",
                                (src, kind, dst, json.dumps(record.get("data", {}), sort_keys=True),
                                 record["at"]))

    def save(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        rows = []
        for id_, type_, name, data, at in self.db.execute("SELECT * FROM nodes ORDER BY id"):
            rows.append({"node": id_, "type": type_, "name": name, "data": json.loads(data), "at": at})
        for src, type_, dst, data, at in self.db.execute("SELECT * FROM edges ORDER BY src, type, dst"):
            rows.append({"edge": [src, type_, dst], "data": json.loads(data), "at": at})
        with open(self.path, "w", encoding="utf-8") as f:
            for row in rows:
                f.write(json.dumps(row, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n")

    def node(self, id_):
        row = self.db.execute("SELECT type, name, data FROM nodes WHERE id = ?", (id_,)).fetchone()
        return None if row is None else {"id": id_, "type": row[0], "name": row[1], "data": json.loads(row[2])}

    def nodes(self, type_):
        rows = self.db.execute("SELECT id, name, data FROM nodes WHERE type = ? ORDER BY id", (type_,))
        return [{"id": i, "type": type_, "name": n, "data": json.loads(d)} for i, n, d in rows]

    def put_node(self, id_, type_, name, data):
        assert type_ in NODE_TYPES
        blob = json.dumps(data, sort_keys=True)
        old = self.db.execute("SELECT name, data FROM nodes WHERE id = ?", (id_,)).fetchone()
        if old != (name, blob):
            self.db.execute("INSERT OR REPLACE INTO nodes VALUES (?, ?, ?, ?, ?)",
                            (id_, type_, name, blob, now_utc()))

    def put_edge(self, src, type_, dst, data=None):
        assert type_ in EDGE_TYPES
        blob = json.dumps(data or {}, sort_keys=True)
        old = self.db.execute("SELECT data FROM edges WHERE src = ? AND type = ? AND dst = ?",
                              (src, type_, dst)).fetchone()
        if old is None or old[0] != blob:
            self.db.execute("INSERT OR REPLACE INTO edges VALUES (?, ?, ?, ?, ?)",
                            (src, type_, dst, blob, now_utc()))

    def edges(self, src=None, type_=None, dst=None):
        query, args = "SELECT src, type, dst, data FROM edges WHERE 1", []
        for column, value in (("src", src), ("type", type_), ("dst", dst)):
            if value is not None:
                query += f" AND {column} = ?"
                args.append(value)
        return [(s, t, d, json.loads(data)) for s, t, d, data in self.db.execute(query + " ORDER BY src, dst", args)]

    def drop_node(self, id_):
        self.db.execute("DELETE FROM nodes WHERE id = ?", (id_,))
        self.db.execute("DELETE FROM edges WHERE src = ? OR dst = ?", (id_, id_))

    def drop_orphan_locations(self):
        self.db.execute("DELETE FROM nodes WHERE type = 'location' AND id NOT IN "
                        "(SELECT dst FROM edges WHERE type IN ('used_in', 'flows_to')) AND id NOT IN "
                        "(SELECT src FROM edges WHERE type = 'flows_to')")

    def senses(self, key):
        """A term's senses in the order they were recorded, the order hits are assigned in."""
        senses = [self.node(dst) for _, _, dst, _ in self.edges(src="term:" + key, type_="has_sense")]
        return sorted(senses, key=lambda s: (s["data"].get("order", 0), s["id"]))

    def decisions(self):
        """Decisions not superseded, oldest first."""
        active = [d for d in self.nodes("decision") if not d["data"].get("superseded_by")]
        return sorted(active, key=lambda d: d["data"]["decided"])


def sense_id(ref):
    if "/" not in ref:
        raise UsageError(f"a sense is TERM/SLUG, not {ref!r}")
    term, slug = ref.rsplit("/", 1)
    return f"sense:{term_key(term)}/{slug}"


def location_id(file, symbol):
    return f"location:{file}#{symbol}"


def claims(rule, hit):
    name, files = (rule, None) if isinstance(rule, str) else (rule["name"], rule.get("files"))
    return fnmatch.fnmatchcase(hit.ident, name) and (
        not files or any(fnmatch.fnmatch(hit.file, g) for g in files))


def ignores(patterns, ident):
    return any(fnmatch.fnmatchcase(ident, p) for p in patterns)


def assign(search, senses):
    """Each hit to the first sense whose identifiers (or prose, strings) claim it."""
    owned = defaultdict(list)
    for hit in search.hits:
        for sense in senses:
            data = sense["data"]
            if (hit.ident and any(claims(rule, hit) for rule in data.get("identifiers", []))) or \
               (hit.kind == "comment" and data.get("prose")) or (hit.kind == "string" and data.get("strings")):
                owned[sense["id"]].append(hit)
                break
        else:
            owned[None].append(hit)
    return owned


def freshness(term, search):
    recorded = term["data"]["lines"]
    fresh = abs(search.lines - recorded) <= max(TOLERANCE_FLOOR, TOLERANCE * recorded)
    new = sorted(set(search.identifiers()) - set(term["data"]["identifiers"]))
    return fresh, recorded, new


# Commands


def cmd_expand(root, args):
    for name in args.names:
        words = words_of(name)
        print(f"{name}: term `{' '.join(words)}`; spellings {', '.join(spellings(words))}")


def split_names(names, also):
    out = list(names)
    for chunk in also or []:
        out += [w.strip() for w in chunk.split(",") if w.strip()]
    keys = []
    for name in out:
        if term_key(name) not in [term_key(k) for k in keys]:
            keys.append(name)
    return keys


def cmd_look(root, args):
    graph, sources, pending = Graph(root), {}, []
    print(f"# Look · HEAD {git_head(root)}\n")
    for name in split_names(args.names, args.also):
        started = time.monotonic()
        search = Search(root, name, sources)
        term = graph.node("term:" + search.key)
        took = time.monotonic() - started
        heading = f"## `{search.key}` ({name}): {search.lines:,} lines in {search.files:,} files"
        if not search.hits:
            print(f"{heading}: unused in code" + (f"; in {len(search.copy)} UI strings" if search.copy else "") + "\n")
            continue
        senses = graph.senses(search.key) if term else []
        if term and senses:
            fresh, recorded, new = freshness(term, search)
            if fresh:
                print(f"{heading} · from the graph (fresh: {recorded:,} lines when recorded at "
                      f"{term['data']['sha']})")
                for sense in senses:
                    print(f"- `{sense['id'][6:]}`: {sense['data']['definition']}")
                if new:
                    print(f"- new since: {', '.join(new[:12])}" + (" …" if len(new) > 12 else ""))
                print()
                continue
            print(f"{heading} · STALE: {recorded:,} lines when recorded, now {search.lines:,}; "
                  f"interpret again, keeping these slugs where they still fit: "
                  + ", ".join(f"`{s['id'][6:]}`" for s in senses))
            if new:
                print(f"New identifiers since: {', '.join(new)}")
        else:
            print(f"{heading} · interpret ({took:.1f} s to find)")
        pending.append(search.key)
        print_digest(search, args.top)
    if pending:
        print("To interpret: " + ", ".join(f"`{k}`" for k in pending) + ". Write their senses to a JSON "
              "file (format: the naming skill, or `record --help`) and run tools/naming.py record FILE.")


def print_digest(search, top):
    by_ident = defaultdict(list)
    prose, strings = [], []
    for hit in search.hits:
        (by_ident[hit.ident] if hit.ident else prose if hit.kind == "comment" else strings).append(hit)
    rows = sorted(by_ident.items(), key=lambda kv: (-len({(h.file, h.line) for h in kv[1]}), kv[0]))
    print("\n| identifier | lines | files | declared | example |\n| --- | --- | --- | --- | --- |")
    for ident, hits in rows[:top]:
        decls = [h for h in hits if h.kind == "decl"]
        example = (decls or hits)[0]
        declared_at = "; ".join(h.where for h in decls[:2]) + (" …" if len(decls) > 2 else "") if decls \
            else "not in repo (system API, parameter or label)"
        text = example.text if len(example.text) <= 100 else example.text[:97] + "…"
        lines = len({(h.file, h.line) for h in hits})
        print(f"| `{ident}` | {lines} | {len({h.file for h in hits})} | {declared_at} | "
              f"{example.file}:{example.line} `{text.replace('|', '¦').replace('`', '')}` |")
    if len(rows) > top:
        rest = ", ".join(f"{ident} {len({(h.file, h.line) for h in hits})}" for ident, hits in rows[top:])
        print(f"\nAnd {len(rows) - top} more: {rest}")
    for label, hits in (("Prose (comments, test names)", prose), ("String literals", strings)):
        if hits:
            samples = "; ".join(f"{h.file}:{h.line} “{h.text[:90]}”" for h in hits[:3])
            print(f"\n{label}: {len(hits)} lines, e.g. {samples}")
    if search.copy:
        print(f"\nUI copy: {len(search.copy)} strings, e.g. "
              + "; ".join(f"“{excerpt(s, search.words)}”" for s in search.copy[:4]))
    print()


RECORD_FORMAT = """\
A JSON object, or a list of them, one per term:

  {"term": "cell",
   "senses": [{"slug": "book-cell", "definition": "one line",
               "identifiers": ["CellMap", {"name": "cell", "files": ["Sources/PaintCore/LineArt/*"]}],
               "prose": true, "strings": false}],
   "ignore": ["cellular", "*Cellular*"],
   "aliases": [["cell/book-cell", "region/region", "why they are one concept"]],
   "flows": [["stage:segment", "stage:vectorize", "label map"]]}

Each hit goes to the first sense whose identifiers claim it, in order: a name may hold `*`
(`regionRing*`; a last sense's `*` takes the rest), and a `files` glob narrows it (`*` crosses
folders); `prose` and `strings` claim the comment and string-literal lines. Identifiers
no sense claims and not ignored stay unsorted in the report. An alias or flow names nodes that
exist or are recorded in the same file (a `stage:NAME` location is made when missing)."""


def cmd_record(root, args):
    with open(args.file, encoding="utf-8") as f:
        payload = json.load(f)
    items = payload if isinstance(payload, list) else [payload]
    graph, sources, sha, notes = Graph(root), {}, git_head(root), []
    for item in items:
        search = Search(root, item["term"], sources)
        if not search.hits:
            raise UsageError(f"`{search.key}` has no hits in code: nothing to interpret")
        known = search.identifiers()
        senses, slugs = [], set()
        for sense in item.get("senses", []):
            slug, definition = sense.get("slug", ""), " ".join(sense.get("definition", "").split())
            if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", slug) or slug in slugs:
                raise UsageError(f"`{search.key}`: slug {slug!r} must be unique, lowercase, a-z 0-9 -")
            if not definition or len(definition) > 240:
                raise UsageError(f"`{search.key}/{slug}`: a one-line definition (up to 240 characters)")
            rules = sense.get("identifiers", [])
            for rule in rules:
                name = rule if isinstance(rule, str) else rule["name"]
                if "*" not in name and name not in known:
                    notes.append(f"`{search.key}/{slug}`: `{name}` is not among the term's identifiers")
            slugs.add(slug)
            senses.append({"id": f"sense:{search.key}/{slug}", "data": {
                "term": search.key, "order": len(senses), "definition": definition, "identifiers": rules,
                "prose": bool(sense.get("prose")), "strings": bool(sense.get("strings"))}})
        owned = assign(search, senses)
        ignored = set(item.get("ignore", []))
        unsorted = sorted({h.ident for h in owned[None] if h.ident and not ignores(ignored, h.ident)})
        term_id = "term:" + search.key
        graph.put_node(term_id, "term", search.key, {
            "words": search.words, "spellings": spellings(search.words), "lines": search.lines,
            "files": search.files, "identifiers": known, "ignored": sorted(ignored),
            "unsorted": unsorted, "sha": sha})
        settled = {dst for _, _, dst, _ in graph.edges(type_="settles")}
        for _, _, old, _ in graph.edges(src=term_id, type_="has_sense"):
            if old not in {s["id"] for s in senses}:
                if old in settled:
                    notes.append(f"`{old[6:]}` was dropped but a decision settles it: kept")
                else:
                    graph.drop_node(old)
        for sense in senses:
            hits = owned[sense["id"]]
            sense["data"].update(lines=len({(h.file, h.line) for h in hits}),
                                 files=len({h.file for h in hits}), sha=sha)
            graph.put_node(sense["id"], "sense", sense["id"][6:], sense["data"])
            graph.put_edge(term_id, "has_sense", sense["id"])
            for _, _, old, _ in graph.edges(src=sense["id"], type_="used_in"):
                graph.db.execute("DELETE FROM edges WHERE src = ? AND type = 'used_in' AND dst = ?",
                                 (sense["id"], old))
            places = defaultdict(list)
            for hit in hits:
                places[(hit.file, hit.top)].append(hit.line)
            for (file, top), lines in places.items():
                loc = location_id(file, top)
                graph.put_node(loc, "location", f"{file}#{top}", {"file": file, "symbol": top, "kind": "code", "sha": sha})
                graph.put_edge(sense["id"], "used_in", loc, {"lines": len(set(lines)), "first": min(lines)})
        notes.append(f"`{search.key}`: {len(senses)} senses, {len(unsorted)} identifiers unsorted")
    for item in items:
        for a, b, *why in item.get("aliases", []):
            ids = [sense_id(a), sense_id(b)]
            for id_ in ids:
                if graph.node(id_) is None:
                    raise UsageError(f"alias: no sense `{id_[6:]}`")
            graph.put_edge(ids[0], "alias_of", ids[1], {"why": why[0] if why else ""})
        for a, b, *what in item.get("flows", []):
            ids = []
            for ref in (a, b):
                if ref.startswith("stage:"):
                    id_ = "location:" + ref
                    graph.put_node(id_, "location", ref, {"stage": ref[6:], "kind": "stage", "sha": sha})
                else:
                    id_ = ref if ref.startswith("location:") else "location:" + ref
                    if graph.node(id_) is None:
                        raise UsageError(f"flow: no location `{ref}`")
                ids.append(id_)
            graph.put_edge(ids[0], "flows_to", ids[1], {"carries": what[0] if what else ""})
    graph.drop_orphan_locations()
    graph.save()
    print("\n".join(notes))


def applying_decisions(graph, keys):
    """Decisions that name one of the keys, ban one, or settle one of their senses."""
    out = []
    for decision in graph.decisions():
        data = decision["data"]
        sense_terms = {dst[6:].rsplit("/", 1)[0] for _, _, dst, _ in graph.edges(src=decision["id"], type_="settles")}
        words = {term_key(data["name"])} | {term_key(b) for b in data["banned"]} | sense_terms
        if words & set(keys):
            out.append(decision)
    return out


def cmd_report(root, args):
    graph, sources = Graph(root), {}
    names = split_names(args.names, args.also)
    started = time.monotonic()
    searches = [Search(root, name, sources) for name in names]
    when, zone = now_eastern()
    out = [f"# What should it be called?\n", f"> {args.concept}\n",
           f"Candidates: {', '.join(args.names)}"
           + (f" · also searched: {', '.join(names[len(args.names):])}" if len(names) > len(args.names) else "")
           + f" · HEAD {git_head(root)} · {when:%Y-%m-%d %H:%M} {zone}\n"]
    decisions = applying_decisions(graph, [s.key for s in searches])
    if decisions:
        out.append("## Decisions already made\n")
        for d in decisions:
            data = d["data"]
            out.append(f"- **{data['name']}**: {data['meaning']}"
                       + (f" Not: {', '.join(data['banned'])}." if data["banned"] else "")
                       + f" Why: {data['reason']} ({data['decided']})")
        out.append("")
    out.append("| Name | In code | Senses | UI copy |\n| --- | --- | --- | --- |")
    sections = []
    for name, search in zip(names, searches):
        term = graph.node("term:" + search.key)
        senses = graph.senses(search.key) if term else []
        if not search.hits:
            out.append(f"| {name} | unused | — | {len(search.copy) or '—'} |")
            continue
        status = "not interpreted"
        if senses:
            fresh, recorded, _ = freshness(term, search)
            status = str(len(senses)) + ("" if fresh else f" (stale: {recorded:,} lines when recorded)")
        out.append(f"| {name} | {search.lines:,} lines · {search.files:,} files | {status} | "
                   f"{len(search.copy) or '—'} |")
        sections.append(report_section(graph, name, search, term, senses))
    out.append("")
    out += sections
    out.append(f"_Found in {time.monotonic() - started:.1f} s. Places are lines; a sense's examples are its "
               f"declaration, then a use in another file._")
    text = "\n".join(out) + "\n"
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
    sys.stdout.write(text)


def report_section(graph, name, search, term, senses):
    out = [f"## {name}\n"]
    if not senses:
        out.append(f"Not interpreted yet: run `tools/naming.py look \"{name}\"` and record its senses.\n")
        return "\n".join(out)
    owned = assign(search, senses)
    out.append("| Sense | Meaning | Places | Examples |\n| --- | --- | --- | --- |")
    for sense in senses:
        hits = owned[sense["id"]]
        examples = pick_examples(hits, search.words)
        where = "; ".join(f"`{h.where}`" for h in examples) or "—"
        places = f"{len({(h.file, h.line) for h in hits}):,} lines · {len({h.file for h in hits})} files"
        out.append(f"| `{sense['id'][6:]}` | {sense['data']['definition']} | {places} | {where} |")
    ids = {s["id"] for s in senses}
    for src, _, dst, data in graph.edges(type_="alias_of"):
        if src in ids or dst in ids:
            out.append(f"\nAlias: `{src[6:]}` is `{dst[6:]}`" + (f" ({data['why']})" if data.get("why") else ""))
    unsorted = sorted({h.ident for h in owned[None] if h.ident and not ignores(term["data"].get("ignored", []), h.ident)},
                      key=lambda i: -search.identifiers().get(i, 0))
    if unsorted:
        out.append(f"\nUnsorted: {', '.join(unsorted[:10])}" + (" …" if len(unsorted) > 10 else ""))
    if search.copy:
        out.append(f"\nIn UI copy: " + "; ".join(f"“{excerpt(s, search.words)}”" for s in search.copy[:3])
                   + (f" (+{len(search.copy) - 3})" if len(search.copy) > 3 else ""))
    return "\n".join(out) + "\n"


TYPE_DECL = re.compile(r"\b(?:struct|class|enum|protocol|actor|typealias)\s+([A-Za-z_]\w*)")
ASIDE = ("tools/", "Tests/", "App/PaintByNumberTests/", "App/PaintByNumberUITests/")


def pick_examples(hits, words):
    """A sense's two examples: the declaration of its main identifier (a type's first, the term's
    own spelling first), then a use of it in another file; shipping code before tools and tests."""
    code = [h for h in hits if h.ident]
    uses = defaultdict(int)
    for hit in code:
        uses[hit.ident] += 1

    def rank(hit):
        is_type = any(m.group(1) == hit.ident for m in TYPE_DECL.finditer(hit.text))
        return (hit.kind != "decl", not is_type, parts(hit.ident) != words, -uses[hit.ident],
                hit.file.startswith(ASIDE), not hit.file.startswith("Sources/"), hit.file, hit.line)

    if not code:
        return [h for h in hits if h.kind != "comment"][:1]
    first = min(code, key=rank)
    rest = [h for h in code if h.file != first.file]
    second = min(rest, key=lambda h: (h.ident != first.ident, h.file.startswith(ASIDE), h.file, h.line)) if rest else None
    return [first] + ([second] if second else [])


def cmd_decide(root, args):
    graph, sources = Graph(root), {}
    target = sense_id(args.sense)
    if graph.node(target) is None:
        raise UsageError(f"no sense `{target[6:]}`: record it first")
    banned = [b.strip() for b in (args.banned or "").split(",") if b.strip()]
    when, zone = now_eastern()
    baseline = {}
    for word in [args.name] + banned:
        baseline[term_key(word)] = sorted(Search(root, word, sources).identifiers())
    key = term_key(args.name)
    decision_id = f"decision:{target[6:]}@{when:%Y%m%d%H%M%S}"
    for old in [s for s, _, _, _ in graph.edges(type_="settles", dst=target)]:
        node = graph.node(old)
        if not node["data"].get("superseded_by"):
            node["data"]["superseded_by"] = decision_id
            graph.put_node(old, "decision", node["name"], node["data"])
    graph.put_node(decision_id, "decision", args.name, {
        "name": args.name, "meaning": " ".join(args.meaning.split()), "banned": banned,
        "reason": " ".join(args.reason.split()), "by": args.by, "decided": f"{when:%Y-%m-%d}",
        "sha": git_head(root), "baseline": baseline})
    if graph.node("term:" + key) is None:
        graph.put_node("term:" + key, "term", key, {"words": key.split(), "lines": 0, "identifiers": {}})
    graph.put_edge(decision_id, "settles", target)
    graph.put_edge(decision_id, "names", "term:" + key)
    graph.save()
    write_glossary(root, graph)
    print(f"Recorded: {args.name} for `{target[6:]}`" + (f", not {', '.join(banned)}" if banned else "")
          + f"; {GLOSSARY} rewritten.")


GLOSSARY_HEAD = """\
# Glossary

The names Paul settled for this code base. For the meaning in the second column, use the name in
the first and none of the words in the third. Generated by `tools/naming.py glossary` from the
decisions in `tools/naming/graph.jsonl`: don't edit it by hand. Before naming a new public type,
property or function, ask the naming skill (`.claude/skills/naming/SKILL.md`).
"""


def write_glossary(root, graph):
    rows = sorted(graph.decisions(), key=lambda d: d["data"]["name"].lower())
    text = GLOSSARY_HEAD + "\n"
    if rows:
        text += "| Name | Meaning | Not | Why | Decided |\n| --- | --- | --- | --- | --- |\n"
        for d in rows:
            data = d["data"]
            cells = [f"**{data['name']}**", data["meaning"], ", ".join(data["banned"]) or "—",
                     data["reason"], data["decided"]]
            text += "| " + " | ".join(c.replace("|", "\\|") for c in cells) + " |\n"
    else:
        text += "No decisions yet.\n"
    with open(os.path.join(root, GLOSSARY), "w", encoding="utf-8") as f:
        f.write(text)


def cmd_glossary(root, args):
    write_glossary(root, Graph(root))
    print(f"{GLOSSARY} rewritten.")


def cmd_drift(root, args):
    graph, sources, drifted = Graph(root), {}, False
    decisions = graph.decisions()
    if not decisions:
        print("No decisions yet.")
        return 0
    for d in decisions:
        data = d["data"]
        print(f"## {data['name']} ({data['decided']})")
        for word in [data["name"]] + data["banned"]:
            key = term_key(word)
            search = Search(root, word, sources)
            new = sorted(set(search.identifiers()) - set(data["baseline"].get(key, [])))
            if word == data["name"]:
                print(f"- uses of {word}: {len(new)} identifiers new since" + (f": {', '.join(new[:10])}" if new else ""))
                continue
            if new:
                drifted = True
                for ident in new:
                    hit = next(h for h in search.hits if h.ident == ident)
                    print(f"- drift? `{ident}` uses banned {word}: {hit.where}")
        print()
    return 1 if drifted and args.strict else 0


def main(argv=None, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("expand", help="spelling variants of each name")
    p.add_argument("names", nargs="+")
    p = sub.add_parser("look", help="answer terms from the graph, or find them in code")
    p.add_argument("names", nargs="+")
    p.add_argument("--also", action="append", help="comma-separated words the concept may already be called")
    p.add_argument("--top", type=int, default=60, help="identifiers shown in full (default 60)")
    p = sub.add_parser("record", help="write terms' senses", epilog=RECORD_FORMAT,
                       formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("file")
    p = sub.add_parser("report", help="the collision report")
    p.add_argument("concept", help="one sentence: what the thing is")
    p.add_argument("names", nargs="+")
    p.add_argument("--also", action="append")
    p.add_argument("--out")
    p = sub.add_parser("decide", help="record Paul's ruling (only on his word)")
    p.add_argument("name")
    p.add_argument("--sense", required=True)
    p.add_argument("--meaning", required=True)
    p.add_argument("--banned")
    p.add_argument("--reason", required=True)
    p.add_argument("--by", default="Paul")
    sub.add_parser("glossary", help=f"rewrite {GLOSSARY}")
    p = sub.add_parser("drift", help="new identifiers using banned words since each decision")
    p.add_argument("--strict", action="store_true", help="exit 1 on drift")
    args = parser.parse_args(argv)
    commands = {"expand": cmd_expand, "look": cmd_look, "record": cmd_record, "report": cmd_report,
                "decide": cmd_decide, "glossary": cmd_glossary, "drift": cmd_drift}
    try:
        return commands[args.command](root, args) or 0
    except UsageError as error:
        print(f"naming: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
