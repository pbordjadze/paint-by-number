# The design-loop kit

The kit draws a panel, writes model-agnostic jobs, checks replies, decides and replays. It never
calls a model. Use `factory/taste/loop` (add `factory/taste` to PATH for `loop`), or
`python3 -m factory.taste`. Python 3.11+ and Pillow are the only dependencies. Records are JSON;
render output and runner scratch files belong outside the repo, normally `/root/factory-out`.

## Make a piece: panel-name worked example

A piece directory has `piece.toml` and a brief. The shipped `pieces/panel-name/piece.toml` uses
the panel-name adapter's existing brief, craft checks and three examples of a name in use.
Create a fresh run; this leaves the recorded panel run alone:

```sh
export LOOP_RUN=/root/factory-out/panel-design
export FACTORY_OUT=/root/factory-out/panel-review
factory/taste/loop new panel-name
factory/taste/loop draw 1
factory/taste/loop jobs 1          # proposer jobs (and writer if enabled)
# Dispatch jobs/001/*.json; put final JSON in replies/001/<job-id>.json.
factory/taste/loop collect 1       # craft checks, slate, blind juror jobs
# Dispatch the juror jobs; put final JSON in replies/001/juror-<guardian>.json.
factory/taste/loop collect 1
factory/taste/loop decide 1
factory/taste/loop checkpoint     # checkpoint.html under FACTORY_OUT
factory/taste/loop report         # standings, representation ledger, tokens and seconds
# Repeat draw/jobs/collect/decide for rounds 2 and 3.
factory/taste/loop --out /root/factory-out/panel-replay replay
```

For a new question, copy that TOML, set `[piece] id = "garden-gates"`, `adapter = "generic"`,
write `brief.md`, and add `slots.json`:
`[{"slot":"1","incumbent":"Old Gate"},{"slot":"2","incumbent":"Other Gate"}]`.
Run `loop new /path/to/garden-gates`. Optional `base.json` holds the rest of a set for uniqueness
and caps. Slots may carry `hex` for swatches, `images` (paths relative to the piece), and `index`
to join the base set. `[piece] context = ["{name} welcomes you through gate {slot}."]` renders
text in use. A slot can supply `candidate_schema`, a JSON Schema object requiring `name` and
`why`, plus `images` and/or a structured `value` for parameters. The default is name/why only.
The supported schema keywords are documented in `schema.py`; unsupported keywords fail closed.
Canned or agent replies may provide absolute image paths; contact sheets show only ballot letters.
Render proposed parameter files with your piece's renderer before collecting them. Parameter values,
images and the chosen design carry into the next round. The `panel-name` and `color-names` adapters
reuse their own craft oracles. Generic pieces use schema validation and uniqueness as craft checks.

## Settings and jobs

TOML requires `rounds`, `jury_size` (including Originality), `proposers`, `candidates_each` per slot,
`scoring = "borda"|"approval"|"copeland"`, `veto_policy = "quote"|"free"|"off"`, `guarantee`,
and `rules_version = 1|2`. Each `[roles.proposer]`, `[roles.juror]`, `[roles.writer]` has a `model`,
`effort` and `enabled`; proposer and juror are required, writer is optional and offers one candidate
per slot. Model and effort strings are passed unchanged; choose identifiers your runner supports.
`[caps]` supports `georgian` and maximum repeated two-word `lead`/`trail` counts. `plants` is an array
of `{slot="1", name="Beeswax", quality="good"}` or `quality="bad"` anchors. Anchors bypass craft
so deliberate defects reach the jury; their quality and source are hidden, and they cannot win.
The color example's good anchor is the recorded jury's winner, not a claim about Paul's approval.
`guarantee = true` requires a slot for each drawn proposer; vetoes, uniqueness and caps still hold.

The `figure` adapter (`factory/pieces/figure/piece.toml`) accepts one to three
`{"patch":{"figure":{"headSize":0.18}},"why":"One-line reason."}` candidates for slot `1`.
It freezes `factory/specs/baseline.json`, the v1 field ranges, and the hero scene/background at
`new`. Every patch applies to that baseline; omitted fields stay and arrays replace whole arrays.
Collection rejects bad fields with their names, then runs `tools/factory/render.py` on every
distinct patch, including the incumbent. All geometry and pixel checks in `checks.json` must
pass. Rejections are recorded in `rounds/NNN/rejected.json` before juror jobs exist.
Candidates use internal spec digests; jurors see only their own shuffled letters, charter and
four image paths per candidate: contact, at-size light/dark, and silhouette. These sheets retain
their native pixels with a letter header. No proposer names, reasons or patches reach the jury.
Figure runs require rules v2, quoted vetoes, and no plants or writer that could bypass craft.

Use the same `new figure`, `draw/jobs/collect/decide/replay` sequence above. On Linux, build with
`swift build -c release --product figures --scratch-path /root/factory-out/figure-build`, and set
`FIGURES_BIN=/root/factory-out/figure-build/release/figures` before collecting. The renderer needs
node with `tools/node_modules`, Pillow, DejaVu Sans and ffmpeg. A canned CLI dry run, including a
failed range, a failed engine check and byte-identical replay, can retain review artifacts:

```sh
TMPDIR=/root/factory-out PYTHONPYCACHEPREFIX=/root/factory-out/pycache \
FIGURES_BIN=/root/factory-out/figure-build/release/figures \
FIGURE_PIECE_REAL=1 FIGURE_PIECE_DRY_RUN=/root/factory-out/figure-dry-run \
python3 tools/factory/test_figure_piece.py \
  FigurePieceTests.test_canned_cli_dry_run_blind_sheets_and_byte_identical_replay -v
```

