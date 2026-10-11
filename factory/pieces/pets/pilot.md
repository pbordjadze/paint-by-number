# F7: local teapot pilot

2026-10-11, Linux, Swift 6.2, `work-pets` **0.1.6**. Read the plan and the installed
`skills/create-pet/SKILL.md`, its animation reference, and the plugin's
`references/sprite-sheet-contract.md`. The older brief describes `hatch-pet` and v1;
this run used `create-pet` and v2: **1536 × 2288**, 192 × 208 cells, eight columns,
eleven rows, 73 required frames and 15 transparent unused cells.

The throwaway **Test Teapot** completed local generation, assembly, validation and
previews. It used `auto`, empty style notes, and a plain neutral teapot concept;
it makes no guardian or shared-style decision. No Library, upload, pet creation,
activation or update tool was called. Only this report belongs in the repo.
Task-controlled inputs, scripts, attempts, frames, logs and output are under
`/root/factory-out/F7`; the built-in image tool additionally retains its own
`/root/.codex/generated_images` cache. No API image fallback was used.

## Non-interactive execution

`codex-cli 0.162.1` was present. The actual non-interactive probe was:

```sh
codex exec --ephemeral --sandbox workspace-write --skip-git-repo-check \
  --cd /root/factory-out/F7 --json \
  --output-last-message /root/factory-out/F7/exec-final.txt - \
  < /root/factory-out/F7/exec-prompt.txt
```

It exited **1 after 0.316 seconds**, before executing the skill:
`failed to initialize in-process app-server client: Read-only file system (os error 30)`.
It also warned that PATH aliases could not be created. The prompt and exact command,
stderr and empty JSONL log are retained in `F7/logs/codex-exec*`. This machine's
read-only Codex state prevents proving unattended hatching through `codex exec`.
The local hatch instead ran in the active Codex session using built-in imagegen and
the skill's requested independent visual workers, at most three generating at once.
No sandbox permissions were broadened.

## Commands and artifacts

These variables identify the installed bundled scripts and the prepared run:

```sh
SKILL_DIR=/root/.codex/plugins/cache/openai-curated-remote/work-pets/0.1.6/skills/create-pet
RUN_DIR=/root/factory-out/F7/teapot
python3 "$SKILL_DIR/scripts/prepare_pet_run.py" \
  --pet-name 'Test Teapot' --description 'Throwaway local neutral teapot pilot for F7.' \
  --pet-notes 'A plain, neutral teapot. No guardian, branding, decoration, costume, extra props, or narrative. Use the automatic style without choosing a shared family style.' \
  --style-preset auto --output-dir "$RUN_DIR"
```

Preparation succeeded and wrote the v2 request, thirteen-job manifest, prompts and
layout guides. Imagegen generated the base first, then grounded every subsequent
strip in it and the required references. Actual row prompts are retained in
`teapot/prompts/used/`; the original generated prompts remain alongside them.
The imagegen skill requires genuine transparency, so calls requested transparent
backgrounds instead of the preparation script's magenta panels; magenta remained
the selected key for extraction and the mandatory cleanup/validation.

Every standard row used the bundled extraction and inspection commands, with
`STATE` replaced by its manifest state:

```sh
python3 "$SKILL_DIR/scripts/extract_strip_frames.py" \
  --decoded-dir "$RUN_DIR/decoded" --output-dir "$RUN_DIR/qa/rows/$STATE/frames" \
  --states "$STATE" --method auto
python3 "$SKILL_DIR/scripts/inspect_frames.py" \
  --frames-root "$RUN_DIR/qa/rows/$STATE/frames" \
  --json-out "$RUN_DIR/qa/rows/$STATE/review.json" --states "$STATE" --require-components
python3 /root/factory-out/F7/register_rows.py
python3 "$SKILL_DIR/scripts/inspect_frames.py" --frames-root "$RUN_DIR/frames" \
  --json-out "$RUN_DIR/qa/review.json" --require-components
python3 "$SKILL_DIR/scripts/compose_atlas.py" --frames-root "$RUN_DIR/frames" \
  --output "$RUN_DIR/final/spritesheet-standard.png"
python3 "$SKILL_DIR/scripts/make_contact_sheet.py" \
  "$RUN_DIR/final/spritesheet-standard.png" --output "$RUN_DIR/qa/contact-sheet.png" --scale 1
python3 "$SKILL_DIR/scripts/render_animation_previews.py" \
  --frames-root "$RUN_DIR/frames" --output-dir "$RUN_DIR/previews/standard"
```

