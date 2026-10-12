# Pip and Colophon, the makers’ pets

Pip is a slightly uneven white handmade teapot with a round lid, warm ink
contour and quiet gray shading. Its face is two small, slightly uneven warm
brown oval eyes and a little curved smile, painted low on its belly. A single
blue dot remains beneath the lid and peeks out during its lid-tip greeting.
The eyes blink, soften and look around; Pip keeps its original compact pot,
loop handle and short spout, without limbs, steam or exterior decoration.

**F40, 12 October 2026.** Chief Designer Caroline’s word, relayed by Paul:
“Pip can have its face back. It was unkind to take away Pip’s face.” The F18
“NO FACE” restriction is lifted. Paul left the blue dot to the maker; it stays.
I gave Pip two slightly uneven ink eyes and a quiet curved smile because I
wanted its face to feel as handmade as its clay. I kept the blue dot under the
lid: having a face needn’t cost Pip its little secret.

**F18 hatch record.** The original faceless Pip and Colophon run is retained
below; F40’s re-hatch commands and acceptance follow it.

F18, 11 October 2026. Pip was hatched and accepted first; Colophon was then drawn
with Pip’s **final** sheet as the family reference. Both are local v2 candidates:
1536 × 2288 RGBA, eight columns and eleven rows, 192 × 208 cells, 73 populated
cells and 15 transparent unused cells. PNG and lossless WebP are retained.
The sole repository change is this piece. All run artifacts, helpers, scratch
build products and the runner’s commit message are in `/root/factory-out/F18`.
No upload, pet creation, Library write or lifecycle/preflight tool was used.
Imagegen itself caches its original output outside that directory; every source
used here was copied into F18, as in F7.

At F18, Pip was a slightly uneven white handmade pot with a round lid, warm ink
contour and quiet gray shading. No face, steam, exterior blue or pattern. A single blue
dot under the lid appears in the two open-lid waving frames; it is hidden in
all other populated cells. Its spout supplies the aim cue for sixteen looks,
while the lid and belly remain upright. Colophon is a plump, soft, round moth
with short furry antennae, normal dark eyes, pale page wings and a few invented
nonalphabetic ink dashes. Native visual review found no wing letters, words,
eyespots, skull or glow, and neither pet uses a named character or logo design.

Commands used the installed create-pet bundle, with the same workflow as F7.
The skill’s independent visual workers reviewed small row batches; the
coordinator approved each dependency before proceeding. Image generation used
only the built-in `image_gen.imagegen`, with actual prompts and supplied
references saved in each pet’s `prompts/used/` and `logs/`. Sprite calls requested
true transparency; `#FF00FF` remained the extraction/cleanup key.

