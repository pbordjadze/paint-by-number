---
name: naming
description: Ask before naming. Use before introducing a new public type, property, function, enum case or file name in paint-by-number, and whenever someone asks what something should be called or whether a name is taken. Runs the naming graph (tools/naming.py): finds what the candidate names and the concept already mean in the code, records each meaning once so later questions reuse it, and returns a collision report. Paul decides; nothing renames code.
---

# Ask before naming

`GLOSSARY.md` holds the names Paul has settled. If your concept is there, use its name, avoid its
banned words, and stop. Otherwise run the seven steps below. Skip them for locals, parameters and
test names.

1. **Ask.** Write down one to five candidate names and one sentence that says what the thing is,
   in the code's terms ("the cluster of same-colored pixels the painter paints as one area").
2. **Expand.** `tools/naming.py look` does this for you: plurals, camelCase, PascalCase,
   snake_case and the common abbreviations all match.
3. **Search by meaning.** Before you look, write down two to five words this concept may already
   be called here: synonyms, the word a neighbouring pipeline stage uses, the UI copy's word. They
   go to `--also`. This step catches an idea that already exists under another name.
4. **Check the graph, then locate.**
   `tools/naming.py look Name1 Name2 --also word1,word2`. A term the graph holds fresh comes back
   as its senses: trust them and don't re-read the code. Every other term comes back as a digest:
   each identifier containing it (lines, files, where it's declared, one example), then prose
   (comments and test names), string literals and UI copy.
5. **Interpret** every term marked `interpret` or `STALE`: sort its identifiers into senses
   (meanings), opening a declaration when the name alone doesn't tell you. Write them to a JSON
   file (format: `tools/naming.py record --help`) and run `tools/naming.py record FILE`.
   - A sense is a meaning, not a spelling: `regions`, `regionCount` and `RegionMap` can be one
     sense; `cell` can be two (`files` globs split one spelling by place).
   - A definition is one line, true of every identifier the sense claims.
   - Give prose (`"prose": true`) to the sense the comments mostly mean.
   - Put system APIs and unrelated words in `ignore`, so that what stays unsorted is worth a look.
   - When senses of two terms are one concept under two names, add an `aliases` pair with the
     reason: a synonym is the drift this tool exists to catch.
   - When a term is stale, keep the slugs it already has where they still fit.
6. **Report.** `tools/naming.py report "<the sentence>" Name1 Name2 --also word1,word2`: one table
   per name with each sense, its meaning, how many places use it and two examples.
7. **Answer** with the report, then three lines: which existing sense, if any, is this concept;
   which candidates collide, and with what; your recommendation and its one reason. Paul decides.
   Record his ruling only on his word, with
   `tools/naming.py decide Name --sense term/slug --meaning "…" --banned word,word --reason "…"`,
   which also rewrites `GLOSSARY.md`.

A decision that applies shows first in the report. Follow it. If you think it's wrong, tell Paul;
don't work around it.

Commit `tools/naming/graph.jsonl` (and `GLOSSARY.md` after a decision) with the work that asked
the question. The next session reuses the senses you recorded instead of reading the code again.
`GLOSSARY.md` is generated: after a merge that touched the graph, or on a conflict in it, run
`tools/naming.py glossary` and commit what it writes.
