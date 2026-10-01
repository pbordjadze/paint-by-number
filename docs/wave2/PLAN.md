# Wave 2 plan

Status: approved plan, not started. Written on the `claude/wave2-plan` branch, which is
`claude/wave1-merge` (b5616f2) plus these documents. The implementing session starts here.

## What wave 2 delivers

The headline is **Suggested settings**: a photo opens in the create flow on settings chosen
for that photo, so the first template is right without slider fiddling. Everything else is
chosen to be small, self-contained and visibly delightful.

| # | Workstream | Spec | Size | Model |
| --- | --- | --- | --- | --- |
| W1 | Suggested settings (Auto) | `01-suggested-settings.md` | large | Opus 5.5 |
| W2 | Whimsical color names | `02-color-nicknames.md` | medium | Sonnet 5.5 (vocabulary), Opus 5.5 (review) |
| W3 | Gradient-aware palette allocation | `03-gradient-allocation.md` | medium | Opus 5.5 |
| W4 | Dark paper | `04-dark-paper.md` | small | Sonnet 5.5 |
| W5 | Share-sheet entry ("Open in Paint by Numbers") | `05-share-sheet-entry.md` | small | Sonnet 5.5 |
| W6 | Gallery search and favorites | `06-gallery-search-favorites.md` | small | Sonnet 5.5 |
| W7 | Time-lapse pacing (optional) | `07-timelapse-pacing.md` | small | Sonnet 5.5 |

Rules every implementing agent follows are in `RULES.md`. Each spec says what exists today
(wave 1 state, with file references), the design, the steps, the tests, the strings, demo
scenarios, acceptance criteria and risks.

## What wave 1 already did (do not redo)

Wave 1 (`claude/wave1-merge`) landed far more than `main` shows. Before touching anything,
read `CLAUDE.md` on this branch; the relevant parts for wave 2:

- Structured color names exist: `Sources/PaintCore/Foundation/ColorNaming.swift`
  (`ColorName`, "dark grayish green"), localized through `App/.../Model/ColorNameText.swift`,
  spoken by VoiceOver, printed in the PDF color key. W2 builds on them.
- A design note for Auto exists: `docs/design/auto-settings.md`. W1 is its concrete plan; the
  note's decisions stand (PaintCore, measured scores, one painting-length preference).
- Gradient bands are fused after segmentation (`Segmentation/BandMerging.swift`), transition
  strips and low-contrast crumbs merge, paints freed by fusing are re-spent
  (`PaletteRefiner`). What remains is the *allocation* problem at 24 colors (W3).
- Regeneration exists (`Library.regenerate`, `RegionRemap`, `PaintProgress.remapped`).
- Photo peek, Reduce Motion, VoiceOver canvas, Dynamic Type palette, TipKit tips, time-lapse
  progress and cancel, damaged-painting recovery, privacy manifest, About and
  Acknowledgements, a string catalog with `tools/strings_check.py`, and the quality regression
  gate (`tools/regression.py`, `tools/baseline/regression.json`) all exist.
- The template coding is versioned (`Template.formatVersion`, extension chunks) and
  `TemplateGenerator.pipelineVersion` is 2.

## Order of work

```
Phase 0  Orchestrator: branch, version decision, worktrees            (½ day)
Phase 1  W1a core · W3 · W2 · W4 · W6 in parallel worktrees           (the bulk)
Phase 2  W1b tuning (after W3 lands) · W1c app integration · W5 · W7
Phase 3  Integrate, regenerate baseline once, CI green, iPhone job, IPA
```

Dependencies:

- **W1b (tuning) waits for W3.** Allocation changes move the ΔE-versus-colors curve that Auto
  measures, so tune Auto on the pipeline it will ship with. W1a (the PaintCore API, the CLI,
  the tests on synthetic images) does not wait.
- **W1c (app integration) can start with W1a** because the spec fixes the PaintCore API up
  front. Integrate against the API, not the tuning.
- **W2 (nicknames) and W6 (gallery) touch the palette bar and the gallery respectively;**
  W4 (dark paper) touches the canvas. They do not overlap each other. W1c touches
  `CreateModel`, `TemplatePreviewView`, `SettingsView`, `Artwork`; W6 touches `GalleryView`,
  `ArtworkCard`, `Library`, `Artwork` (one new field each: coordinate the `Artwork` edit
  through the orchestrator, or land W6 first).
- **W3 and W1 both change pipeline output.** The regression baseline is regenerated once, by
  the orchestrator, after both are merged.

## Agent structure

One orchestrator session (Opus 5.5) on a `claude/wave2` integration branch cut from this
branch. It never writes feature code itself; it owns the integration branch, the CI loop,
`TemplateGenerator.pipelineVersion`, the regression baseline, `CLAUDE.md` and the merges.