```sh
SKILL_DIR=/root/.codex/plugins/cache/openai-curated-remote/work-pets/0.1.6/skills/create-pet
RUN_DIR=/root/factory-out/F18/pip # repeat with colophon
python3 "$SKILL_DIR/scripts/prepare_pet_run.py" \
  --pet-name Pip \
  --description 'Codex’s small handmade white teapot; moods through posture and lid.' \
  --pet-notes 'Plain white hand-drawn teapot, round lid, a little lopsided as if thrown by hand. NO FACE, no steam, no pattern, no blue on the outside. Only one small blue dot BENEATH the lid, visible only as the lid lifts in waving or review. No Mrs. Potts, Utah teapot profile, blue-and-white china. Express moods through posture and lid. No arms, legs or detached effects. Directional aiming feature is spout; closed round lid in look rows.' \
  --style-preset auto \
  --style-notes 'Hand-drawn warm dark ink contours, imperfect curves and quiet ivory ceramic fill, soft restrained gray shading; a compact original storybook object. Simple tactile drawing, no 3D render.' \
  --chroma-key '#FF00FF' \
  --output-dir /root/factory-out/F18/pip
python3 "$SKILL_DIR/scripts/prepare_pet_run.py" \
  --pet-name Colophon \
  --description 'Claude’s small soft moth with pale page wings, a safe lamp circuit and bookmark landing.' \
  --pet-notes 'Small round soft moth, never spindly. Plump nearly spherical body, short soft antennae and little feet, two pale page-like wings with only a few hand-inked invented nonalphabetic dash marks. No real letters/words on wings, no eyespots/skull marking/glowing eyes. Tiny normal dark eyes are allowed. Circles lamp glass once at a safe distance, never flame or singed; only nearest wing edge catches warmth; lands beside words folding wings flat like a bookmark. Avoid Mothra, Pokemon moths, The Moth logo, bookworm mascots. No floating effects, extra props or scene inside atlas.' \
  --style-preset auto \
  --style-notes 'Use Pip’s sheet as family reference: hand-drawn warm dark ink contours, imperfect curves, quiet ivory fill and soft restrained gray shading. Compact soft original storybook creature, tactile drawing, no 3D rendering. Preserve moth identity.' \
  --chroma-key '#FF00FF' \
  --output-dir /root/factory-out/F18/colophon \
  --reference /root/factory-out/F18/pip-contact-sheet.png
python3 "$SKILL_DIR/scripts/extract_strip_frames.py" \
  --decoded-dir "$RUN_DIR/decoded" --output-dir "$RUN_DIR/qa/rows/$STATE/frames" \
  --states "$STATE" --method auto
python3 "$SKILL_DIR/scripts/inspect_frames.py" \
  --frames-root "$RUN_DIR/qa/rows/$STATE/frames" --states "$STATE" \
  --require-components --json-out "$RUN_DIR/qa/rows/$STATE/review.json"
python3 /root/factory-out/F18/pipeline.py pip standard
python3 /root/factory-out/F18/pipeline.py pip row9
python3 /root/factory-out/F18/pipeline.py pip final
python3 /root/factory-out/F18/pipeline.py pip quality
# The same four stages were run for colophon.
python3 /root/factory-out/F18/audit.py pip
python3 /root/factory-out/F18/audit.py colophon
```

The preparation commands above reproduce the values recorded in each
`<pet>/pet_request.json`; actual imagegen prompts preserve every constraint.
The outside-repo pipeline helper records each exact bundled command
and its output in `<pet>/logs/{standard,row9,final,quality}-commands.jsonl` and
matching output logs. `standard` runs registration, `inspect_frames.py`,
`compose_atlas.py`, `make_contact_sheet.py` and `render_animation_previews.py`.
Registration scales/translates existing generated pixels, one transform per
row, preserving jump displacement. Running-left mirrors the independently
approved rightward frames individually, keeping temporal order; neither design
has handed text or directional lighting to invalidate that derivation.

Cardinals were approved before either look row, using bundled
`extract_cardinal_anchors.py` and `compose_cardinal_anchor_strip.py`. `row9`
uses `assemble_extended_atlas.py` to register and save the approved first eight
looks; only then was row 10 generated. `final` attaches row 10 while retaining
that exact registered row 9, runs **one** `despill_chroma_edges.py` per candidate,
then `validate_atlas.py --require-v2` on both encodings, final contact/direction
sheets, `measure_direction_continuity.py` and previews from exact final cells.
`quality` runs `validate_pet_quality.py` with frame, chroma, semantic and
continuity reports, then creates the shuffled blind sheet.

Three independent reviewers saw only each shuffled blind sheet, without its
answer key, labeled directions or the other verdicts. Their JSON verdicts were
combined and validated with the bundled commands:

```sh
python3 "$SKILL_DIR/scripts/combine_direction_blind_verdicts.py" \
  --verdicts "$RUN_DIR/qa/blind-review-a.json" \
  --verdicts "$RUN_DIR/qa/blind-review-b.json" \
  --verdicts "$RUN_DIR/qa/blind-review-c.json" --json-out "$RUN_DIR/qa/blind-combined.json"
python3 "$SKILL_DIR/scripts/validate_direction_blind_verdicts.py" \
  --answer-key "$RUN_DIR/qa/blind-answer-key.json" \
  --verdicts "$RUN_DIR/qa/blind-combined.json" --json-out "$RUN_DIR/qa/blind-validation.json"
python3 /root/factory-out/F18/render_signature.py
```

