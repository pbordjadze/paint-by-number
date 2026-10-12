# The design-loop kit

The kit draws a panel, writes model-agnostic jobs, checks replies, decides and replays. Its
deterministic loop never calls a model; runners and the opt-in pet driver handle dispatch. Use `factory/taste/loop` (add `factory/taste` to PATH for `loop`), or
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
`[caps]` supports `georgian` (off by default) and maximum repeated two-word `lead`/`trail` counts.
Opting into `georgian = true` caps place names at one in fifty and cultural words at one in thirty,
using `glossary.json`. The glossary also explains ordinary cultural words to Originality.
`plants` is an array
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

`new` freezes settings, prompt version, brief, approved `factory/STYLE.md` if present, seats, glossary, initial
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

The Codex runner derives a strict transport schema at dispatch: required, closed objects,
types, enums and `anyOf` unions. Uniqueness, bounds, string lengths and exclusive `oneOf`
checks stay in the full `reply_schema` used by collection. Frozen jobs are never rewritten
for transport changes, so completed replies remain reusable on resume.

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

## Play before the Mac

The simulator host driver and the Swift UI-test mailbox contract are documented in
[the play piece README](../pieces/play/README.md). `play new --driver simctl` boots and installs
the app, runs the test and collects guardian file replies in the foreground; the recorded mock
remains the default. Both kinds of session replay offline through F17's mock.

The `play` piece uses sequential turns rather than design candidates and a jury. Its settings
are `factory/pieces/play/piece.toml` (move budget, recent-history length, player model and effort),
with a brief and `moves.schema.json`. A session freezes these and the chosen guardian's charter.
The kit's runners consume its jobs unchanged; the loop itself never calls a model.

Moves are strict JSON objects, tagged with `do`. Unknown actions, extra or missing fields, wrong
types, nonfinite numbers, and out-of-range area numbers are rejected with reasons:

| Move | Example |
| --- | --- |
| Fill a numbered area | `{"do":"fill","area":1}` |
| Tap an accessibility label | `{"do":"tap","label":"Paint 1"}` |
| Drag in screenshot pixels | `{"do":"drag","from":{"x":20,"y":30},"to":{"x":80,"y":60},"steps":12}` |
| Wait | `{"do":"wait","seconds":0.5}` |
| Take another screenshot | `{"do":"screenshot"}` |

Area and paint numbers are positive integers; `steps` is a positive integer. Coordinates and
seconds are finite, nonnegative numbers. A driver state has exactly `screen` (nonempty string),
`selected_paint` (positive paint number or `null`), `filled_areas` (unique area numbers starting at
1), and `area_count` (nonnegative integer). Area numbers must fit the count. The move budget
counts all accepted moves, including waits and screenshots. A session stops at that budget or
when all areas are filled, including an initially complete picture.

The portable `Driver` protocol in `play.py` exposes `screenshot() -> Path`, `state() -> dict`,
`perform(move)`, and `settle()`. `perform` initiates the move; `settle` waits until screen and
state can be read. A rejected move must leave the driver unchanged. The Mac's later driver
implements this interface, including real wait timing. Python callers use
`Session.create(outside_repo_path, driver, guardian_id, budget=100)`, then `job()` and `collect()`;
`apply({"move":…, "reason":…})` is also available for canned playback.

For Linux, a mock folder contains images and `recording.json`:

```json
{
  "version": 1,
  "initial": {
    "screenshot": "000.png",
    "state": {"screen":"painting", "selected_paint":1, "filled_areas":[], "area_count":1}
  },
  "turns": [{
    "move": {"do":"fill", "area":1},
    "screenshot": "001.png",
    "state": {"screen":"painting", "selected_paint":1, "filled_areas":[1], "area_count":1}
  }]
}
```

Screenshot paths are relative to that folder and cannot escape it. The mock requires each
recorded move exactly, advances on `settle`, and never sleeps for recorded waits. Unexpected
moves and exhausted recordings are rejected. The CLI freezes the recording in the session's
`driver/` folder so successive processes resume from the same inputs.

```sh
export LOOP_RUN=/root/factory-out/play-session
factory/taste/loop play new --recording /root/factory-out/mock-picture --guardian moon --budget 100
factory/taste/loop play jobs
# Dispatch jobs/001/player-moon.json through a separate runner.
# Save {"move":{"do":"fill","area":1},"reason":"Fill the first numbered area."}
# as replies/001/player-moon.json, then:
factory/taste/loop play collect
# Repeat jobs/collect while session.json says active.
factory/taste/loop play report
factory/taste/loop --out /root/factory-out/play-replay play replay
```