Choose a fresh dry-run directory. Its rankings are canned plumbing checks; the Lamp's later run
makes the taste decision. Without `FIGURE_PIECE_REAL=1`, the tests use small stand-in sheets.

`new` freezes settings, brief, approved `factory/STYLE.md` if present, seats, glossary, initial
slots, vocabulary and calibration in `rules.json`. Later piece/panel edits do not change the run.
Jobs are `jobs/NNN/<role>-<guardian>.json`: `prompt`, `reply_schema`, `model`, `effort`, `images`,
plus identity and attempt. They and blind ballots are immutable. Proposers see their past reception;
jurors see shuffled letters and text/swatch/image sheets without proposer attribution. Replies
must match the schema exactly, including every slot and a complete unrepeated ranking; approval
also requires an explicit approval list (empty is allowed). Originality only vetoes.
A malformed reply creates `retries/NNN/<job-id>.json` with the error and original reply. Send it
back to the same agent once and write `replies/NNN/<job-id>.retry.json`. A failed repair blocks
collection/decision explicitly. Waiting or rejected collection exits 1; it never guesses a reply.

## Runners, checkpoints and calibration

Claude orchestration reads each job and dispatches its prompt/model/effort/images; the separate
adapter imports the final `SubagentHandback` through `transcripts.py`. Codex uses read-only
`codex exec --json --output-schema … --output-last-message …` in an outside-repo scratch root
([official interface](https://developers.openai.com/codex/noninteractive/)). Run adapters explicitly:

```sh
python3 -m factory.taste.runners --run "$LOOP_RUN" claude "$LOOP_RUN/jobs/001/proposer-moon.json" /path/agent.output
python3 -m factory.taste.runners --run "$LOOP_RUN" codex "$LOOP_RUN/jobs/001/juror-moon.json" --out /root/factory-out/codex-jobs
factory/taste/loop calibrate /path/checkpoint.json    # writes calibration.json under FACTORY_OUT
factory/taste/loop --run /root/factory-out/next new panel-name --calibration /path/calibration.json
factory/taste/loop gallery --picks /path/checkpoint.json
```

The checkpoint saves `slot,name,veto,love,note,at` to `checkpoint/c<slot>` using the same Claude
owner/database interface as Thirty-Six Colors. It adds `round` for later rounds. Outside Claude it
saves locally and exports `checkpoint.json`; it does not publish anything. Love and veto are
exclusive. The gallery shows names, makers, proposer reasons, jury evidence and Paul's annotations.

The Marginarium's palette page follows the collection page's night ground and puts each jury's
notes beside its swatch. Build it with
`python3 tools/factory/palette_gallery.py --out /root/factory-out/F12/gallery.html`, or add
`--preview` to see all colors. It reads `pieces/color-names/run/` and Paul's `checkpoint.json`
export (an array, a checkpoint-record map, or a `{ "by": "Paul", "picks": [...] }` envelope).
Vetoed names use the export's `replacement`; the original name and veto remain in the margin.
Reasons are quoted from proposals; jury reasons identify the name that juror preferred.

Claude drafts `factory/pieces/color-names/drops.json` and Paul approves it. Its format is an array:
`[{ "date": "2026-10-11", "colors": [1, 2] }]`, where colors are slot IDs, each listed at most once.
This is a format example, not an approved schedule. Without a schedule, only preview builds work.
Drops open at midnight UTC on their date; unscheduled and future colors are absent from the HTML.
Rebuild the static page when a drop is due. `--as-of YYYY-MM-DD` pins the date for review;
`--run`, `--checkpoint`, and `--drops` select other inputs. Output always stays outside the repo.
The app's later section can use the same dates in bundled content; this generator changes no app code.

Calibration compares every loved candidate against its alternatives (reversed for a veto). It scores
jurors' rankings and proposer sources separately, with evidence counts and smoothed factors
`0.5 + (agreements + 1)/(pairs + 2)`. Notes alone imply no preference. Factors affect future runs:
juror factors multiply base weight and ledger boost, source factors multiply final candidate scores.
Borda is n−1…0; approval awards one weighted point per approved candidate; weighted Copeland
awards one point per pairwise win, half per tie, zero per loss. Originality never scores.
Cost reports count tokens and elapsed seconds per agent/attempt from Claude transcripts and Codex
JSONL, deduplicate streaming usage, include cached input, and mark unmeasured fields `null`.
No dollar price is invented; an API runner can later consume the same jobs and reply paths.

## Replay and checks

`loop --run <records> --out <fresh-directory> replay` rebuilds decisions and ledger in a copy,
including the two recorded runs. Legacy v1/v2 schemas and exceptions remain frozen; compatibility
CLIs `taste.py` and `colors.py` still work. New runs default to v2: quoted guards-against vetoes,
uniqueness/caps before the optional guarantee, deterministic repair of interacting constraints,
and separate broad-favorite/most-loved standings. Unknown rules versions fail.

```sh
export TMPDIR=/root/factory-out    # keep test scratch output outside the repo
python3 -m unittest discover -s tools/factory -p test_taste.py
python3 -m unittest discover -s tools/factory -p test_loop_kit.py
# With pytest installed: python3 -m pytest tools/factory/test_taste.py tools/factory/test_loop_kit.py
```