The separate Colophon signature preview uses a generated enclosed glass lamp
and open book, plus a generated eight-pose warm-edge flight strip. It translates
those generated pixels around one closed circuit at uniform travel speed, then
approaches the page and uses the **exact final atlas review row** to fold the
wings flat beside the printed words. No scenery enters the atlas, and no code
paints, redraws or recolors the moth. The GIF plays once; the MP4 and twelve
ordered stills make the entire behavior inspectable. `signature/motion-checks.json`
records clearance from a conservative bounding box around the whole lamp,
including its base. Each flight pose was visually checked for warmth restricted
to the wing edge facing the lamp; the body, eyes and antennae stay unlit.

| Image job | Pip: call seconds | Colophon: call seconds |
| --- | ---: | ---: |
| Base | 29.664 | 50.046 |
| Idle | 27.678 | 27.256 |
| Running right | 26.351 | 28.248 |
| Running left | derived, no generation | derived, no generation |
| Waving | 27.368 | 30.533 |
| Jumping | 23.613 | 27.008 |
| Failed | 26.119 | 31.692 |
| Waiting | 25.475 | 39.280 |
| Active work | 26.771 | 23.045 |
| Review | 28.128 | 28.513 |
| Cardinals | 23.882 | 33.666 |
| Look row 9 | 30.861 | 35.011 |
| Look row 10, attempts in order | 28.308; 26.523 | 26.600 |
| Signature lamp/book setting | — | 27.214 |
| Signature flight, attempts in order | — | 26.402; 28.534 |
| **Generations including rejected attempts** | **13** | **15 (12 atlas, 3 signature)** |
| **Summed call seconds** | **350.741** | **475.547** |

Times are measured seconds awaiting each imagegen call, including rejected
attempts, rather than billing estimates. Summed call time is not elapsed wall
time: standard row workers ran concurrently. Per-attempt prompts, reference
paths and timings remain in `<pet>/logs/generation-summary.json`.
Pip preparation through local acceptance: 08:52:43–09:10:03 UTC, 1040.437
seconds (17m 20.4s). Colophon: 09:08:20–09:33:36 UTC, 1515.868 seconds
(25m 15.9s), including preparation overlapping the final Pip review. Its first
image generation followed Pip’s acceptance. These intervals include inspection,
repairs, assembly and blind review; Colophon also includes the signature clip.
Exact timestamps are in each `logs/wall-time.json`.

Failures and fixes were kept in the run artifacts:

- Both raw cardinal strips had tiny alpha touching fixed-slot boundaries. The
  bundled connected-group extractor recovered complete poses; one shared scale
  and the bundled cardinal compositor produced an approved strip. The mandatory
  cardinal extractor was rerun successfully; failed source reports remain.
- Pip’s first row 10 exceeded the maximum look width ratio: 155/103 = 1.50485.
  A 1% source-resampling trial was discarded. Regenerating the complete coherent
  row with a broader front and compact side profiles passed at 1.45714. Original
  candidates and failed quality evidence remain in `pip/qa/revision-1/`.
- Bundled look prompts omit the full pet/style notes, so the used prompts repeat
  them explicitly. Colophon’s second look row required six source references;
  imagegen accepts five. A labeled two-panel reference preserves the **entire**
  Pip final contact and Colophon standard contact together, leaving space for
  the base, guide, cardinals and approved row 9. No required visual was dropped.
- Colophon’s first signature flight strip warmed the wrong edge in its bottom
  pose. It was rejected and the complete strip regenerated, then inspected and
  cleaned once with the bundled despill script. The selected top-edge poses are
  intentionally similar because that wing contour slopes.