Each job includes the charter, latest screenshot path and image, state, and recent moves/reasons.
Replies have exactly `move` and a nonempty one-line `reason`. Missing replies exit 1 as waiting;
a rejected reply records the reason and writes one repair job in `retries/NNN/`. The runners write
its answer to `replies/NNN/player-<guardian>.retry.json`. A failed repair blocks the session.
Rejected moves do not advance the mock or consume the budget.

`initial.json`, `turns/NNN.json` and `screenshots/` preserve each observed state and original image
bytes; turns also contain the guardian, move and reason. `session.json` reports `active`, `complete`
or `budget`. `contact.png` shows the initial screen and every turn. Replay performs the recorded
moves through the mock and compares initial/turn/session records, screenshots, frozen rules and
contact sheet byte for byte in a fresh directory. Jobs, replies, rejections and costs remain source
inputs. `play replay --recording <folder>` additionally checks against an independent recording.

```sh
TMPDIR=/root/factory-out PYTHONPYCACHEPREFIX=/root/factory-out/pycache \
python3 -m unittest discover -s tools/factory -p test_play.py -v
```

Set `PLAY_DRY_RUN` to a fresh outside-repo directory to retain the canned three-area session,
mock frames, contact sheet and independently checked replay. These are plumbing checks; no live
guardian or app is run on Linux.

## Linux factory checks and build paths

Use the host Swift toolchain. `FIGURES_BIN` selects the already built figures executable for
`tools/factory/verify.py`, its review subprocess and the Python integration tests. Verification
also accepts `--figures`. A missing executable is reported before any output is created.
`SWIFT_SCRATCH_PATH` selects the Swift build/test directory for verification and the nested
hairpin test in `test_render.py`; verification also accepts `--swift-scratch-path`. Build the
Swift tests there before running Python tests, because the hairpin probe uses `--skip-build`.

```sh
export SWIFT_SCRATCH_PATH=/root/factory-out/swift-build
swift build --scratch-path "$SWIFT_SCRATCH_PATH" -c release --static-swift-stdlib
swift test --scratch-path "$SWIFT_SCRATCH_PATH"
export FIGURES_BIN="$SWIFT_SCRATCH_PATH/release/figures"
TMPDIR=/root/factory-out FACTORY_TEST_OUT=/root/factory-out PYTHONDONTWRITEBYTECODE=1 \
python3 -m unittest discover -s tools/factory -p 'test_*.py'
tools/factory/verify.py /root/factory-out/verification
```

Job IDs are nonempty ASCII slugs (letters/digits separated by `-` or `_`); rounds are positive
integers and attempts are `0` or `1`. Runner replies, costs, scratch artifacts and legacy
transcript extractions share the same containment checks and refuse symlinked paths.
The panel-name piece compares its accent/punctuation/article-normalized identity, the color
piece uses case folding, and generic pieces use case folding. These identities also govern
whole-set repairs, guarantees and assignment search; displayed and recorded names stay verbatim.
The kit and review CLI help exits before rendering, regenerating fonts or loading optional
dependencies.

## Codex runs the Lamp

F36's opt-in driver composes the kit's read-only Codex runner with separate local pet workers.
It implements the seven-step pets plan and preserves primary and comparison answers for the
model/taste experiment. [Decisions and records](../pieces/pets/codex-lamp/README.md) document
resumption, failure handling, local acceptance and the historical-replay transport difference.
No pet-service or ChatGPT Library operation is authorized. This sandbox cannot launch live models;
Claude should run these commands on the authenticated host with the installed v2 create-pet skill:

```sh
mkdir -p /root/factory-out/F36/tmp
export TMPDIR=/root/factory-out/F36/tmp
export FACTORY_TEST_OUT=/root/factory-out/F36
export PYTHONDONTWRITEBYTECODE=1

python3 -m factory.taste.codex_lamp run /root/factory-out/F36/lamp \
  --model gpt-6-astra --compare gpt-6.1-sol --effort high --parallel 4 --image-workers 3
python3 -m factory.taste.codex_lamp replay /root/factory-out/F36/lamp \
  --pieces chapter-6,renumber,front-door --models gpt-6-astra,gpt-6.1-sol --effort high --parallel 4
python3 -m factory.taste.codex_lamp compare /root/factory-out/F36/lamp
```

