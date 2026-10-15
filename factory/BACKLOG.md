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
  - standings that report the broad favorite and the most-loved (most first places) separately;
  - a hook for a second jury on the finalists;
  - proposers see their own past names and how they fared;
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
- make templates of every library picture (`App/PaintByNumber/Resources/Samples/library.json`, 44 today; converted
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
`pieces/pets/brief.md`. The skill is `create-pet` from the `work-pets` plugin
(`~/.codex/plugins/cache/openai-curated-remote/work-pets/<version>/skills/create-pet`), which
makes **v2** sheets: 1536 × 2288, 192 × 208 cells, eight columns by eleven rows (nine animation
states plus sixteen look directions); read its `references/sprite-sheet-contract.md`.
1. Hatch one throwaway test pet end to end: a plain, neutral teapot, not a guardian, with no
   style decisions. Use the skill's bundled scripts, including `validate_atlas.py --require-v2`
   and `validate_pet_quality.py`. Keep every file under `/root/factory-out/F7`, never in the repo.
2. **Do not upload, create, activate or update a pet, and do not save to any ChatGPT Library:**
   stop after the local validation and previews.
3. Write `factory/pieces/pets/pilot.md`: whether the skill ran non-interactively under
   `codex exec`, the commands that worked, wall time, the number of image generations, what failed
   and how it was fixed, and whether shared style notes and reference images can steer every pet
   the way the plan assumes.

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
- The look follows the collection page (`tools/factory/collection_template.html`). The gallery is
  part of the Marginarium, the app's storybook section (`NOTES.md` › Paul's point 8): each color's
  jurors' notes are its margin. Vetoed colors show their `replacement` from `checkpoint.json`, and
  the veto itself as a margin note. Build the page with the design-loop kit's page tools
  (`factory/taste/pages.py`) where they fit.

### F13 · The design-loop kit
Branch `codex/f13-loop-kit`. After F2. Turn the loop into a small kit any design question can
use: primitives, tools and settings, documented.
- **Settings per piece** (`pieces/<piece>/piece.toml`): rounds; jury size; proposers per round
  and candidates each; scoring (`borda`, `approval` or `copeland`); veto policy (`quote` the
  guards-against line, `free`, or `off`); the "everyone gets a slot" guarantee; caps; plants
  (known-good and known-bad anchors); the model and effort for each role (proposer, juror,
  writer); the rules version.
- **Model-agnostic agent jobs.** The kit writes `jobs/<round>/<role>-<guardian>.json` (prompt,
  reply schema, model, effort, images) and reads `replies/<…>.json`; it never calls a model
  itself. Runners are separate:
  - Claude subagents today, read back through `transcripts.py`;
  - `codex exec`, which gives a second model family on the panel;
  - an API runner later.

  A reply that breaks its schema goes back to its agent once.
