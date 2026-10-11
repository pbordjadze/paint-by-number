# Factory backlog

Work for Codex, specified by Claude, reviewed by Claude before it is merged. The architecture is
`ARCHITECTURE.md`; the engine's contract is `SPEC.md`; the taste loop's code is `taste/`, and its
two runs are `pieces/panel-name` and `pieces/color-names`.

## How to work an item

- Read the root `CLAUDE.md` first: its rules hold here (determinism, saved data, licensing,
  "Scratch output goes outside the repo").
- Branch `codex/<id>-<slug>` from `origin/claude/vibe-factory`, one item per branch. Never push to
  `claude/*` branches, `main` or `sidestore`.
- Every commit message carries `[skip ci]`: GitHub's macOS runners are rationed. Verify on Linux
  instead (`tools/swift.sh` or a local Swift 6.2 toolchain, Python, node).
- Stay inside the item's scope. If the item is wrong or unclear, stop, and say so in the report
  rather than guessing.
- Finish with a short report: what changed, what you verified and how, what you were unsure of.
- Don't edit this file; Claude keeps it.

## Ready

### F1 · v0 review fixes
*Depends on Claude's review of 8c5683e; Claude adds the list here.*

### F2 · The taste loop as a library
Branch `codex/f2-taste-loop`. Today `taste/taste.py` (the panel-name run) and `taste/colors.py`
(the color-names run) each carry their own draw, ballots, scoring and ledger. Make one loop with
pieces as plug-ins.
- `taste/loop.py`: seeded draws by the ledger; per-juror shuffled ballots; scoring (Borda points
  × weight: `panel.json` base weight × the ledger boost × an optional calibration factor);
  vetoes; one name per slot; the style guide's caps as a piece hook; the "everyone gets a slot"
  guarantee as an option; the ledger.
- `taste/transcripts.py`: read an agent's final reply (its `SubagentHandback` message) from a
  Claude Code transcript `.output` file, as `colors.py extract` does.
- `taste/pieces/panel_name.py` and `taste/pieces/color_names.py`: today's two pieces as plug-ins
  (brief, proposer and juror prompts, craft checks, slots, rendering in use).
- **Rules are versioned per run.** A run records the rule set it used, and old runs replay under
  their own rules. Rules v1 is the panel-name run's; v2 is the color-names run's: a veto must
  quote the charter's "guards against" line, and the guarantee runs after uniqueness and caps.
- **Chapter 1's fixes** (`How the Panel Named Itself`, and `NOTES.md`):
  - an Originality glossary (`taste/glossary.json`, the Georgian words in the charters: supra,
    qvevri, tonir, …) that Originality's prompt includes;
  - standings that report the broad favorite and the most-loved (most first places) separately;
  - a hook for a second jury on the finalists;
  - proposers see their own past names and how they fared.
- Tests (pytest, under `tools/factory/` beside `test_render.py`): replaying both recorded runs from
  their files reproduces their `decision.json` and ledger byte for byte; unit tests for draws,
  scoring, vetoes, uniqueness, caps and the guarantee.

### F4 · Versioned nickname vocabularies (PaintCore and pbn only)
Branch `codex/f4-vocabulary-versions`. The design is `pieces/color-names/brief.md` › "Never
rename a saved painting". This item covers only PaintCore and pbn, no app changes.
- Before touching anything, record pins: `pbn names` output for six templates (the six
  `Tests/Corpus` photos), three seeds each. After the change, the same commands give the same
  bytes.
- `ColorNickname.Vocabulary`: version 1 is today's table, verbatim, with a test pinning its
  SHA-256. `assign(_:seed:version:)` with version 1 gives exactly today's names. Add
  `currentVersion = 1`.
- The style-guide lints become a library oracle, `Vocabulary.problems()`, used by
  `ColorNicknameTests` and by a new `pbn vocab check <table.tsv>`.
- `pbn names --vocabulary N` and `--nickname-table <file.tsv>`: the latter assigns from a
  proposed table, for the color loop's renderer. Update the `main.swift` usage header.
- No template, regression baseline or `pipelineVersion` changes. Run `swift test` and
  `tools/regression.py` (no `--update`) to show nothing moved.

### F5 · Nickname traffic
Branch `codex/f5-nickname-traffic`. `tools/factory/nickname_traffic.py`:
- make templates of the 45 library pictures (`App/PaintByNumber/Resources/Samples/`, converted
  to PPM) with pbn at the app's default settings;
- run `pbn names` with five seeds each;
- count how often each anchor is drawn and write `factory/pieces/color-names/traffic.json`
  (index, hex, name, draws, share), sorted by draws. Deterministic: the same run gives the same
  file.

Temporary templates go outside the repo. The color loop uses this file to choose which anchors
matter most.

### F6 · Pets on the collection page
Branch `codex/f6-collection-pets`. `tools/factory/collection.py` builds the Lamp's page from
`GUARDIANS.md` and `panel.json`. When `factory/pets/<id>/spritesheet.webp` exists, show that pet
in place of the letter circle, animated with CSS `steps()` over its idle row. The atlas is
192 × 208 cells, eight columns, nine rows; idle is row 0, six frames of 280, 110, 110, 140, 140
and 320 ms. Respect `prefers-reduced-motion`: show the first frame still. Test with a generated
placeholder atlas; never commit a real pet as a fixture.

### F7 · Pet pilot
Branch `codex/f7-pet-pilot`. Codex-native; uses Codex's image budget. Read the plan first,
`pieces/pets/brief.md`.
1. Does `codex exec` run the `hatch-pet` skill non-interactively? Try it.
2. Hatch one throwaway test pet end to end: a plain, neutral teapot, not a guardian, with no
   style decisions. Validate it with the skill's `validate_atlas.py`. Keep the files outside
   the repo.
3. Write `factory/pieces/pets/pilot.md`: the commands that worked, wall time, the number of image
   generations, the usage meter before and after, what failed and how it was fixed, and whether
   the skill can take shared style notes and reference images the way the plan assumes.

### F8 · Pipeline snapshots
Branch `codex/f8-snapshots`. For the making-of show: the pipeline's intermediate pictures,
without changing a single template byte.
- `TemplateGenerator.generate(…, observer:)`, an optional callback that receives each stage's
  picture: the working image, the structure map, the smoothed image, the palette with its label
  map, the simplified regions, the line art (books), and the vectorized boundaries. Pictures are
  downscaled to at most 1024 px on the long side.
- A nil observer costs nothing and changes nothing. A test generates with and without an observer
  and compares the encoded templates. `tools/regression.py` must report every template the same.
  No `pipelineVersion` bump.
- `pbn generate --snapshots <dir>` writes them as PPM/PGM, named by stage. Update the usage
  header.
- Determinism: snapshots are byte-identical across runs and core counts.

## Needs a spec first (Claude)

- **F3 · The figure piece** for the taste loop: proposals edit the figure spec, the engine
  renders, jurors judge the sheets. After F1 and F2.
- **F9 · Reveal fields:** for each pipeline stage, a map of when each pixel changes, which the
  show's wipes and the workers follow. After F8.
- **F10 · Figure engine v1:** props (the broom, the mortar and pestle), actions (sweep; ink a line
  with the brush tip pinned to it), several actors.

## Waits on CI (rationed macOS runners)

- **F11 · Versioned vocabularies in the app:** the version in `meta.json`, and a pin in
  `App/PaintByNumberTests` so Apple's math is checked. After F4, and when Paul releases CI
  minutes.