Each workstream runs as one subagent in its own git worktree
(`.claude/worktrees/<name>`, branch `wt/<name>`), with `RULES.md` and its spec as the
brief. Subagents commit on their branch and do not push; the orchestrator merges and pushes.

Reviews: W1 and W3 each get an adversarial review by a second Opus 5.5 agent before the
merge (wave 1's reviewer found a blocker the researcher's own report had missed; that
pattern pays for itself on pipeline work). W2's vocabulary gets a taste review by Opus 5.5.
The small UI workstreams (W4, W5, W6, W7) are reviewed by the orchestrator reading the diff;
no separate reviewer.

Model choice, in one sentence each:

- **Opus 5.5** for anything that needs judgment without a compiler or a ground truth: the
  Auto estimator and its tuning, the palette allocation research, the app integration of Auto
  (concurrency-sensitive `CreateModel` changes), reviews, and the orchestrator.
- **Sonnet 5.5** for well-specified, bounded, test-guarded work: dark paper, gallery
  search and favorites, the share-sheet entry, time-lapse pacing, and writing the nickname
  vocabulary from a style guide with a lint test.

Usage discipline:

- Only the orchestrator pushes, and it batches: one CI run per integration step, not per
  subagent commit. CI (the only compiler for `App/`) takes 15–20 minutes; the orchestrator
  works on merges and reviews while it runs.
- Every subagent ends with a short report (what changed, test output, head SHA, anything
  unresolved) that the orchestrator keeps in `docs/wave2/log/<name>.md`, so the wave can be
  paused and resumed from the branch alone.
- If usage runs short, finish in this order: W4, W6, W5 (cheap, independent, shippable),
  then W3, then W1, then W2, then W7. A half-done W1 must not be merged; a finished W3 can be.

## Phase 0 checklist (orchestrator)

1. Confirm the state of wave 1: is `claude/wave1-merge` green on CI and merged to
   `claude/paint-by-numbers-app` (build 68 shipped)? If build 68 shipped with
   `pipelineVersion` 2, wave 2's pipeline changes (W1, W3) bump it to 3 in the integration
   commit. If not, it stays 2 (unreleased) and the bump waits.
2. Cut `claude/wave2` from the current head of `claude/wave1-merge` (or `main` once wave 1
   is merged there). Put the two open decisions from wave 1 (potrace GPL licence; sample
   photo licences) in front of the owner again; neither blocks wave 2's code.
3. Build the release `pbn` and run `tools/regression.py` once to make sure the gate is green
   before anyone changes the pipeline.
4. Create the worktrees and spawn Phase 1. Give every subagent: `RULES.md`, its spec, the
   session's attribution lines, and the worktree path.
5. Add `docs/wave2/log/` as subagents report.

## Phase 3 checklist (orchestrator)

1. Merge in the order W4, W6, W5, W3, W1, W2, W7 (small and independent first, so a broken
   merge is cheap to find).
2. Regenerate `tools/baseline/regression.json` once (`tools/regression.py --update
   --sheets`), look at every sheet, commit the baseline with a message naming the two
   pipeline changes. Decide `pipelineVersion` per Phase 0.
3. Push; run the iPad job; read `errors.txt`, screenshots of every new demo scenario, and
   the regression table. Iterate until green. Then the iPhone job via workflow_dispatch.
4. Whole-diff review by a fresh Opus 5.5 agent against each spec's acceptance list.
5. Update `CLAUDE.md` (every spec says what to add), `README.md` highlights (Suggested
   settings, color nicknames, dark paper, share-sheet entry, search and favorites).
6. Push to `claude/paint-by-numbers-app` for the IPA and the SideStore source.

## Cross-cutting requirements (from `CLAUDE.md`; every workstream)

- Every user-facing string goes through the string catalog in one of the three forms, with
  a catalog entry; `tools/strings_check.py` must pass. Color nicknames are data, not UI
  literals (see W2 for how they are displayed verbatim).
- Every screen worth a screenshot gets a demo scenario in `ci/scenarios.txt` that calls
  `DemoMode.markReady()`; demo code stays in `#if DEBUG`; `ci/check_release.sh` must pass.
- New behaviour gets tests: Swift Testing in `Tests/PaintCoreTests`, XCTest in
  `App/PaintByNumberTests`, UI tests in `App/PaintByNumberUITests`.
- Saved data rules: new `Artwork` fields decode tolerantly (`decodeIfPresent` with a
  default); no `Artwork.currentFormat` bump unless older apps must not open the folder; new
  template data goes in an extension chunk; never change how an existing format is read.
- Pipeline output changes: run `tools/regression.py --update --sheets`, look at the sheets,
  commit the baseline with the change; keep parallel float reductions deterministic.
- Required-reason APIs need a privacy manifest entry; ported code needs an Acknowledgements
  entry.
- Comments explain why, sparingly. No dead code, no TODO litter, no stubs.