All nine component inspections passed without warnings. The registration helper
only scales/translates extracted generated pixels, with one transform per row,
maximum width 150 px and baseline 185 px; it preserves the jump displacement.
The bundled compositor builds the atlas. Sources and native-size cells were
visually inspected, including an independent gait review.

Cardinals used `extract_cardinal_anchors.py` and `compose_cardinal_anchor_strip.py`.
The accepted cardinal report is `qa/cardinal-anchors.json`. Row 9 was generated,
registered and inspected before row 10:

```sh
python3 "$SKILL_DIR/scripts/assemble_extended_atlas.py" \
  --base-atlas "$RUN_DIR/final/spritesheet-standard.png" \
  --look-row-9 "$RUN_DIR/decoded/look-row-9.png" \
  --registered-row-output "$RUN_DIR/qa/look-row-9-registered.png" \
  --registration-manifest-output "$RUN_DIR/qa/look-row-9-registration.json" \
  --chroma-key '#FF00FF'
python3 "$SKILL_DIR/scripts/assemble_extended_atlas.py" \
  --base-atlas "$RUN_DIR/final/spritesheet-standard.png" \
  --registered-row-9 "$RUN_DIR/qa/look-row-9-registered.png" \
  --row-9-registration "$RUN_DIR/qa/look-row-9-registration.json" \
  --look-row-10 "$RUN_DIR/decoded/look-row-10.png" \
  --output "$RUN_DIR/final/spritesheet-extended-before-despill.png" \
  --manifest-output "$RUN_DIR/qa/extended-assembly.json" --chroma-key '#FF00FF'
python3 "$SKILL_DIR/scripts/despill_chroma_edges.py" \
  "$RUN_DIR/final/spritesheet-extended-before-despill.png" \
  --output "$RUN_DIR/final/spritesheet-extended.png" \
  --webp-output "$RUN_DIR/final/spritesheet.webp" \
  --json-out "$RUN_DIR/qa/chroma-despill-extended.json" --chroma-key '#FF00FF'
python3 "$SKILL_DIR/scripts/validate_atlas.py" "$RUN_DIR/final/spritesheet-extended.png" \
  --require-v2 --chroma-key '#FF00FF' --json-out "$RUN_DIR/final/validation-extended.json"
python3 "$SKILL_DIR/scripts/validate_atlas.py" "$RUN_DIR/final/spritesheet.webp" \
  --require-v2 --chroma-key '#FF00FF' --json-out "$RUN_DIR/final/validation-webp.json"
python3 "$SKILL_DIR/scripts/make_contact_sheet.py" "$RUN_DIR/final/spritesheet-extended.png" \
  --output "$RUN_DIR/qa/contact-sheet-final.png" --scale 1
python3 "$SKILL_DIR/scripts/make_direction_qa_sheet.py" "$RUN_DIR/final/spritesheet-extended.png" \
  --output "$RUN_DIR/qa/direction-sheet.png"
python3 "$SKILL_DIR/scripts/measure_direction_continuity.py" "$RUN_DIR/final/spritesheet-extended.png" \
  --json-out "$RUN_DIR/qa/look-continuity.json"
python3 "$SKILL_DIR/scripts/validate_pet_quality.py" "$RUN_DIR/final/spritesheet-extended.png" \
  --atlas-validation "$RUN_DIR/final/validation-extended.json" \
  --chroma-report "$RUN_DIR/qa/chroma-despill-extended.json" \
  --frame-review "$RUN_DIR/qa/review.json" \
  --direction-semantics "$RUN_DIR/qa/direction-semantics.json" \
  --continuity "$RUN_DIR/qa/look-continuity.json" --json-out "$RUN_DIR/qa/pet-quality.json"
python3 /root/factory-out/F7/render_final_previews.py
```

Each rebuilt candidate received exactly one despill pass. Both final encodings and
the quality gate report **`ok: true`**. PNG: 2,130,510 bytes; WebP: 1,446,548 bytes.
Jump lift is **61 px**, landing offset **0 px**, maximum look-center drift **2.5 px**,
and look-width ratio **1.054**. The quality report retains eighteen review warnings:
sixteen natural gaps between the feet and two adjacent-frame diff outliers. Native
inspection found no material holes, wrong quadrant, reversal or remaining size snap.

