# W1 — Suggested settings ("Auto")

Model: Opus 5.5 (three agents: W1a core, W1b tuning, W1c app). Reviewer: Opus 5.5.
Builds on `docs/design/auto-settings.md`; that note's decisions stand. This spec makes them
concrete enough to implement without further design.

## Goal

A photo opens in the create flow on settings chosen for that photo. The user sees "Suggested
for this photo" and a template that is already good; the Colors, Detail and Smoothness
sliders remain, and moving one makes the settings "Custom". One preference, Painting Length
(Quick, Relaxed, Detailed), replaces today's global "Starting Colors" stepper.

## Today (wave 1)

- `GenerationSettings` holds `colorCount` (6…150), `detail`, `smoothness`, `seed`; every photo
  starts from `Preferences.initialGenerationSettings` (`defaultColorCount`, default 24, detail
  and smoothness 0.5). `App/.../App/Preferences.swift`, `Features/Settings/SettingsView.swift`.
- `CreateModel` (`Features/Create/CreateModel.swift`) decodes the photo, runs Vision
  (`SubjectImportance.map(for:)`, faces + foreground + saliency → `Grid<Float>`), makes a
  reduced `draftImage` (long side ≈ 640/1.5 before the generator's 1.5× cap, so the working
  draft is ~640 px), then generates a draft and the full template. Drafts take a few hundred
  milliseconds; `pbn bench` reports the "preview" regime (~467 px) separately.
- The pipeline already computes everything the analysis needs: `WorkingImage.okLab`,
  `StructureMap` (coherent vs. total gradient sums per axis), `ImportanceMap`,
  `PaletteBuilder.histogram` (64³ OKLab histogram over ~120k samples), `TextureMap`,
  `RegionAdjacency.boundarySteps` (mean image step across each boundary).
- `pbn generate` writes `stats.json` (region count, mean/p95 ΔE, tiny regions, label room,
  palette, color names, timings). `tools/eval.py`, `tools/compare.py`, `tools/regression.py`
  consume it. "Add fields, never rename them."
- `Artwork` records `settings` and `pipelineVersion`; `Library.regenerate(artwork:settings:)`
  re-runs the pipeline on the stored photo and carries progress over.

## Design

### The PaintCore API (fixed up front so W1c can integrate before tuning finishes)

