# Chronicle

What Paul's Claude sessions on Paint by Moonlight did, kept by the record-keeper session.
This branch has no history in common with `main` and no CI; `main` never carries it.

- `story/<date>.md`: the night told as a story, one per working day (UTC), written by hand.
  Read this.
- `log/<date>.jsonl`: the same night as data, one event per line, oldest first. Parse this.
- `sessions.json`: every session the chronicle has met, keyed by id.
- `render.py`: builds `site/index.html` (the published page) from the three.

## An event (`log/*.jsonl`)

| field | |
| --- | --- |
| `at` | UTC, ISO 8601, to the second |
| `session` | session id (`session_…`), or `paul` for something he did outside a session |
| `kind` | `start`, `ask` (needs Paul), `decision` (Paul decided), `idea`, `work` (progress worth a line), `ship` (pushed or merged), `ci`, `block`, `review`, `end`, `note` |
| `text` | one or two plain sentences, the record keeper's words |
| `paul` | optional: Paul's words, verbatim |
| `branch`, `sha`, `row` | optional: branch, commit, `docs/backlog.md` row |

Fields are only ever added. Each session's own transcript stays the detailed record; this keeps
what a reader needs a week later.