Re-run the same command to resume; completed calls are skipped and tallies rebuilt. Keep model,
effort and sources fixed for a run. To apply current guardian charters to steps that have not
started, run `python3 -m factory.taste.codex_lamp refresh-inputs /root/factory-out/F36/lamp
--reason 'Use the revised guardian charters for remaining steps.'` before resuming.
The original `inputs.json` stays intact. Immutable snapshots in `input-revisions/` and an atomic
`provenance.json` record the reason, time, input hashes and started steps. A step freezes its
revision before dispatch: partial rounds and unfinished model pairs retain that revision.
Only charter text changes; seeds, rules, glossary and chapter evidence remain frozen. Repeating
an unchanged refresh does nothing. Comparison reports separate input revisions in both paired
results and aggregates. Historical replays continue to use their original sources.
`--skill-dir /absolute/path/to/skills/create-pet` overrides
automatic installed-skill discovery. Text concurrency defaults to four; pet workers default to
three and can be reduced to one or two. Each image worker uses workspace-write with only
`/root/factory-out` as its writable root (including its working directory), automatic approval
requests disabled, and implicit `/tmp`/`TMPDIR` roots excluded. Agents are explicitly instructed
to keep task files under their F36 attempt folder and never use pet-service or Library tools.
The parent alone copies validated packages into `factory/pets/`.

Pilots intentionally start without a family reference. The image jury chooses a pilot from the
winning style as the fixed reference for every final pet and redo. New proposals state the exact
v2 geometry and row counts; hatch workers apply that contract over technical conflicts in old
style sheets, keeping their taste and recording each override and autonomous decision in provenance.
Style-sheet motion numbers guide the drawing; only the skill's validators gate a pet. Workers
record target versus observed motion in their decisions rather than spending repairs on those
numbers. No worker asks for clarification. Rerunning a stopped legacy run retries zero-generation
pilots blocked by the old reference, contract or clarification instructions, and the pilot that
failed solely on the old numeric jump-lift gate. Each gets one migration attempt, preserving the
failure, art and logs. Genuine validation failures and provider refusals remain failures.
Dispatched text prompts, replies, replays and comparison files stay intact on resume.

Without repairs, the pet run makes **138 driver-launched `codex exec` calls**: 63 primary text/image
jury seats, 51 comparison text seats, and 24 hatch workers (four pilots plus twenty final pets).
An optional second style round adds 50; each flagged brief adds two; each pet redo adds one,
plus six seats to review the replacements. Invalid replies can add one repair call per job,
with the validation errors and previous reply. The skill may also use independent internal visual reviewers; those are additional
to the driver count. Historical replay adds **114 calls**, comparing with 57 saved Claude seats.
`compare` makes none: **252 driver calls** for the basic run plus full replay.

V2 has a **312-image-generation floor** for the four pilots and twenty pets (13 each, versus the
old v1 estimate of ten). The recorded pilots used 13–21 generations per pet: budget roughly
312–504 before jury redos, with provider failures or technical repairs changing that number.
A complete regenerated pet adds about 13 more; row-only redos may use fewer. Live CLI auth/plugin
startup, image-tool availability in `codex exec`, structured schema support, reference-image limits,
and many-image jury context remain unproven here. Frozen prompts explicitly carry style/avoidance
notes into the v2 look jobs and ask workers to combine complete reference sheets when the tool's
five-reference limit would otherwise be exceeded. Passing fake calls proves orchestration, not
visual quality or the consistency of a generated family.

Offline checks use a fake `codex` on PATH and the installed **real** atlas/quality validators.
Synthetic test pixels are never copied into this repository:

```sh
TMPDIR=/root/factory-out/F36/tmp FACTORY_TEST_OUT=/root/factory-out/F36 PYTHONDONTWRITEBYTECODE=1 \
python3 -m unittest discover -s tools/factory -p test_codex_lamp.py -v

swift build --scratch-path /root/factory-out/F36/swift-build -j 4
swift test --scratch-path /root/factory-out/F36/swift-build -j 4 --no-parallel
TMPDIR=/root/factory-out/F36/tmp FACTORY_TEST_OUT=/root/factory-out/F36 PYTHONDONTWRITEBYTECODE=1 \
SWIFT_SCRATCH_PATH=/root/factory-out/F36/swift-build \
FIGURES_BIN=/root/factory-out/F36/swift-build/debug/figures \
python3 -m unittest discover -s tools/factory -p 'test_*.py'
```