Both final PNG/WebP structural validations are `ok:true`, with no errors or
warnings, 73 populated cells, 15 fully transparent unused cells, no chroma
fringe and zero transparent RGB residue. Both final quality reports are
`ok:true`, errors empty. Hash audits confirm the reports describe the actual
encoded final files. Pip’s jump lifts 74 px and returns within 1 px of idle;
Colophon lifts 47 px and lands exactly at idle. Maximum look center drift is
9 px / 2 px, width ratio 1.45714 / 1.12, respectively.

All four cardinals passed all three blind reviewers for each pet. Both aggregate
blind validations pass with 27 of 28 axes confirmed and one intermediate
horizontal ambiguity: Pip 157.5, Colophon 337.5. Ordered native follow-up accepts
these as subtle correct transitions and records warnings in
`qa/blind-followup.json`, without overriding a hard gate or changing pixels.
One Colophon reviewer also found 112.5’s vertical pitch subtle; the other two
read down and the native ordered descent supports that majority. Pip retains
six quality warnings: two semantic subtleties (157.5 and 202.5), the natural
handle opening at 045, and three silhouette-center transitions. Colophon
retains three: 045 resembling 022.5, 337.5’s weak isolated horizontal cue, and
the stronger 045→067.5 turn measured as a local continuity outlier. They were
visually reviewed, not suppressed or fixed by relaxing thresholds.

The signature clip passes its path assertions: one closed circuit, no repeat
extension in the GIF, and a minimum 46.519 px gap between the visible moth and
the conservative whole-lamp box. Its GIF lasts 5.34 seconds; ffprobe confirms
an H.264 MP4 at 1024 × 1024. The warmth-edge native sheet and ordered scene
stills were inspected after cleanup; the final landing uses the atlas’s low,
flat page wings. Family resemblance and intermediate aim strength remain
visual judgments; this Linux run does not establish Mac runtime integration.

**Family assessment: yes.** The final idle comparison carries over Pip’s warm
brown hand-ink outline, imperfect organic curves, ivory fill, restrained gray
shadows and compact quiet silhouette. Colophon’s fuzzy head and papery wings
change the material; the little ordinary eyes gave the moth a face that Pip
did not have at that hatch. The invented wing dashes are new and do not carry Pip’s hidden
blue dot. This is a visual judgment supported by the reference trail and idle
comparison, not a numerical similarity claim.

Final review artifacts under `/root/factory-out/F18`:

- `pip-contact-sheet.png`, `colophon-contact-sheet.png` and
  `idle-rows-side-by-side.png`, cropped from the exact accepted atlases.
- `<pet>/previews/final/`: all-states GIF/MP4, idle–jump–idle loop, five jump
  stills, all nine state GIFs and sixteen-look loop.
- `colophon/signature/lamp-bookmark.gif`, `.mp4`, `behavior-contact.png`,
  `semantics.json` and `motion-checks.json`.
- `<pet>/final/validation-{extended,webp}.json`, `qa/pet-quality.json`,
  `qa/blind-validation.json` and `qa/acceptance.json` bind checks to exact hashes.

Linux verification used the installed Swift 6.2 toolchain directly:

```sh
swift build --scratch-path /root/factory-out/F18/swift-build -j 4
swift test --scratch-path /root/factory-out/F18/swift-build -j 4 --no-parallel
git diff --check
```

Build passed in 125.15 seconds; all 310 tests in 26 suites passed in 90.192
seconds. Logs are `logs/swift-build.log` and `logs/swift-test.log`. No source,
fixture, app, backlog or git metadata was changed. The runner’s intended commit
message is `/root/factory-out/F18/commit-message.txt`; no commit or push was made.


**F40 re-hatch, 12 October 2026.** Pip’s face is an original warm-ink design,
with the F18 final contact sheet grounding the ceramic identity. All run output
is in `/root/factory-out/F40`; imagegen’s cached originals used here were copied
into `pip/originals/`. The old atlas and contact sheet were copied into
`references/`. The installed create-pet 0.1.6 skill and its v2 contract were
used with the built-in imagegen tool. As in F18, this is a local candidate:
no Library write, upload, pet lifecycle action or app integration.