- **Tools:**
  - renderers: a text in use, swatch sheets, image contact sheets lettered per juror;
  - the checkpoint page (Paul's veto, love and note, stored as on the Thirty-Six Colors page)
    and the gallery page generators;
  - calibration: score each juror and each proposer source against Paul's picks, and write the
    factors the scoring reads;
  - cost accounting: tokens and time per agent, from transcripts and Codex logs;
  - replay: re-decide any run from its records.
- **A CLI:** `loop new <piece>`, `loop draw|jobs|collect|decide <round>`, `loop replay`,
  `loop report` (standings, ledger, costs).
- **`taste/README.md`:** how to make a new piece, on one page, with the panel-name piece as the
  worked example.
- **Tests:** both recorded runs replay byte for byte; a toy piece runs end to end on canned
  replies.

### F9 · Reveal fields
Branch `codex/f9-reveal-fields`. For each pipeline stage the making-of show reveals, a map of
*when* each pixel changes, which the wipe and the walking workers follow. Builds on F8's
snapshots (`pbn generate --snapshots <dir>`). FigureRig and the `figures` CLI only; PaintCore,
pbn and the app are untouched.
- `RevealField.make(from: A, to: B, seed:)` for two consecutive snapshots of the same size. A
  pixel *changes* when the pictures differ: OKLab distance ≥ 0.02 for color pictures, more than
  8 of 255 for grayscale ones (structure, line art).
- Time per changed pixel, in [0, 1]: geodesic distance over changed pixels (8-connected,
  integer steps of 2 straight and 3 diagonal, breadth-first in raster order) from a seed set,
  divided by the largest distance. Seeds by option: `left` (the changed pixels of the leftmost
  column that has any; the default), `center` (the changed pixel nearest the center) or
  `strongest` (the pixels whose change is largest). A changed pixel unreachable from the seeds
  starts its own region at the largest time reached so far, regions in raster order. Unchanged
  pixels carry no time.
- **Worker paths:** split [0, 1] into K equal steps (default 12); for each step, the centroid of
  the pixels whose time falls in it (skip empty steps); the path is those centroids in order,
  smoothed with two rounds of Chaikin, written as absolute SVG path data in the snapshot's pixel
  coordinates, ready to use as a scene path.
- `figures reveal <snapshot-dir> <out-dir> [--seed left|center|strongest] [--steps K]` writes, for
  each consecutive stage pair present: `<from>-<to>.pgm` (0 = unchanged, otherwise
  1 + round(t × 254)) and `<from>-<to>.json` (`width`, `height`, `changed` fraction, `seed`,
  `steps`, `path`).
- `tools/factory/reveal_sheet.py <snapshot-dir> <reveal-dir> <out.png>`: per stage pair, six
  frames of the wipe (B shown where t ≤ the frame's time, A elsewhere) with the path drawn.
  Output outside the repo.
- Tests: synthetic pictures (only the right half changes → times rise left to right; nothing
  changes → empty field, no path; two separate blobs → both timed, raster order); every option;
  byte-identical output across runs; the PGM encoding. Run it on one corpus photo's snapshots and
  look at the sheet.

### F10 · Figure engine v1: props, two actions, several actors
Branch `codex/f10-engine-v1`. Extend `SPEC.md` (scene and spec version 2, documented beside
version 1, which must keep decoding) and the engine. **The hero scene must render byte for byte
as before** (a test pins its digests before the change).
- **Props**, drawn in the figure's ink style from shapes defined in code: `broom` (stick and a
  fan of bristles), `brush` (handle, ferrule, tip), `mortar` (bowl and pestle), `jar`. A scene
  actor may hold one (`"holds": "broom"`): it follows the hands and the forearm's direction, its
  length a fixed share of the figure's height. Props on the ground are scene items
  (`"props": [{"kind": "jar", "at": {"path": "brook", "t": 0.4}}]`).
- **`sweep`** `{ "do": "sweep", "path", "to" }`: walk the path holding the broom low in both hands;
  the broom head swings across the heading once per footfall.
- **`ink`** `{ "do": "ink", "path", "from", "to" }`: the actor walks beside the path, offset to its
  left by a share of its height; the right hand's brush tip is pinned to the path at the current
  arc length (two-bone IK to the tip; the walk sets the pace), and the inked stroke grows behind
  the tip in the ink style, staying drawn afterwards.
- **Several actors:** any number, each with its own seeded streams (wobble, particles); drawn far
  to near by their feet's screen y, ties by actor order.
- **Checks** (added to `checks.json`): the brush tip within 0.5 px of the inked path on every ink
  frame; a held prop's grip within 0.5 px of its hand on every frame; no two actors' pelvises
  closer than one hip width.
- A second committed scene, `factory/scenes/workers.json`, on `hero.svg`: one worker inks the
  brook while another sweeps along the hill. Render it with `render.py` and look at the sheets.
- Bump the engine's version; update `SPEC.md`'s tables and the CLAUDE.md map line if it changes.

### F3 · The figure piece
Branch `codex/f3-figure-piece`. A design-loop kit piece (`factory/taste`, F13) whose candidates
are figure specs. Codex builds the piece and dry-runs it; the Lamp runs it later, so no taste
decision is made here.
- `factory/pieces/figure/piece.toml` and a plug-in: a candidate is a patch of `FigureSpec` fields
  within `SPEC.md`'s ranges (rejected otherwise, with the field named), applied to
  `factory/specs/baseline.json`.
- Craft is the engine's own checks: a candidate whose `checks.json` fails is out before any
  juror sees it.
- The renderer runs `render.py` on `hero.json` per candidate and gives jurors the contact,
  at-size (light and dark) and silhouette sheets, each candidate's sheets under a shuffled
  letter.
- Proposer jobs ask for at most three patches with a one-line reason each; juror jobs carry the
  sheets as image paths and the charter, and ask for a ranking, reasons and vetoes (rules v2).
- A dry run with canned replies through `loop new/draw/jobs/collect/decide/replay`, and tests:
  out-of-range patches rejected, a failing check excludes a candidate, ballots shuffled and
  blind, replay byte-identical.

### F14 · Marginarium page polish
Branch `codex/f14-page-polish`. Two small fixes found in review.
- **Collection page, v2 pets:** `tools/factory/collection.py` sizes every atlas as v1
  (1536 × 1872). Read each `spritesheet.webp`'s size and accept v1 (1536 × 1872) and v2
  (1536 × 2288) sheets, scaling the background to the matching quarter size (384 × 468 or
  384 × 572); idle stays row 0. Reject any other size with a message naming the file. Tests
  with generated placeholder atlases of both sizes.
- **Palette gallery wording:** name the outside writer "the outside writer" and the incumbent
  "the name the app already had", and omit the reason line when a proposer gave none (the
  writer never does) instead of "No proposer reason recorded".

### F15 · Reveal paths a figure can walk
Branch `codex/f15-walkable-reveal-paths`. F9 emits a stationary `M x y` path when a field has a
single centroid, which `FigureScene`'s walk parser rejects. Give every reveal path a walkable
length (a short segment through the centroid along the wipe's direction, at least one step long),
and make the walk parser's error name the path and its length when it still refuses one. Tests
for both. Hero and workers renders stay byte for byte.

### F16 · The first making-of render
Branch `codex/f16-making-of`. The show the night began with: one picture, its pipeline stages
revealed one after another, a worker walking each reveal path while the wipe follows it, and each
stage's citation card. Factory only; no app code.
- `tools/factory/making_of.py <photo.ppm> <out-dir>` runs `pbn generate --snapshots`, then
  `figures reveal`, then writes one scene per stage pair (the worker inks for line-art stages and
  sweeps for the others, using F10's actions) and renders them with `render.py`, joined into one
  `making-of.mp4` with the wipe composited under the figures. Output outside the repo.
- **Citations:** `factory/scenes/making-of/citations.json` maps each stage to the paper whose
  method it runs, with authors, year and title copied exactly from `ACKNOWLEDGEMENTS.md`, and the
  line of that file each came from. A stage with no matching entry gets no card. Claude reviews
  this file before it is merged; never invent or reword a citation.
- Deterministic: two runs give identical frames. Test with a small photo from `Tests/Corpus`;
  look at the contact sheet. No taste decisions: timing and look use the spec's defaults, and the
  Lamp judges them later.

### F17 · The play loop, before the Mac
Branch `codex/f17-play-loop`. The half of the play harness (chapter 4, M2) that runs anywhere, so
the Mac only has to supply a real driver. Factory only; no app code.
- **Moves** as JSON with a schema: `fill {area}`, `tap {label}` (an accessibility label),
  `drag {from, to, steps}`, `wait {seconds}` and `screenshot`. Unknown or malformed moves are
  rejected with the reason.
- **A driver interface** (`screenshot()`, `state()`, `perform(move)`, `settle()`), and a mock
  driver that plays a recorded folder of frames and states so the loop can be tested on Linux.
  `state()` reports the screen, the selected paint, the filled areas and the area count.
- **A design-loop piece, `play`:** each turn writes a guardian's job (its charter, the latest
  screenshot path, the state, the last few moves) and reads back one move and a one-line reason;
  the loop performs it, waits for the screen to settle, and records the turn. A session ends at a
  move budget or when every area is filled.
- **Records:** every turn's move, reason, screenshot and state, replayable against the mock
  driver byte for byte, and a contact sheet of a session.
- Tests with the mock driver: a session that fills a three-area picture, a rejected move, replay.

### F18 · Pip and Colophon, the makers' pets
Branch `codex/f18-makers-pets`. Chapter 7: Codex keeps the test teapot as its pet, named **Pip**;
Claude's pet is a moth named **Colophon**. Hatch both with the `create-pet` skill exactly as in F7
(`pieces/pets/pilot.md`): v2 sheets, the bundled scripts and validators, every file under
`/root/factory-out/F18`, **no upload, no pet creation, no Library writes**.
1. **Pip, first.** Codex's teapot, redrawn: a plain white teapot with a round lid, hand-drawn and a
   little lopsided as if thrown by hand; **no face**; no steam; no pattern; no blue anywhere on the
   outside. One small blue dot sits beneath the lid, seen only when the lid lifts (show it in the
   waving or review row, where the lid lifts). Avoid: Mrs. Potts (*Beauty and the Beast*), the
   stock 3D-graphics "Utah" teapot profile, blue-and-white china. It is an object, so it shows its
   moods through posture and the lid, not a face.
2. **Colophon, second, drawn with Pip's sheet as a family reference.** A small, round, soft moth,
   never spindly; wings like two pale pages with a few hand-inked lines of invented marks: no real
   letters or words, no eyespots, no skull marking, no glowing eyes. It circles a lamp's glass
   once at a safe distance (never the flame, never singed); only the wing edge nearest the light
   catches warmth; it lands beside the words, folding its wings flat like a bookmark. Avoid:
   Mothra, Pokémon moths, the logo of The Moth, bookworm mascots.
3. Write `factory/pieces/pets/makers.md`: commands, image generations and time for each, what
   failed and how it was fixed, and **whether Colophon looks like Pip's family**, with what in the
   reference carried over and what did not. Put both final contact sheets and a side-by-side of
   the two idle rows under `/root/factory-out/F18`.

### F19 · The making-of at full size, with the real drawing
Branch `codex/f19-making-of-full-size`. F16's renders used thumbnails (144 × 96 and 64 × 43), so
the photo was a stamp on the paper and the worker towered over it. Render one corpus photo at its
real working size, as a coloring book from its committed maps. Factory only; no app code.
- `making_of.py` gains `--lines <drawing.pgm>`, passed to `pbn generate` as `--lines` beside
  `--edges`, exactly as `tools/regression.py` passes the book regime's two maps (read it; reuse
  its conversion of `tools/baseline/lines/<name>-{contours,drawing}.png` to PGM at the photo's
  size, outside the repo).
- Render `Tests/Corpus/parrots.jpg` (converted to PPM outside the repo) at full size with both
  maps. Fix whatever full size breaks (memory, time, frame layout) without changing the look:
  walking pace, figure size, card timing and fades stay the spec's defaults; those are the
  Lamp's to judge, not ours.
- **Report the numbers the Lamp needs:** frames and seconds per stage and in total, wall-clock
  render time, the worker's height as a share of the photo's, and the paper size. If the movie
  runs past three minutes, say so; don't shorten it.
- A legible contact sheet: per stage, the frames at 0, 25, 50, 75 and 100 % of the wipe, cropped
  to the paper's photo-and-figure area (so a 144-wide photo is no longer a stamp), plus one
  full-resolution PNG of each stage's midpoint, all outside the repo.
- Deterministic: two full runs give byte-identical frames (compare digests in the report). Tests
  for the new flag and the cropped contact sheet on a small synthetic photo.

### F20 · The makers' page
Branch `codex/f20-makers-page`. Chapter 7 gave the Marginarium a last page, after all the
guardians, for the two who built and told it: Pip and Colophon (`pieces/pets/makers.md`).
Add it to the collection page. Factory only; no app code.
- `tools/factory/collection.py` gains `--pets <dir>`: read `<dir>/<id>/spritesheet.webp` instead
  of `factory/pets/` (real pets stay out of the repo; their final sheets are under
  `/root/factory-out/F18/{pip,colophon}/final/`). Keep the current behavior without the flag.
- After the guardians, a closing section, **The makers**, with two entries and no letter
  circles: **Pip**, "Codex's teapot. A plain white teapot, a little lopsided, with no face. Lift
  the lid and there is a blue dot underneath." and **Colophon**, "Claude's moth. A small round
  moth with pale page wings. It circles the lamp once, at a safe distance, and lands beside the
  words like a bookmark." Use these words exactly. Each shows its idle row; a tap or click
  plays one other row once and returns to idle: Pip's waving row (row 3, the lid lifts),
  Colophon's review row (row 8, the wings fold flat). Take each row's frame count and timings
  from the create-pet skill's v2 reference (`~/.codex/plugins/cache/openai-curated-remote/work-pets/0.1.6/skills/create-pet`),
  and cite where in the report. Reduced motion: still first frames, and a tap shows the row's
  middle frame for a moment instead of playing it. The entries are buttons with VoiceOver-style
  labels ("Pip, Codex's teapot. Tap to lift the lid.").
- A missing sheet leaves its entry as text only. Tests with generated placeholder v2 atlases
  (never real pets): the flag, the section's order and words, the row and timing data, the
  missing-sheet case. Build the page with the real sheets outside the repo and look at it in a
  headless browser screenshot (idle, and mid-row after a click).

### F21 · A read-only audit of the factory
Branch none: report only, no code changes. Read `Sources/FigureRig`, `Sources/figures`,
`tools/factory/*.py` and `factory/taste/*.py` end to end, as a reviewer who will be blamed for
what ships. Look for: bugs (with the input that triggers each), nondeterminism (set or dict
order, time, unseeded randomness, float sums that depend on chunking), unsafe file handling
(paths from JSON written outside their directory, output written into the repo), dead code,
duplicated helpers that have drifted apart, tests that cannot fail, and docstrings that no
longer match the code. Run the test suites and the tools' `--help` to check claims.
Write `/root/factory-out/F21/audit.md`: findings ranked most severe first, each with file and
line, a one-line failure scenario, and a proposed fix; then a short list of what you checked
and found sound. Don't fix anything; Claude turns the findings into backlog items.

### F22 · Audit fixes, Swift (FigureRig and figures)
Branch `codex/f22-audit-swift`. F21's read-only audit (`/root/factory-out/F21/audit.md`; a copy
is in Claude's scratchpad if that is gone) found these in `Sources/FigureRig` and
`Sources/figures`. Fix each with a test that fails before the fix. Swift only; Python is F23.
- **Finding 2, huge finite numbers trap.** Bound canvas size, path coordinates and length,
  durations, frame and gait counts at decode or before any Double-to-Int conversion; out of
  range throws a field-specific `FigureInputError`. CLI tests for the three probes (canvas
  height, idle duration, a path coordinate of `1e300`) exit nonzero with a message, no trap.
  Scenes may later come from guardians' patches, so this is input validation, not paranoia.
- **Finding 3, the CLI's part.** `figures render` and `figures reveal` refuse an output inside
  the repository and any symlinked child (`frames/`, …) of the output; cleanup removes only the
  frame files the run owns, never unrelated SVG/PNG.
- **Finding 5, `propGrip` compares the hand with itself.** Derive each grip from the rendered
  prop (base, axis, kind, attachment offsets) and compare that with the hand; a missing expected
  attachment fails. Negative tests that move the drawn base or axis without touching the grip
  metadata, including the two-handed broom.
- **Finding 6, a new walk after ink drifts by the ink offset twice.** A switched walk path that
  starts at the actor resets the inherited lateral offset; continuing on the same ink path keeps
  it. Test the audit's ink-then-new-path scene (ends at y = 393, not 386) and same-path
  continuation.
- **Finding 7, cards squeeze without limit.** Wrap title and author lines to as many lines as
  needed with a minimum horizontal scale (state it, and why), and fail `cardSize` on measured
  post-layout size. The longest real citation, Douglas and Peucker's 1973 title in
  `ACKNOWLEDGEMENTS.md`, must render legibly; test it and a pathological 150-word title.
- **Finding 11, the Swift part:** `figures --help` lists `render` and `reveal` and exits 0.
- Hero and workers digests stay byte for byte unless a fix must move them; if one moves, say
  which fix and why in the report, and update the pin in the same commit.

### F23 · Audit fixes, Python (taste kit and factory tools)
Branch `codex/f23-audit-python`. The Python half of F21's findings. Python only, and don't touch
`tools/factory/making_of.py` (F19 is changing it). Each fix with a test that fails before it.
- **Finding 1, job IDs escape their directories.** IDs are nonempty safe slugs, rounds and
  attempts are validated, and one helper resolves and checks every reply, cost and scratch path
  (symlinks included) before writing; the legacy extract adapters use it too. Negative fixtures
  for traversal and absolute IDs.
- **Finding 3, the Python part.** `collection.py`, `reveal_sheet.py` and `render.py` refuse
  repository outputs and symlinked output children, and remove only files they own.
- **Finding 4, translucent ink passes the contrast check.** Measure the composited ink colour
  over the actual paper (material opacity apart from edge antialiasing). Test `#55555580`
  failing on the default paper.
- **Findings 8–10.** The craft oracle rejects an empty or whitespace name; one identity hook per
  piece used everywhere names are compared (within a slot, across the set, in repairs and the
  legal-assignment search), with recorded runs replaying byte for byte; JSON-schema `enum` and
  `uniqueItems` compare booleans apart from numbers (1 and 1.0 stay equal).
- **Finding 11, the Python part.** Every public script parses arguments before importing
  optional dependencies or writing anything; `--help` exits 0 with no side effects
  (`card_font.py` must never regenerate `Charter.swift` on `--help`). A subprocess test runs
  each script's `--help` and checks nothing changed.
- **Finding 12.** `verify.py` and the nested Swift test in `test_render.py` honour `FIGURES_BIN`
  and a Swift scratch path (an option or env var, documented in `factory/taste/README.md`), and
  report a missing build clearly.
- Recorded taste runs (`pieces/panel-name`, `pieces/color-names`) still replay byte for byte.

### F24 · The simulator driver, before the Mac
Branch `codex/f24-simctl-driver`. M2's host half, so the Mac session only writes the Swift side.
Factory only; no app code. Build on F17's `Driver` protocol in `factory/taste/play.py`.
- **The mailbox contract**, written down in `factory/pieces/play/README.md` for the Mac session
  to implement in Swift: the driver and the app's Debug-only play UI test talk through a host
  directory (the simulator shares the host file system) whose path the test reads from the
  environment (`xcodebuild` passes `TEST_RUNNER_PLAY_MAILBOX` to the runner as
  `PLAY_MAILBOX`). The driver writes `move-<n>.json` atomically (temp file, then rename); the
  test performs it and writes `done-<n>.json` with the resulting state (F17's state schema) once
  the screen has settled, or `error-<n>.json` with a reason. A `hello.json` from the test says it
  is ready. Numbers start at 1 and never repeat within a session.
- **`factory/taste/simctl.py`**, a `SimctlDriver` implementing the protocol over `xcrun simctl`
  and `xcodebuild`: find the device by name in `simctl list devices --json` (the default is CI's
  13-inch iPad Pro), boot it and wait (`bootstatus -b`), set appearance, install an `.app`, and
  start `xcodebuild test-without-building -xctestrun <file> -only-testing:<test>` with the
  mailbox variable, waiting for `hello.json`. `perform` writes the move; `settle` waits for its
  `done`/`error` file with a timeout and fails clearly if the runner exits first; `state` returns
  the last settled state; `screenshot` uses `simctl io <udid> screenshot`. Optional video:
  `simctl io recordVideo` from start to finish, stopped with SIGINT. Every command is built in
  one place, logged, and run without a shell.
- **Tests on Linux with a fake `xcrun`** on `PATH`: a script that records its arguments and
  answers `simctl list`, `bootstatus`, `io screenshot` (writes a PNG) and `xcodebuild` (starts a
  fake runner that answers the mailbox from a scripted folder). Cover a three-move session,
  an `error-<n>.json`, a runner that dies, a timeout, a missing device, and a replay of the
  recorded session with F17's mock driver. Nothing here may call a real `xcrun`.
- `play.py` gains `--driver simctl` with the options above; the mock stays the default.

### F25 · A read-only audit of the saved-painting decoders
Report only, no repository changes. Saved paintings must open in every later build and decoders
treat files as hostile (root `CLAUDE.md` › Saved data compatibility); PaintCore ships
`-Ounchecked`, so a missed check is a silent out-of-bounds read on a user's device.
- Read `Sources/PaintCore/Model/TemplateCoding.swift`, the `LINE` and `DETL` chunk readers, the
  `PaintProgress` reader and everything they call, as a reviewer who will be blamed. For every
  count, span, reference and coordinate: is it checked against the bytes left or the canvas, in
  `Int` arithmetic, before anything allocates or indexes with it?
- Fuzz them on Linux from a harness kept **outside the repo** (a scratch Swift package that
  depends on PaintCore by path, built in release with `-Ounchecked` like the app, plus a debug
  build so traps show): start from the five frozen fixtures in `Tests/PaintCoreTests/Fixtures/`
  and from templates `pbn generate` writes, mutate (bit flips, truncation, length and count
  fields set to boundary values, chunk tags swapped, chunks duplicated), and decode. A trap,
  hang, huge allocation or out-of-bounds read under the debug build is a finding; record each
  crashing input under `/root/factory-out/F25/crashes/`.
- Write `/root/factory-out/F25/audit.md`: findings most severe first, each with file and line,
  the input that triggers it, and a proposed fix; then what was fuzzed (inputs, iterations, time)
  and found sound.

### F26 · Determinism across core counts, checked
Report only, no repository changes. Root `CLAUDE.md` promises the same maps and settings give the
same bytes on any core count (`Parallel`'s doc comment is the contract).
- Build `pbn` in release. For each `Tests/Corpus` photo, generate classic, the coloring book from
  `tools/baseline/lines/` (as `tools/regression.py` does) and Auto's suggestion under
  `taskset -c 0`, `0-1`, `0-2` and all cores, and compare the template bytes and stats.
- Read `Sources/PaintCore` for floating-point reductions whose grouping follows the band or
  core count (the convention's examples: `RegionAdjacency.boundarySteps`,
  `RegionRuns.accumulate`), and any reading of `activeProcessorCount` that reaches output.
- Write `/root/factory-out/F26/report.md`: the byte comparison table, every difference traced to
  its code with a proposed fix, and the reductions you checked and found sound.

### F27 · Validator counts that can't overflow (PaintCore)
Branch `codex/f27-validator-counts`. From the decoder review (F25, Claude's notes at
`/root/factory-out/F25-claude/audit.md`, finding 3): `GeometryValidator` keeps its bucket counts
in `Int32` (`Sources/PaintCore/Vector/GeometryValidator.swift`, around lines 52-70), and a
template with an unusual edge layout can push them past 2^31; the debug build traps, and the
release build (`-Ounchecked`) would index wrongly. The same layout can make validation very slow.
It is reachable through `pbn check`, the regression gate and the app's Debug create check.
- First write a test in `Tests/PaintCoreTests` that builds such a template in code and shows
  the overflow (or, if you find it can't overflow, say why in the report and stop there).
- Then count in `Int`, and bound the work so validation of any template that decodes finishes in
  time proportional to its size; a template over the bound fails validation with a clear reason
  rather than running on.
- Generated templates validate exactly as before: `swift test` all green, and
  `tools/regression.py` (no `--update`) passes with no metric moved. No `pipelineVersion` bump
  is needed (validation doesn't change output); say so if you find otherwise.

## Tuesday night: the making-of ships (starts when Paul says go)

F29–F35 below are the making-of's. The earlier app items with the same numbers (the Marginarium's
second version, the play harness, three flaky UI tests, palette preparation off the main actor,
the chapter reader, and the factory's Pillow and gallery fixes) shipped on Oct 11–12 under those
numbers; their branches and `ORCHESTRATOR.md`'s tables keep the old meanings.

Paul, October 12, 2026: "We should probably be prepared for Tuesday night after the usage reset,
where we want to actually get that animation thing working. The lamp — they should be involved
obviously, and that's probably the next chapter, but we also need it to actually work lol, can't
just be for lamp content".

**Where it stands.** Every making-of item so far is merged here, but nothing is in the app.
- `main` has neither the stage snapshots (F8) nor FigureRig; this branch is about 180 commits
  ahead of `main` and 78 behind, so the pieces are ported, never merged wholesale.
- The one full render (F19, parrots) runs 338 s at 2064 × 1813, took 52 minutes on Linux and ran
  out of disk. In it the worker is a speck (7.5% of the height), the wipes are straight vertical
  fronts, the structure stage turns the photo black, the line-art worker inks a straight line
  across the drawing, and the line-art card repeats the simplified stage's paper.
- The figure piece has never had a Lamp round, and no piece exists for the show itself.
- In the app, generation takes under a second, so the show can't play while it runs. NOTES already
  decided the answer: "The show plays when the painter taps Start, over each stage's recorded
  picture: the pipeline reruns once with an observer, so the template stays byte for byte the
  same. Tap to skip; replay from More." There is one scene per credited method, and the cards are
  New York italic, authors and year first, about 0.5 s + 0.2 s per word, at least 2 s. Reduce
  Motion shows the cards only, cross-faded.

**An army, not a worker.** Paul, October 13: "the idea was an army of little stick figures".
His first message said so: "8 or 16 animations of a stick figure from different angles, so we can
have one for each direction that could be an edge of a line in a painting, so for each layer we see
the workers applying that image transform." F19 and this plan's first draft drifted to one worker
per stage. Every scene has a crew of small figures working along the stage's changing edges, each
facing one of 8 or 16 directions. FigureRig already takes up to 1,024 actors.

**The shape: one spec, two renderers.** `making-of.json` holds every taste choice. The app plays
it live over the painter's own photo (SwiftUI, FigureRig computing the figures). The factory
renders the same spec into clips for the Lamp and Paul. What they pick is what ships: the same
engine, seeds and timings, over a different picture. It works first, with a sensible default spec
in the app, and the Lamp then tunes the spec rather than gating the build.

**Who does what.** Codex does the portable parts (PaintCore, FigureRig, the factory tools), which
are verified on Linux. Claude does the spec and the app, which compiles only on CI, and reviews
everything. Codex runs the Lamp (`codex_lamp.py`, as for the pets) to spare Claude's usage, and
Paul checkpoints.

**Night order.**
1. Paul says go. Claude cuts `claude/making-of` from `main` and starts F29 and F30 on Codex at
   once, then writes F31 while they run.
2. Claude reviews F29 and F30, merges them into `claude/making-of`, links FigureRig, and builds
   F32 in CI rounds of about 45 minutes. Meanwhile Codex does F33, then F34.
3. v1 goes to `main` and SideStore with the default spec as soon as F32 is green, then v2 with the
   Lamp's spec after Paul's checkpoint. F35 comes last.

**Decided with Paul (Oct 13, from the demo, version 4):**
- Length: "I was thinking much shorter honestly. Like less than 10 seconds." Six steps of 1.5 s,
  about 9 s.
- Layers in order: each step shows only what it adds to the last (sketch, shading, the paints,
  merging, ink, clean curves), never the full photo again at every step.
- Cards: "Give each of them 1.5 seconds, this is for fast and attentive readers — maybe the font
  should be a little bit like, faint or transparent — or I guess book themed — idk, just gentle so
  it’s not overwhelming". Small, faint, book-like, one per step for its 1.5 s.
- The crew stays: "Maybe the workers wouldn’t go away, they’d keep working between each stage".
  One crew for the whole show; between steps each worker walks to an untaken spot of the next
  step (the nearest it can reach in time) and swaps tools on the way; a worker with no job left
  keeps working where it stands. The demo's `planTroupe` is the reference.
- "Ooh ok, we can try a few less. That newest demo still showed color. I also don’t like the
  sliding animation from left to right." So: about 100 workers; the picture stays pencil and
  ink (grey tones for shading, paints and merging; the template's lines and numbers last), with
  color only in the crew's paint pots; each layer comes in as patches all over the picture where
  the crew works (equalized value noise), never a front sliding across.
- Crew: "more, and smaller" than the first demo's 22 at 8 %. Proposed: about 12 pt tall on
  screen, the count growing with the picture's area (about 130 a step on an iPhone).

**Decided with Paul (Oct 13–14, checkpoints 1 to 3, rendered on Linux):**
- Pets, not stick figures: "I’m thinking pets only — give me a little mockup of what a smaller
  amount of them might look like?" The Lamp's own pets are the crew, using the poses their sheets
  already have. "We’ll plan on making new animations for each pet when codex usage is back."
- Layers: "5-6 is just a big jump, everything else looks good". Step 5 inks the template's own
  lines, so step 6 only relaxes them into curves and adds the numbers.
- Pace: "This is rushed. And with the pets instead of stick figures, this will be visually
  engaging enough that we can slow it down a little." Then "2.5s looks right": six steps of
  2.5 s, about 18 s with the pets' entrance and goodbye.
- Motion: "The hops might be too fast. There’s still some refinement needed here for general
  motion." The motion pass: eased walks at most 2.4 heights a second, low hops with a springy
  landing, arrivals on the step's quarter beats, no teleports.
- "You could try the scholars suggestions": the sketch keeps only the edges relative total
  variation keeps, the paints flow from the k-means++ seeds the method picks, and the outlines
  relax from stepped to smooth as Potrace's method does.
- Crew size: "Before moving forward — maybe see what this looks like with 6 or 3 or even just 1
  pet?", then "3 seems better": three pets (the Enchanted Workshop's, Dino's and the Snow
  Queen's) at 16 % of the picture's height, each working its own band of the picture.
- The Lamp's second look: "maybe add someone who guards minimalism, and someone else who could be
  interesting". Rikyū and Lotte joined (Who's Who).

- Chief Designer Caroline, relayed by Paul: "Add that Caroline suggested that this was too many
  pets at 12, and then again at 6 — and still thinks this final output, though very cool, is a lot
  to see for the user. She suggests a briefer description of what each step does and then for the
  paper name to be a footnote/citation instead of so front and center." The cards now try it: a
  short caption per step (`caption` in the spec), with each paper's credit line, letter for letter,
  as a small, fainter footnote under it.
- Chapter 7, "Before You Paint": Paul asked the Scholar, Niko, Bulat and Dino to write it, Bulat
  narrating ("one more serious narrator") and the others "more cute and childish in the margins",
  with a condensed cast.

- Paul, on Caroline's cards and the Lamp's last two asks: "Looks great—yes to both calls". The
  cards keep their captions; the greys follow the Snow Queen's tones (0.62 to 0.92, averaging
  0.85); the goodbye gets a last look and, for the last one out, a wave at the edge (Dino and the
  Robber Girl). The show is now 19 s.

**Where it stands (Oct 15).** On `claude/making-of`: F29's port (with it, the regression gate's
60 templates are byte for byte main's), the spec (F31's file, `making-of.json`), the factory's
renderer (`tools/factory/making_of_clip.py` with `making_of_pets.py` and `making_of_layers.py`,
which reads the spec), and the crew's planner and motion in portable Swift (`Sources/MakingOf`,
06a8345), replaying the Python's parrots plan. F30 is superseded (the crew is three of the Lamp's
guardians, drawn from their sprite sheets, not FigureRig's figures), and F33 and F34 were done another way (see each). F46 (Oct 15) put the
rest of the show in portable Swift. Next: F32, a thin view, when CI minutes return.

**Paul's calls** (each has a recommendation; nothing waits on them except where noted):
1. Placement: on Start, over his own painting's stages, skippable, with replay from the
   painting's menu, as NOTES has it. A shareable video can come later; `TimelapseExporter`'s
   frame hook makes that one item.
2. Length: about 25–30 s, skippable from the first tap. Does it play on every Start, or once and
   then on demand? The recommendation is every Start, since a skip costs one tap.
3. Card face: New York in the app, with Charter staying factory-only, so no new font license or
   Acknowledgements section is needed.
4. The Lamp on Codex for the round's volume, with Claude reviewing and Paul at the checkpoint.
5. Pets cheering the workers (`chapter-6` option E): after v1 works, as a Lamp option.

### F29 · Stage snapshots on main (a port of F8)
Branch `codex/f29-snapshots-main` from `origin/claude/making-of` (not this branch). Port
`Sources/PaintCore/PipelineSnapshot.swift`, the `observer:` parameter through
`TemplateGenerator.generate` and `Segmenter.segment`, and `pbn --snapshots` from
`codex/f8-snapshots` (457dc29, built on pipelineVersion 10) to `main`'s pipelineVersion 11:
working image, structure, smoothed, palette, simplified, line art (books with an edge map) and
vectorized, at most 1024 px on the long side.
- A nil observer does no work, and the template is byte for byte the same with or without one:
  `tools/regression.py` passes with no baseline change, and pipelineVersion stays.
- Tests: each stage arrives once, in order, at its size; the template is identical with and
  without an observer, classic and coloring book; the observer can't change determinism across
  core counts.
- Report each stage's capture cost in time and bytes on the corpus.

### F30 · FigureRig as an app library
*Superseded Oct 14: the crew is three of the Lamp's guardians, drawn from their sprite sheets with
procedural motion (`Sources/MakingOf`), so the app links no FigureRig.*
Branch `codex/f30-figurerig-library` from `origin/claude/making-of`, after F29. Bring
`Sources/FigureRig`, `Sources/figures` and `Tests/FigureRigTests` (with F22's fixes) over from
this branch, split so the app links only what it draws:
- The `FigureRig` library holds the rig, scenes, reveal fields and a frame API that returns each
  actor's filled shapes at time t: no SVG, no files, no card. Its `swiftSettings` match
  PaintCore's (`-O` in Debug), because Debug app builds otherwise run it unoptimized.
- Charter's outlines, the card layout and the PPM/PGM snapshot reading move to the `figures`
  executable (factory only). The app sets cards in New York with SwiftUI.
- Reveal fields work from in-memory stage pictures (F29's observer output), not files.
- Checks: `swift test`; the hero and workers digests stay byte for byte; `figures render` of
  both scenes is identical before and after the split. Report the time to compute one frame of
  the workers scene; the budget is 2 ms on Linux.
- Out of scope: the Xcode project (Claude links it in F32).

### F31 · The show spec (Claude)
`App/PaintByNumber/Resources/making-of.json` is the one spec both renderers read. Scenes run in
stage order, each with its stages, its method ids from `Acknowledgements.swift` › methods (the
Scholar's rule: cards match the acknowledgements letter for letter, and a test checks it), its
action, prop and duration. It also holds the crew (how many figures, their height as a share of the picture,
how they spread along the front and pick their direction), the wipe's seed and softness, the card rule, colors from the app's tokens, and a total of 25–30 s.
- One scene per credited method, with no repeats. Line art credits HED (Xie and Tu, 2015) and
  Informative Drawings (Chan, Durand and Isola, 2022), not Felzenszwalb a second time.
- Strict, bounded decoding, since the Lamp's patches will write it. The default is Claude's,
  from NOTES' decided rules, and the Lamp tunes it in F34.

### F32 · The show in the app (Claude, CI)
*In progress Oct 15, in the release session (`claude/making-of-view` from `claude/release-1`): a
Settings switch, off by default, plays the show on Start from the Marginarium's sprite sheets; no
Replay yet. It joins the first TestFlight build if its CI is green in time, otherwise the next.*
On `claude/making-of`, after F29–F31.
- **Start:** `CreateModel` reruns the final generation once with an observer, off the main
  actor, and keeps the stage pictures at screen size plus their reveal fields. The template must
  equal the one saved (a test).
- **`MakingOfView`:** a TimelineView with a Canvas draws the earlier stage, the next stage
  revealed by its arrival-time field (a SwiftUI shader, or GraphicsContext's alpha-threshold
  mask), and the crew as filled paths from FigureRig.
  - The card is SwiftUI Text, in New York italic with Dynamic Type, and VoiceOver reads each
    card as it appears.
  - Tap or Skip opens the painting.
  - Reduce Motion shows the cards only, cross-faded over the stage pictures; dark mode is
    supported.
  - Memory is released when the show ends.
- **Replay:** from the painting's menu, regenerating the snapshots on demand (output is
  deterministic). For a painting made by an older pipelineVersion, decide in review: replay the
  current stages, or hide the item.
- **Done means:**
  - tests for the timeline (card durations by the rule, scene order, total length);
  - a UI test: Start plays, Skip opens the painting, Replay plays;
  - the demo scenarios `making-of`, `-dark`, `-reduce-motion` and `-long-text` in
    `ci/scenarios.txt`;
  - catalog strings and the `App/CLAUDE.md` pointer;
  - a portrait photo among the screenshots (`Tests/Corpus/regatta`): the factory's checks were
    all landscape until Oct 14, when the first portrait found four bugs (`claude/making-of`
    9075e59); the crew's `petHeight` is the spec's height times the picture's shorter side;
  - Acknowledgements unchanged.

### F33 · The factory renders the spec
*Done another way, Oct 13–14: `making_of_clip.py` renders the spec with the guardians as the crew, at the snapshots'
size, landscape and portrait; Paul judged its clips at checkpoints 1 to 3.*
Branch `codex/f33-making-of-spec` from this branch. `tools/factory/making_of.py --show
<making-of.json>` renders each scene as its own clip (at most 6 s, at phone size), the whole show
(at most 30 s) and contact sheets, all from the spec.
- Fix what the 338-s render showed:
  - a crew instead of one worker, sized and spread by the spec;
  - the line-art crew inks along the drawing's own strokes, not a straight line;
  - the structure stage is drawn on paper rather than black;
  - a stage's wipe starts where its change starts, not as a vertical front.
- Stream frames to the encoder, and stay under 2 GB of disk (F19 ran out). The budget for the
  whole show is under 10 minutes on four cores.
- `loop checkpoint` pages can show a clip (`<video>` with a poster) beside a candidate's stills,
  so Paul judges motion as motion.

### F34 · The Lamp's round: a making-of piece (Codex runs the Lamp)
*Done another way, Oct 14: the Lamp looked at the show twice, by Claude's subagents rather than a
`pieces/making-of` piece on Codex (051f616, then the second look, ec63ecb and 118c591), and Paul
said yes to its calls. The piece itself was never built.*
`factory/pieces/making-of`, after F33.
- **Parameters:** the spec's taste fields (scene durations within the length budget, the crew's
  size and spread, props per scene, wipe softness and seed, card placement, and option E's pets).
- **Code checks:** length at most 30 s, every card on screen as long as the rule says, contrast,
  and the crew on screen and large enough to read.
- **Jury:** six with Originality, run through `codex_lamp.py`. Jurors see each candidate's
  contact sheet and the frames at each scene's midpoint.
- **Paul's checkpoint:** with the clips. His picks win (point 11). Claude writes the winner back
  to `making-of.json` for v2.

### F46 · The show's portable half (Claude, Linux, `[skip ci]`)
*Done Oct 15 (`claude/making-of` 27b69c0): `Show.init` builds the whole show once (0.46 s on four
cores, 1.0 s on one, for 1024 x 682; about 37 MB kept), and `frame(at:)` says what to draw at any
moment (26 µs on average). The Swift equals the Python exactly for every decision and within 2e-6
for pixels, with the same bytes on 1 and 4 cores. `making_of_clip.py` is now a driver over the
same modules, so a factory clip is the show the app will play. On the way, the old clip turned
out to replan each guardian's bends after planning, so it never showed the plan its fixture
pins; it does now. 207 MakingOf tests, 126 Python ones (in the core CI job from the next real
run). Left for F32: draw a `ShowFrame` (`ShowFrame`'s doc comment lists everything to draw), set
the cards in New York with credit lines from `Acknowledgements` by exact method name, Reduce
Motion, and one CI check of a frame without ink against `Show.composite`.*
On `claude/making-of`, before F32. Everything F32 needs but the drawing, as portable Swift in
`Sources/MakingOf`, tested on Linux against the Python reference, so the app's view only draws what
a frame function hands it and F32 takes fewer CI rounds. Built in four packages by Sonnet agents,
Claude reviewing and merging:
- **Shared** (cbbc874): `Plane`; `ShowStreams`, one SplitMix64 per purpose (homes, spots, noise,
  seeds, strokes), the same in `making_of_pets.stream`; a small fixture (a parrot's head, 216 x 144).
- **A, crew inputs, exact:** the pictures and the template's strokes, labels, the spots and the
  k-means++ paint seeds on the streams, `CrewInputs.make`; the Python moves to the same draws and
  loses the dead `Crew` and dots mode, and the parrots plan fixture is made again.
- **B, layers and compositor:** the six layers' math at the snapshots' size (relative total
  variation, the tone curve from the palette's counts) and each step's picture recipe as a CPU
  reference, within a measured tolerance of the Python.
- **C, reveal:** value noise on the streams, arrival times, per-region times, the stroke and number
  schedules, the ink lines at any time.
- **D, the show:** `Show.frame(at:)` (picture recipe, ink lines, numbers, seed rings, sprite draws,
  the card), the timeline tests F32 lists, `making_of_clip.py` reduced to a driver over the shared
  modules, the Python tests in the core CI job, and the CLAUDE.md pointers.

### F35 · The chapter (Claude)
*Started Oct 14 as Chapter 7, "Before You Paint" (a Doc: Bulat narrating, the Scholar, Niko and
Dino in the margins); it ships with or after the show.*
How the show was made and judged, told from F34's records, with the Lamp in the margins (Bart
included). It comes after the show ships, never instead of it.

## Needs the Mac (Claude, in a session on the Mac)

- **M1 · Prove the toolchain:** build the app, run the unit tests and one UI test, take a screenshot.
- **M2 · The play harness:** (host half: F24) a Debug-only "play" UI test that performs moves from a file
  (`fill <area>`, `drag`, `tap <label>`, `wait`, `screenshot`), a Debug hook that reports each
  area's label point by number, a driver around `xcrun simctl` (boot, install, launch a demo scene,
  screenshots, video, appearance), and a design-loop piece that hands each turn to a guardian.
  Debug-only code follows the app's `#if DEBUG` rule.
- **M3 · The Lamp's first painting:** the ledger picks a guardian; it paints one library picture
  start to finish; the video and moves are kept for chapter 5.
- **M4 · A self-hosted runner** for the app's CI jobs, limited to pushes from trusted accounts.
- F11 can be built and tested here before it costs CI minutes.

## Waits on CI (rationed macOS runners)

- **F32**, the show in the app: in progress in the release session (Oct 15).
- Two flaky tests still open (`ORCHESTRATOR.md`): `EyeFinderTests.findsBothEyesOfAFaceWithTheirIrises`
  and `GalleryActionsTests.testTimelapseShowsProgressAndCancels`.

Shipped from this section: F28 (`main` 2025569, build 1.0.303) and F11 (Ship 2, build 1.0.311).

- **F28 · Damaged data never traps, in the app** (shipped; from F25's review, findings 1, 2 and 4;
  confirmed by Claude reading the code): `PaintProgress.sanitized` keeps any finite positive
  time, and `PaintingTimeText.spent` does `Int(seconds / 60)`, so one damaged `progress.bin`
  (about 1e157 s) traps the gallery card at every launch once autosaved to `meta.json`. Clamp
  the time on decode and in `meta.json`'s reader, and saturate before converting to `Int`.
  `TemplateRefinements.focus` converts scaled brush points to `Int` unclamped, so a point like
  `[1e16, 0.5]` traps on regeneration: clamp to -0.5...1.5 as `LineEdits.sanitized` does. Bound
  the LZFSE output size when reading `template.pbnt`. Tests in `App/PaintByNumberTests` for each
  (a damaged `progress.bin`, `meta.json` and `refinements.json` open without trapping), per
  `LibraryTests`' pattern. Batch with F11 so one CI run checks both.

- **F11 · Versioned vocabularies in the app** (shipped, with v2 names): the version in `meta.json`, and a pin in
  `App/PaintByNumberTests` so Apple's math is checked. After F4, and when Paul releases CI
  minutes.
