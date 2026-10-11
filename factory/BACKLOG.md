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
Branch `codex/f1-v0-fixes`. From Claude's review of 8c5683e (a render plus a reading). Each fix
comes with a test that fails before it and passes after.
1. **Leg reach.** The pelvis leads both feet, so the trailing foot sits up to 1.04 steps behind
   it, and the defaults use 99.65% of the leg (`Rig.swift:216-219, 253, 268`). `ikClamps` fails
   for `motion.step` above about 0.184 (the spec allows 0.4), for path slopes above about 10° at
   depth 0.5, for the spec's own example (`to` 0.6), and for paths toward the viewer.
   - Center the pelvis over the feet, and lower it as the step lengthens.
   - Under a clamp, draw the clamped ankle, never the unreached target (`Rig.swift:268`).
   - Test: zero clamps over a sweep of step (0.08–0.4), depth (0–1), slope (up to 30°) and
     heading (all 16).
2. **Reverse checks that can't fire.** `kneeReverse`/`elbowReverse` compare a vector with its own
   projection (`Rig.swift:286`), and `kneesBendForward` (Tests:100) is circular. Measure the bend
   against the heading. Test: a pose built with a reversed knee fails.
3. **Elbows.** They bend forward like knees, and pop by about 0.1 figure heights when a cast arm
   crosses 90° (`Rig.swift:182, 260`). Elbows bend back for hanging and swinging arms and outward
   for raised arms, with a pole that never flips. Test: the largest elbow jump between frames
   stays under a small bound through a cast.
4. **The cast must read from any heading.** Release raises the arms up and outward, hands above
   the head and spread wider than the shoulders, not only toward the heading: facing the viewer,
   the arms vanished behind the body. Test: at release, facing the viewer, the hands are above
   the head and their screen spread is at least twice the shoulder width.
5. **The kerchief reads as a blindfold:** a band across the middle of the face. Make it cover the
   crown, with the knot behind when facing the viewer and the face clear. Test: no headwear
   shape crosses the middle third of the head when facing the viewer.
6. **Ink fill rule.** Use `nonzero` for ink (evenodd leaves holes where an outline folds over
   itself: about 5% at a 150° fold, `SVGWriter.swift:38`). Keep evenodd for the card's glyphs.
   Test: rasterize a hairpin stroke, no holes.
7. **Proportions.** `normalizationScale` includes `motion.bounce` (`FigureSpec.swift:24`), so
   tuning the bounce rescales the figure. `lean` and `hunch` are shears (`Rig.swift:242`), so
   the spine stretches. Make both rotations that keep bone lengths. Tests: standing height is
   exactly 1 at any bounce; bone lengths are unchanged by lean and hunch.
8. **Defaults the Lamp can see.** `magic.size` 0.07 (sparkles were about 2 px), `motion.step`
   0.26 once fix 1 lands. Update `SPEC.md`'s table and `baseline.json`, and make `hero.json`'s
   walk cover a good stretch of the brook (`to` about 0.35).
9. **The baseline test.** `committedBaselineRetainsSpecDefaults` pins `baseline.json` to the
   defaults, but the baseline is meant to be tuned. Instead, test that it decodes and passes
   every check.
10. **Credits.** Drop the `ACKNOWLEDGEMENTS.md` section: the file is the app's credits, and the
    app doesn't ship FigureRig. `Charter.swift` keeps Bitstream's notice. Add one line to the
    root `CLAUDE.md` › Licensing and credits naming `Sources/FigureRig/Charter.swift`
    (Bitstream Charter outlines, Bitstream's license, factory only).
11. **Small:**
    - `verify.py:71` diffs against `HEAD` (always empty after a commit); diff against the
      merge-base.
    - `render.py` exits 0 when a check fails; exit non-zero.
    - `render.py` needs DejaVu Sans (line 89): say so in `--help`, or fail clearly.
    - `Scene.swift:53` error paths read `actors.Index 0…`; print `actors[0].timeline[1].do`.
    - The last partial walk step rushes the swing foot (`Rig.swift:155`); ease it like the
      others.

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
  - proposers see their own past names and how they fared;
  - the Georgian bar as a code check for name pieces (`GUARDIANS.md` › The shared bar): place
    names at most one in fifty, Georgian words at most one in thirty, against a list in
    `taste/glossary.json`; the prompts say the thread is felt, not named;
  - rename the seat `nina` to `robber-girl` in `panel.json`, with an alias so the two recorded
    runs (which say `nina`) still replay byte for byte.
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

### F12 · The palette gallery
Branch `codex/f12-palette-gallery`. A page, and later a section of the app (issue #16), showing
every color the Lamp named: the swatch, the name, who named it, the guardian's reason, what the
jury said, and whether Paul loved it.
- `tools/factory/palette_gallery.py` builds it from a run's records (`pieces/color-names/run/`:
  `slots.json`, `decision.json`, `proposals/`, `verdicts/`) plus Paul's checkpoint picks
  (`pieces/color-names/run/checkpoint.json`, which Claude exports when he is done).
- **A slow drop.** The gallery reveals colors on a schedule, `pieces/color-names/drops.json`
  (date, colors), which Claude drafts and Paul approves. The page shows only colors whose date
  has passed; a `--preview` flag shows all. The app has no server, so in the app this becomes
  date-gated content bundled with a release.
- The look follows the collection page (`tools/factory/collection_template.html`).

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