The new face remains visible in all sixteen looks. Its two ink eyes and smile
move together on the fixed belly; the handle stays left, spout right, and the
pot does not revolve. The original eye construction survives every expression.
The underside dot is visible only in waving frames 1 and 2 (zero-indexed),
with no blue in any other populated cell.

Commands (actual imagegen prompts and references are in `pip/prompts/used/`
and `pip/logs/`; generation happens between the dependency stages):

```sh
SKILL_DIR=/root/.codex/plugins/cache/openai-curated-remote/work-pets/0.1.6/skills/create-pet
RUN_DIR=/root/factory-out/F40/pip
python3 "$SKILL_DIR/scripts/prepare_pet_run.py" \
  --pet-name Pip \
  --description 'A small handmade white teapot with two uneven ink eyes, a quiet smile, and a secret blue dot under its lid.' \
  --pet-notes 'Keep Pip recognisably the original F18 teapot: plump slightly lopsided white handmade ceramic belly, round domed lid with little round knob, loop handle and short curved spout. Give Pip its own original face: two small warm dark ink oval eyes set a little unevenly, and a tiny soft curved smile on the front belly. No sclera, eyelashes, eyebrows, cheeks or nose. Expressions can blink, soften and concentrate without changing the eye design. Keep a single small blue dot only BENEATH the lid, visible only when the lid tips open in waving, hidden otherwise. No steam, exterior blue, pattern, limbs, loose effects, props or ground shadow. No known character likeness. Face remains visible in all directional poses; animate the painted face on the fixed ceramic belly with gentle lid and spout follow-through, anchored pot base; no whole-pot turntable.' \
  --style-preset auto \
  --style-notes 'Match the F18 reference: hand-drawn warm dark brown ink contour, imperfect curves, ivory ceramic fill, quiet restrained gray shading and faint paper texture. Compact tactile storybook teapot, not a 3D render. The new face uses that same warm ink.' \
  --chroma-key '#FF00FF' \
  --output-dir /root/factory-out/F40/pip \
  --reference /root/factory-out/F40/references/pip-f18-contact-sheet.png
# After each independently generated standard state:
python3 "$SKILL_DIR/scripts/extract_strip_frames.py" \
  --decoded-dir "$RUN_DIR/decoded" --output-dir "$RUN_DIR/qa/rows/$STATE/frames" \
  --states "$STATE" --method auto
python3 "$SKILL_DIR/scripts/inspect_frames.py" \
  --frames-root "$RUN_DIR/qa/rows/$STATE/frames" --states "$STATE" \
  --require-components --json-out "$RUN_DIR/qa/rows/$STATE/review.json"
python3 /root/factory-out/F40/pipeline.py pip standard
python3 /root/factory-out/F40/prepare_cardinals.py
python3 /root/factory-out/F40/pipeline.py pip row9
python3 /root/factory-out/F40/pipeline.py pip final
python3 /root/factory-out/F40/review_directions.py
python3 /root/factory-out/F40/pipeline.py pip quality
python3 "$SKILL_DIR/scripts/combine_direction_blind_verdicts.py" \
  --verdicts "$RUN_DIR/qa/blind-review-a.json" \
  --verdicts "$RUN_DIR/qa/blind-review-b.json" \
  --verdicts "$RUN_DIR/qa/blind-review-c.json" --json-out "$RUN_DIR/qa/blind-combined.json"
python3 "$SKILL_DIR/scripts/validate_direction_blind_verdicts.py" \
  --answer-key "$RUN_DIR/qa/blind-answer-key.json" \
  --verdicts "$RUN_DIR/qa/blind-combined.json" --json-out "$RUN_DIR/qa/blind-validation.json"
cp "$RUN_DIR/previews/final/idle.gif" /root/factory-out/F40/pip-idle.gif
python3 /root/factory-out/F40/audit.py pip
python3 tools/strings_check.py
git diff --check
```

