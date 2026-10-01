# Wave 2 final review (Opus 5.5)

Head `f5ce66f` (two commits on 47a22ec; merged as 7d86694). No blocker; no pipelineVersion bump due.
148 tests in 11 suites pass; regression 24 cases all "same"; self-test 74; strings ok (302).

## Acceptance items not plainly met
- W1: "equal or better than 24/0.5 on ≥ 70 %": 6/69 by the spec's rule, 81 % at equal painting
  time; night-moon worse on both by 0.0011 ΔE — deviated, documented; owner decision.
- W1: CI `bench.txt` "suggest" line — missing: the benchmark step skipped every wave 2 push
  (it compared only with HEAD~1). Orchestrator: CI now compares with the shipping branch.
- W1: chip on iPhone light/dark — iPhone job not yet run in wave 2.
- W1: `analyze(_:)` instead of `hints(for:)`; per-length footers; ramp and "< 900 px" rules dropped;
  bands recalibrated — deviated, documented.
- W2: 5/60 at first, 0/60 after fixes; JND draw window; walks ≤ 24 anchors — documented.
- W3: ramp weight, ≤ 3 rings, allocation tests, ×1.10 band — not met; metric only (informational);
  documented; owner decision.
- W4: dark-paper screenshot only in dark appearance; accentFloor/outline untuned — documented.
- W5: share sheet listing in Photos — device-only (owner).
- W6: favorite in the card's accessibility value; Duplicate keeps it — documented.
- W7: QuickTime playback; BT.709 tag kept — documented.

## Cross-cutting: met
Demo code only in `#if DEBUG` (nesting-aware search); 10 new scenarios listed and reach
`markReady()`; tolerant `Artwork` fields, no format change; no new required-reason API; nothing new
to credit; PaintCore Foundation-only; no TODO/FIXME; no `defaultColorCount`/`initialGenerationSettings`
readers.

## Findings
Fixed: `e775420` the gallery Show menu's VoiceOver value ("All"/"Favorites"); `f5ce66f` CLAUDE.md
note that an opened file also closes the gallery's time-lapse sheet.
Left (major): CI on the merged head; the M1 suggest budget (benchmark skipped); the iPhone job.
Left (minor): a file arriving while PaintView's sheets or gallery rename/delete dialogs are up may
not present the create flow; Favorites as the stored filter after the library empties; Color Names
in the Painting section (footer explains only Advance to Next Color); `Preferences.paperAppearance`
read only by tests (like `paper`, `haptics`, `sounds`); `choose` failure generates on the sliders'
current values.

## pipelineVersion
No bump: no stage `TemplateGenerator.generate` runs changed; the 18 legacy cases are byte-identical.
`SubjectImportance.map(for:)` now raises animals like faces, so regenerating an old animal photo can
differ at the same settings — a different input, not a pipeline change.