The bundled `make_direction_blind_qa_sheet.py`, `combine_direction_blind_verdicts.py`
and `validate_direction_blind_verdicts.py` also passed: three isolated reviewers,
fourteen randomized A/B pairs, all twenty-eight axis classifications correct, no
warnings. They received neither the answer key nor labeled look prompts/sheets.
The host Pets MCP preflight was not invoked; this was a local-only pilot, without
file transfer or lifecycle operations.

`previews/final/` contains nine state GIFs, all-state GIF and H.264 MP4, the
idle–jump–idle GIF, ordered look-loop GIF, and five labeled jump stills. These were
rendered from the exact final PNG; contact and direction sheets and the ordered
jump stills were shown and inspected. `ffprobe` confirmed the MP4 is 192 × 208,
8.84 seconds. `qa/acceptance.json` verifies that final PNG/WebP hashes still match
their successful validation reports.

## Cost, failures and repairs

Measured from preparation **08:10:22.884 UTC** through final local acceptance
**08:28:36.544 UTC**: **18 minutes 13.660 seconds**, including the CLI probe,
concurrent Swift verification, visual review and repairs. There were **21 image
generations**: base 1; idle 2; right 5; left 2; waving 1; jumping 2; failed 1;
waiting 1; active work 1; review 1; cardinals 1; look row 9 2; look row 10 1.
Summed generation-call wall time was **460.951 seconds**; parallel calls overlap.
One additional image-tool request was rejected before generation for six inputs.
Per-job logs and `logs/generation-summary.json` retain the accounting.

- Some initial strips clipped the outer spout/handle despite passing extracted-cell
  checks. Regenerating complete rows with smaller poses and broad empty end gutters
  repaired idle, jump and look row 9; gait also needed source-padding repair.
- Near/far stride prompts produced ambiguous or repeated-foot gait. After recurrence,
  the strategy changed to explicit alternating attached foot lifts with rest poses.
  Independent inspection caught the left hopping row; its second generation fixed it.
- The cardinal script's fixed slots cut unevenly spaced, otherwise complete source
  poses. The bundled connected-group extractor recovered all four; bundled cardinal
  composition aligned them before rerunning the mandatory extractor successfully.
- Jump extraction preserved lift but landed at 203 px versus idle's 180 px. The
  common registration helper fixed landing without inventing motion or redrawing pixels.
- Row 10 arrived at a larger source scale, causing a visible boundary snap while
  structural checks passed. One uniform **176/209** resize of its entire source strip
  preserved its pose family before the unchanged row-9 transform was reapplied.
  `qa/source-scale-registration.json` records this; `qa/revision-1/` preserves the
  rejected candidate and reports. Rebuilt geometry and previews were checked again.
- Imagegen accepts at most five reference paths. Removing the optional sixth,
  registered-row attachment retained all five required row-10 references and worked.
- The first Swift test process terminated with exit **143**, without a test failure
  summary; its cause was not established. The serial retry completed successfully.
  An initial hook assertion also failed because look prompts omit notes; this became
  a recorded finding. A jump extraction command initially used the wrong revision
  filename; selecting the accepted `decoded/jumping.png` fixed that command error.

## Can the plan's shared inputs steer every pet?

The hooks exist, but this pilot does **not** prove a consistent twenty-pet family.
A separate manifest-only run under `F7/hook-probe` supplied neutral technical style
notes and a reference, with no additional generations or style decision. Inspection
of all thirteen jobs found style and pet notes in the **base plus nine animation
prompts**, but **neither in the three v2 look prompts**. References were attached
to all thirteen. The coordinator must explicitly carry shared notes into those
look prompts; this run repeated its neutral constraints and look mechanics there.

There is also an input-limit mismatch: row 10 already needs five images before an
extra shared/user reference. The probe's additional reference makes six. Reference
consolidation or a compatible tool path is needed before relying on that input
across the set. A successful teapot with one automatic style only demonstrates
identity grounding within this pet, not cross-creature style control. The v2 floor
is thirteen visual jobs per pet, **260 for twenty**, before retries; the brief's
ten-job estimate is v1. Taste review and shared-style pilots remain untested here.
The right gait's last pose is mildly wider, and near-vertical intermediate looks
are subtle; both were reviewed, with no blocking acceptance defect found.

## Repository verification

```sh
swift build --scratch-path /root/factory-out/F7/swift-build -j 4
swift test --scratch-path /root/factory-out/F7/swift-build -j 4 --no-parallel
```

Build passed (100.94 seconds). Test retry passed: **298 tests in 24 suites**,
65.858 seconds of tests. Logs, build products, and the runner's commit message
are under `F7`, outside the worktree. No commit or push was made.
