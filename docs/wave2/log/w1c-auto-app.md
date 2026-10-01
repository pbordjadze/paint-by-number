# W1c — Suggested settings, app integration (Opus 5.5) — report

Branch `wt/w1c-auto-app`, head `bb23b8e` (on claude/wave2 + wt/w1a-auto-core 72a0ecc). Uncompiled
here; strings_check ok (293 entries), self-test passed. No PaintCore changes.

## Departures from the spec
- `SubjectImportance.analyze(_:)` returns importance map + hints from one Vision pass (a separate
  `hints(for:)` would detect faces twice); `map(for:)` stays for regeneration and starter samples
  (no scene classification). Quantizing/filtering in a pure `hints(faces:animals:labels:)`.
- `Preview.settings` is optional: the first draft (center candidate via `firstDraft`) carries nil.
- While settings are chosen, sliders are disabled with placeholder values (VoiceOver: "Choosing
  settings…"), Start is disabled; `makeDraft()` waits for a running suggestion.
- The view calls `settingsChanged()` from the slider update instead of `.onChange(of: settings)`,
  so moving the sliders to the winner doesn't mark them custom or regenerate.
- Painting Length footer varies with the choice (about half an hour / about an hour / a few hours);
  Printed Templates moved to its own section ("The paper size printed templates are laid out for.").
- Extra scenario `create-custom-long-text`.

## App
- Hints: faces (existing detector), `VNRecognizeAnimalsRequest`, `VNClassifyImageRequest`; rects
  flipped to top-left, clipped, rounded to 0.01, sorted; allowlisted labels ≥ 0.3; animals raise
  the importance map like faces.
- Create flow: loading → analyzing → suggesting (`AutoSettings.choose` on the draft, `sourceSize` =
  the photo's size; `AutoSettings.draftImage(from:)` replaces the model's own reduction);
  3 candidates when `activeProcessorCount < 6`, else 5. First draft rendered on the pipeline thread,
  handed to the main actor by a closure formed in nonisolated code; a load counter drops a late
  draft. Winner = center → full resolution at once; otherwise the winner's draft (~100 ms) then
  full resolution. Cancellation: lock-protected flag set in `withTaskCancellationHandler`; a new
  photo or closing the flow cancels. If `choose` fails, the default settings, no chip.
- Origin suggested until a slider moves (then custom); Reset to Suggested reapplies the kept
  decision without a run. Chip: sparkles "Suggested for this photo" / "Custom · Reset to
  Suggested" button; VoiceOver Settings + state or Reset + value Custom; 44 pt; wraps.
- Settings: Painting Length (default Relaxed) replaces Starting Colors; `defaultColorCount`,
  `defaultColorCountValue`, `initialGenerationSettings`, `CreateModel(initial:)` removed.
- `Artwork.settingsOrigin`/`paintingLength` (strings; missing → nil; unknown kept; no bump);
  decision never stored; regeneration keeps the recorded settings.
- Scenarios `create-suggested` (lighthouse), `create-custom`, `create-custom-long-text` (parrots).
- CLAUDE.md: create flow suggesting bullet; Painting Length under Preferences.

## Tests
CreateModelTests (suggesting visible, draft before decision, ends ready + suggested with the
photo's size, slider → custom, Reset without a run, Start during suggestion, cancel on new photo
and close), PreferencesTests (Painting Length), LibraryTests (meta round trip, old files, unknown
values), SubjectImportanceTests (rounding, clipping, sorting, allowlist, Vision-empty run), UI:
CreateFlowTests (chip, Reset), LongTextTests (Reset), SettingsTests (Painting Length).

## Open
Vision classifier identifiers for the allowlist unverified (wrong ones only drop a label; no rule
reads labels yet); legacy `VN*` requests may warn on iOS 26; Settings UI test assumes Relaxed
stored; screenshots to check: create-suggested, create-custom, create-custom-long-text, settings,
landscape-create-preview.