```swift
// Sources/PaintCore/Auto/PhotoAnalysis.swift
public struct SubjectHints: Sendable, Codable, Hashable {
    /// Normalized rects (0…1, top-left origin) of detected human faces and animals.
    public var faces: [NormalizedRect]
    public var animals: [NormalizedRect]
    /// Scene labels with confidence (VNClassifyImageRequest identifiers the app chose to
    /// keep, e.g. "portrait", "landscape", "flower", "food", "night"); empty on Linux.
    public var labels: [String: Float]
}

public struct PhotoAnalysis: Sendable, Codable, Hashable {
    public var sourceWidth, sourceHeight: Int
    /// Weighted mean ΔE a k-paint palette reaches, for k in `paletteCurveKs` (8…64).
    public var paletteCurve: [Float]
    public var chromaticFraction: Float      // pixels with chroma > 0.04
    public var chromaSpread: Float           // std of chroma
    public var structureDensity: Float       // mean coherent gradient, normalized
    public var textureFraction: Float        // busy but incoherent pixels
    public var smoothFraction: Float         // pixels inside gentle ramps (sky, skin, bokeh)
    public var noise: Float                  // high-frequency energy in flat areas
    public var subjectCoverage: Float        // importance > 0.6
    public var importanceEntropy: Float      // 0 = one hotspot … 1 = flat
    public var faceCoverage: Float           // from hints, 0 without
    public var animalCoverage: Float
    public var labels: [String: Float]
}

public enum PaintingLength: String, Sendable, Codable, CaseIterable { case quick, relaxed, detailed }

public struct AutoCandidate: Sendable, Codable {
    public var settings: GenerationSettings
    public var score: AutoScore?             // nil until run
}

public struct AutoScore: Sendable, Codable, Hashable {
    public var fidelity: Float               // importance-weighted mean ΔE
    public var fidelityP95: Float
    public var regions: Int
    public var tinyRegions: Int              // under radius 3
    public var bandRings: Int                // regions bounded mostly by weak boundaries (see W3)
    public var minLabelRoom: Float
    public var estimatedSeconds: Double
    public var total: Float                  // lower is better
}

public struct AutoDecision: Sendable, Codable {
    public var analysis: PhotoAnalysis
    public var preference: PaintingLength
    public var candidates: [AutoCandidate]   // in evaluation order, scores filled in
    public var winner: Int                   // index into candidates
    public var settings: GenerationSettings { candidates[winner].settings }
}

public enum AutoSettings {
    public static let paletteCurveKs = [8, 12, 16, 24, 32, 48, 64]
    public static func analyze(_ image: RGBAImage, importance: Grid<Float>?, hints: SubjectHints?,
                               cancel: CancellationCheck) throws -> PhotoAnalysis
    /// The prior: a center and up to `maxCandidates` settings around it, deterministic.
    public static func candidates(for analysis: PhotoAnalysis, preference: PaintingLength,
                                  maxCandidates: Int) -> [AutoCandidate]
    public static func score(_ output: TemplateGenerator.Output, working: RGBAImage,
                             importance: [Float], preference: PaintingLength) -> AutoScore
    /// Runs the candidates on `image` (already reduced to the draft size), in parallel and
    /// cancellable, and picks the winner. `firstDraft` is called as soon as the center
    /// candidate finishes so the app can show something immediately.
    public static func choose(image: RGBAImage, importance: Grid<Float>?, hints: SubjectHints?,
                              preference: PaintingLength, maxCandidates: Int,
                              cancel: CancellationCheck,
                              firstDraft: (@Sendable (TemplateGenerator.Output) -> Void)?) throws -> AutoDecision
}
```

`NormalizedRect` is a four-float struct in PaintCore (no CoreGraphics). Everything is
`Codable` so `pbn` can write the decision as JSON and tests can pin it.

### Analysis (`analyze`)

Runs at the draft size (~640 px long side). Reuses the pipeline's stages, no new image
processing beyond what is listed:

