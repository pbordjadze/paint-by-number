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

## Needs the Mac (Claude, in a session on the Mac)

- **M1 · Prove the toolchain:** build the app, run the unit tests and one UI test, take a screenshot.
- **M2 · The play harness:** a Debug-only "play" UI test that performs moves from a file
  (`fill <area>`, `drag`, `tap <label>`, `wait`, `screenshot`), a Debug hook that reports each
  area's label point by number, a driver around `xcrun simctl` (boot, install, launch a demo scene,
  screenshots, video, appearance), and a design-loop piece that hands each turn to a guardian.
  Debug-only code follows the app's `#if DEBUG` rule.
- **M3 · The Lamp's first painting:** the ledger picks a guardian; it paints one library picture
  start to finish; the video and moves are kept for chapter 5.
- **M4 · A self-hosted runner** for the app's CI jobs, limited to pushes from trusted accounts.
- F11 can be built and tested here before it costs CI minutes.

## Waits on CI (rationed macOS runners)

- **F11 · Versioned vocabularies in the app:** the version in `meta.json`, and a pin in
  `App/PaintByNumberTests` so Apple's math is checked. After F4, and when Paul releases CI
  minutes.