The preparation command reproduces `pet_request.json`; the complete command
array is also in `logs/prepare-command.json`. The F18 assembly/registration
helpers were copied into F40, with their run root changed. They call the
installed bundled scripts, retaining exact commands and outputs in
`logs/{standard,row9,final,quality}-commands.jsonl` and matching output logs.
Standard rows use one shared scale and offset per row, preserving jump lift.
The coordinator and independent visual workers approved each dependency before
look generation. Row 9 was registered and reviewed before row 10; final
assembly preserves that exact row 9 and shares its registration transform.

Running-left was derived with the bundled
`derive_running_left_from_running_right.py --confirm-appropriate-mirror`.
The raw rightward strip had uneven spacing, so already extracted complete
frames were staged into safe slots before framewise mirroring, preserving
animation order. No handed marks, text, props or directional lighting prevented
that derivation. The exact staging/derivation commands and decision are in
`logs/gait-commands.txt` and `qa/rows/running-left/derivation/`.

Thirteen image generations include one rejected review strip. Its narrowed
eyes looked stern and brow-like, so the entire row was regenerated with plain
oval eyes, inspection glances and a pleased blink. A provisional standard
assembly containing the rejected row is retained and explicitly unapproved;
it was rebuilt before cardinal generation. Cardinal source-slot validation
also found stray edge alpha; as in F18, bundled connected-group extraction
recovered the intact poses, the bundled cardinal compositor rebuilt their
strip, and the mandatory extractor then passed. Failed evidence and originals
remain in the run. Row 10 needed six references; a two-panel image preserves
the entire F18 and F40 standard contacts together, leaving room for the base,
guide, approved cardinals and row 9. No reference was dropped.

The final stage ran one `despill_chroma_edges.py` pass, then
`validate_atlas.py --require-v2 --chroma-key '#FF00FF'` on the exact PNG and
lossless WebP. Both are `ok:true`, errors and warnings empty: 1536 × 2288 RGBA,
192 × 208 cells, eight columns, eleven rows, 73 populated cells and 15 fully
transparent unused cells, zero chroma fringe and zero hidden transparent RGB.
The PNG is 1,884,186 bytes; WebP 1,271,600 bytes. Their decoded RGBA pixels
match exactly, and acceptance hashes bind the reports to those files.

`validate_pet_quality.py` passes with no errors. The final jump lifts 37 px
and lands within 1 px of idle; maximum look-center drift is 1 px and width
ratio 1.02098. I inspected every final contact row at native size in three
batches, the neutral-plus-sixteen-look sheet, and the ordered jump stills.
The per-state GIFs, all-state GIF/MP4, idle–jump–idle loop and look loop were
rendered from the exact accepted atlas. All three isolated blind reviewers
confirmed all 28 tested axes; combined validation passes without ambiguity,
errors or warnings.

Six quality warnings are retained: intermediate spacing at 157.5, 247.5 and
337.5 is less even than ideal, and pixel-difference outliers occur at
157.5→180, 270→292.5 and 337.5→000. Native ordered review finds correct
quadrants, intact faces and stable bodies, without reversal or a conspicuous
snap. These are visual judgments, not relaxed validator thresholds. Their
landmark evidence and continuity review are in `qa/direction-semantics.json`.
The blue-dot audit finds 34 blue pixels in each raised-lid frame and zero in
every other populated cell.

Paul’s previews are `/root/factory-out/F40/pip-contact-sheet.png` and
`/root/factory-out/F40/pip-idle.gif`. The deliverable atlas is
`pip/final/spritesheet-extended.png`, with `pip/final/spritesheet.webp` beside
it. Full previews live in `pip/previews/final/`, prompts in `pip/prompts/used/`,
and validation/acceptance evidence in `pip/final/` and `pip/qa/`.

The string check passes (436 entries/keys), and `git diff --check` passes.
Only this maker record changes in the repository; F18’s history remains.
`App/` is untouched, so no App API assumptions or unconfirmed calls arise.
No Swift source changed and no Swift build/test rerun was needed. The runner’s
commit message is `/root/factory-out/F40/commit-message.txt`; no commit or push
was made.