- `paletteCurve`: for each k in `paletteCurveKs`, k-means++ seeds + 10 Lloyd iterations on
  `PaletteBuilder.histogram` samples (the same histogram the pipeline uses, so the curve
  reflects the pipeline's own weighting), reporting weighted mean ΔE. Seeded, deterministic.
  Cost: a few milliseconds per k on the 64³ histogram.
- `structureDensity`, `textureFraction`: from `StructureMap` (coherent magnitude vs. the
  summed step magnitude `w`): texture is `w` above a threshold with ratio below 0.5;
  structure density is the mean coherent magnitude normalized by its 90th percentile, as
  `ImportanceMap.fallback` does.
- `smoothFraction`: pixels whose per-pixel step is below `0.004` OKLab but whose box-blurred
  (radius = side/30) coherent magnitude is above `0.002` (a slope that persists across a
  window: a ramp, not a flat patch and not texture).
- `noise`: median absolute Laplacian of L over pixels with step below the ramp threshold.
- `subjectCoverage`, `importanceEntropy`: from the importance map after `ImportanceMap.make`
  (so the fallback counts too).
- `faceCoverage`, `animalCoverage`, `labels`: copied from hints, areas summed and clamped.

Quantize every feature to 3 decimals before it is used or stored, so tiny floating-point
differences between devices cannot flip a decision.

### Candidates (`candidates`)

A documented rule, not a learned model. Compute a center, then neighbours:

1. **Colors** `c0`: the smallest k on `paletteCurve` where the marginal gain per added paint
   falls below `0.0004` ΔE (interpolated between the sampled ks), clamped to the preference's
   color band. Then: `+4` if `faceCoverage > 0.05` (skin needs tones), `×1.25` if
   `chromaSpread` is in the top third of the corpus, `×0.6` if `chromaticFraction < 0.15`
   (monochrome / sepia), `+2` per 0.1 of `smoothFraction` above 0.3 only when W3's allocation
   is present (it needs steps for ramps), round to an even number.
2. **Detail** `d0`: the preference's center (Quick 0.3, Relaxed 0.5, Detailed 0.7), `+0.15`
   when `subjectCoverage > 0.5` (the subject fills the frame), `−0.15` when
   `textureFraction > 0.35` (foliage, gravel), `−0.1` when the source long side is under
   900 px (nothing to resolve), clamped to 0…1.
3. **Smoothness** `s0`: `0.4 + 0.5 × textureFraction + 0.3 × min(noise / 0.01, 1)`, and
   `−0.1` when `structureDensity` is in the top third (architecture stays crisp), clamped to
   0.25…0.8. Smoothness gets one value per photo; it does not multiply the candidates.
4. **Neighbours**: colors `{0.75 c0, c0, 1.3 c0}` × detail `{d0 − 0.2, d0, d0 + 0.2}`, pruned
   to `maxCandidates` by distance from the center (the center first, then the four
   single-axis moves, then diagonals). The default `maxCandidates` is 5; the app lowers it
   to 3 on devices with fewer than 6 performance cores.

The thresholds above are starting values. W1b tunes them (see Tuning) and writes the final
values into the code with a comment per constant saying what it was tuned on.

### Scoring (`score`)

Measured against this photo, as the design note requires:

- `fidelity`: importance-weighted mean ΔE between the painted template (region colors) and
  the working image, in true OKLab; `fidelityP95` likewise.
- `regions`, `tinyRegions` (inscribed radius under 3), `minLabelRoom` from the template.
- `bandRings`: regions whose boundary is weak (mean image step across it below 0.25 × the
  paint difference) over at least 70 % of their perimeter: the rings a ramp posterizes into.
  W3 adds this metric to `stats.json`; W1 uses the same function.
- `estimatedSeconds`: `PaintingTime.estimate` moved into PaintCore as
  `PaintingTime.estimate(regionCount:)` (the app keeps calling it through PaintCore).
- `total = fidelity + 0.5 × fidelityP95 + 0.02 × bandRings / regions + 0.01 × tinyRegions / regions + bandPenalty`
  where `bandPenalty` grows quadratically with the distance of `estimatedSeconds` outside the
  preference's time band: Quick 10–45 min, Relaxed 40–120 min, Detailed 100–300 min
  (region bands at 3 s per region: roughly 200–900, 800–2400, 2000–6000 regions at the
  working size; at the draft size scale by the area ratio before comparing). Ties (within
  0.002 of `total`) go to the fewer regions.

The weights are starting values; W1b tunes them. The scoring must be explainable from the
decision JSON: `pbn suggest` prints a table of candidates with every term.

### `choose`

Runs `analyze`, builds candidates, runs the center first and calls `firstDraft` with its
output, then the rest in parallel (`Parallel.mapBands` over candidates; each candidate's own
pipeline stays parallel too, so cap concurrency at the core count), each cancellable through
`cancel`. Scores every finished candidate, picks the winner. Deterministic for the same
image, importance, hints and preference.

### App integration (W1c)

- `SubjectImportance` gains `hints(for:) -> SubjectHints` next to `map(for:)`: faces from the
  existing `VNDetectFaceRectanglesRequest`, animals from `VNRecognizeAnimalsRequest`, labels
  from `VNClassifyImageRequest` filtered to a fixed allowlist of identifiers (people/portrait,
  animal kinds, landscape, sky, water, flower, food, night, building/architecture, vehicle,
  document/text) with confidence ≥ 0.3. Faces and animals also raise the importance map
  (animal rects the same way face rects do today; `VNDetectFaceLandmarksRequest` is **out of
  scope** for this wave). Quantize rects to 2 decimals.
- `CreateModel`: a new phase `.suggesting` after `.analyzing`. `prepare` returns importance,
  hints and the draft image; then `AutoSettings.choose` runs on the draft image with
  `firstDraft` → the preview shows the center candidate at once (as a draft), the winner
  swaps in when scoring finishes, then the full-resolution generation starts with the
  winner's settings. Sliders show the winner's values. `settingsOrigin: .suggested | .custom`;
  any slider change sets `.custom`; "Reset to Suggested" restores the decision's settings
  (no re-run). The decision is kept on the model for the artwork draft.
- `TemplatePreviewView`: a chip above the sliders: "Suggested for this photo" (sparkles
  symbol) that becomes "Custom · Reset to Suggested" (a button) once a slider moved. While
  suggesting, the status capsule says "Choosing settings…". Dynamic Type, VoiceOver label
  and value, long-text scenario.
- Settings: replace the "Starting Colors" stepper with a "Painting Length" picker (Quick,
  Relaxed, Detailed; default Relaxed) with a footer ("Suggested settings aim for about an
  hour of painting."). Key `paintingLength`; `Preferences.paintingLength`;
  `initialGenerationSettings` is removed (nothing starts from fixed settings any more; the
  create flow waits for the suggestion). Remove `defaultColorCount` and its tests; keep
  reading nothing from it.
- `Artwork` gains `settingsOrigin: String?` ("suggested"/"custom") and
  `paintingLength: String?`; `ArtworkDraft` carries them; `meta.json` decodes tolerantly; no
  `currentFormat` bump. The decision JSON itself is **not** stored (it is reproducible from
  the photo and the preference).
- Device budget: suggestion must finish within 1.5 s on the CI M1 and 4 s on an A15-class
  device at `maxCandidates` 5; `CreateModel` lowers `maxCandidates` to 3 when
  `ProcessInfo.processInfo.activeProcessorCount < 6`. The first draft appears no later than
  today's first draft.
- Demo scenarios: `create-suggested` (preview with the chip) and `create-custom` (after a
  slider move, showing Reset). `settings` scenario already exists and shows the new picker.

### CLI and tooling (W1a)

- `pbn suggest <image> [--importance map.pgm] [--hints hints.json] [--length relaxed]
  [--candidates 5] [--out dir]`: writes `decision.json` and prints the candidate table.
- `pbn generate --auto [--length …] [--hints …]`: chooses, then generates at full detail;
  `stats.json` gains `auto: {settings, winner, candidates: [...]}` and `analysis`.
- `tools/eval.py run … -- --auto` passes through; the sheet's caption shows the chosen
  settings.
- `tools/regression.py` gains the `auto` regime for the six samples: the baseline records
  the chosen settings per sample; a change in a choice shows in the table (informational
  band, since choices are expected to move when the pipeline moves) and the hard invariant
  is that the choice lies inside the preference's bands.
- `tools/auto_sheet.py <decision.json dir>`: one contact sheet per photo with every
  candidate's painted preview, its score terms, and the winner framed, for tuning by eye.

### Tuning (W1b, after W3 lands)

Corpus: the six samples, Kodak 01–24, scikit-image astronaut, chelsea, coffee, rocket, plus
at least ten photos the agent downloads that cover portraits, pets, night, snow, food,
architecture, and low-contrast fog (public-domain sources; record the URL and licence in
`docs/wave2/log/auto-corpus.md`). Hints for Linux come from a hand-written
`hints/<name>.json` for the photos with faces or animals.

Procedure:

1. For each photo, run `pbn suggest` at each Painting Length and build the auto sheets.
2. Judge each winner by eye against its neighbours; record every disagreement in a table
   (photo, length, winner, preferred candidate, why).
3. Adjust one rule or weight at a time; re-run; stop when at most 10 % of the (photo,
   length) pairs would have been chosen differently by eye and no pair is "clearly wrong".
4. Pin the final constants in code with comments, pin the corpus decisions in
   `tools/baseline/auto.json` (consumed by the `auto` regime), and write the tuning log.

Acceptance against fixed defaults (design note): on the corpus at Relaxed, Auto's fidelity is
equal or better than 24/0.5/0.5 at equal or fewer regions on at least 70 % of photos, within
the time band on every photo, and never worse than the defaults on both fidelity and
region count on the same photo.

## Tests

PaintCore (`Tests/PaintCoreTests/AutoSettingsTests.swift`):

- Analysis on synthetic images: a flat image (curve flat, smooth 0, texture 0), a gentle
  ramp (smoothFraction high), a checkerboard of 2-px squares (textureFraction high,
  structure low), a sharp rectangle (structure high, texture low), added Gaussian noise
  raises `noise`, a centred bright disc with a flat importance map vs. a hotspot map changes
  `importanceEntropy` the right way.
- Candidates: monochrome image gets fewer colors than a colorful one; Quick centers below
  Relaxed below Detailed; `maxCandidates` respected; order starts with the center;
  deterministic.
- Scoring: a template with more regions than the band scores worse than one inside it at
  equal fidelity; `bandRings` counts a synthetic ramp's rings and not a hard-edged contour.
- `choose`: completes under cancellation, calls `firstDraft` once before returning, picks a
  winner inside the band, byte-identical decision JSON on two runs.
- Fixture: `Tests/PaintCoreTests/Fixtures/auto-parrots.json` pins the decision for the
  bundled parrots photo at Relaxed (regenerated only with a documented reason).

App (`App/PaintByNumberTests`):

- `CreateModelTests`: loading a sample passes `.suggesting`, shows a draft before the
  decision, ends `.ready` with `settingsOrigin == .suggested`; a slider change makes it
  `.custom`; Reset restores the decision's settings without a new suggestion run.
- `PreferencesTests`: `paintingLength` default and persistence; `Artwork` meta round trip of
  the new fields; an old `meta.json` without them decodes.
- `SubjectImportance`: hints are quantized and the allowlist filters labels (unit test with
  a synthetic image where Vision returns nothing: hints are empty, not nil-crashing).

UI (`App/PaintByNumberUITests/CreateFlowTests.swift`): the chip reads "Suggested for this
photo" after a sample opens; dragging the Detail slider shows "Reset to Suggested"; tapping
it restores the slider value.

## Strings

"Suggested for this photo", "Custom", "Reset to Suggested", "Choosing settings…",
"Painting Length", "Quick", "Relaxed", "Detailed", the Settings footer, the chip's
accessibility value. All in `Localizable.xcstrings`; `tools/strings_check.py` passes.

## CLAUDE.md

Add: the `Auto/` folder and its API; `pbn suggest` and `--auto`; the `auto` regression
regime and `tools/baseline/auto.json`; the Painting Length preference; the rule that
analysis features are quantized and decisions are reproducible, never stored.

## Acceptance

- Opening any of the six samples shows a chip and a template without touching a slider,
  on iPad and iPhone, light and dark, with VoiceOver reading the chip.
- `pbn suggest` on the corpus reproduces `tools/baseline/auto.json`; Linux CI runs it.
- Budgets met (CI `bench.txt` gains a "suggest" line per sample).
- The reviewer could not find a photo in the corpus where Auto is clearly worse than the
  old defaults, and found the decision tables explainable.

## Risks

- Vision results can differ between devices and OS versions, so hints are quantized and the
  decision is never stored; a saved painting keeps its recorded settings.
- Overfitting to the corpus: the rules are few and named; the tuning log records every
  change and the reason.
- Time to first draft: the center candidate is the first draft; nothing waits for scoring.
