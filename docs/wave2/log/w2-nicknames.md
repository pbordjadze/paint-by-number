# W2 — Whimsical color names (Sonnet 5.5) — report

Branch `wt/w2-nicknames`, head `3ce5177` (before the taste review). PaintCore built and tested;
app uncompiled here.

## Vocabulary
638 entries (`Sources/PaintCore/Foundation/ColorNicknameVocabulary.swift`; its doc comment carries
the style guide), each hex picked from the object or weather it names and checked on rendered swatch
sheets; dropped three-word names, Never-list clashes, leading-word-cap overruns, other-color and
brand-like names. 24³ in-gamut coverage sweep passes (≥ 5 anchors within ΔE 0.10 everywhere,
near-black/white/saturated corners included; near-blacks must be nearly pure black because OKLab L
is steep near 0).

## PaintCore
- `ColorNickname.assign(_:seed:)` per spec, with two deviations: a paint whose six candidates are
  taken keeps walking anchors within ΔE 0.12 (up to 24) before falling back (keeps 150-color
  palettes unique); draw weights are rounded to integers before the draw (a last-bit `exp`
  difference can't change a name).
- App seed `ColorNickname.seed(for: UUID)` = XOR of the UUID's two 64-bit halves; CLI uses
  `GenerationSettings.seed`. `pbn names <t.pbnt> [--seed N]`; stats.json `colorNicknames`.
- `ColorNicknameTests` (15): format, forbidden words, color-word-matches-anchor, coverage,
  uniqueness at 150, determinism, ≥ 30 % seed variation, non-empty fallback, nearest-wins (on the
  most isolated anchor: at a typical anchor the spec's weighting gives the nearest ~25–45 %).

## App
- `PaintingSession(nicknameSeed:)`, `colorNicknames`, `nickname(of:)`, `colorNameStyle` (set by
  `Preferences.apply`, updated on change).
- Palette: captions/Large Content Viewer/current-color "12 · Harbor Fog"; swatch labels and
  announcements "12, Harbor Fog, dark grayish blue". Long-press popover (Number/Name/Shade/Hex),
  VoiceOver action "Show Color Details".
- PDF key: nickname, structured name (secondary), hex + area count.
- Settings › Painting: Color Names Playful/Plain, hidden when not running in English (non-English
  shows the localized structured name everywhere).
- `paint-names-plain` scenario; tests in PreferencesTests, PaintSpeechTests, LocalizationTests,
  PaintingSessionTests, PDF key tests, UI (popover, Plain, Settings picker); AccessibilityUITests
  swatch-label regex updated. 9 catalog entries; no VERBATIM_FILES/ALLOWED_LITERALS change needed
  (nicknames reach the UI only as variables). eval.py: nickname + name on two lines per swatch.

## Results
`swift test`: 116 tests in 9 suites passed; release build ok; regression 18 cases all pass, all
templates "same". Parrots at 24 colors × 3 seeds: 24 distinct names each, varying by seed; a few
loose ("Morning Lake" on a warm gray, "Hemp Rope" on a green-gray) from the nearest-six pool
(~ΔE 0.05).

## Open
App/UI tests uncompiled; long-press + Button guarded by ignoring the tap while details are open
(not tried on a device); `eval.py run` not runnable here (no node), palette-label drawing checked
directly. `PDFExporter.hex` made internal.
