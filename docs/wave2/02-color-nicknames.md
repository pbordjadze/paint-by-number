# W2 — Whimsical color names

Model: Sonnet 5.5 writes the vocabulary and the code from this spec; Opus 5.5 reviews the
vocabulary for taste and accuracy before the merge.

## Goal

Every paint gets an evocative, tasteful name ("Harbor Fog", "Apricot Jam", "Moss After
Rain") that is accurate for its color, unique within the palette, and different from one
painting to the next, so seeing what the colors are called is part of the fun. The
structured name from wave 1 ("dark grayish blue") stays as the precise, localizable
description and the fallback.

## Today (wave 1)

- `Sources/PaintCore/Foundation/ColorNaming.swift`: `ColorName(oklab:)` classifies into 16
  families × 5 lightness bands × 3 chroma levels; `english` renders it; `PaletteColor.colorName`.
- `App/.../Model/ColorNameText.swift` localizes the structure; `PaintSpeech` speaks
  "N, <color name>"; the palette shows `current-color` ("12 · Dark green"); the PDF color key
  lists names; `pbn` stats and eval sheets print them.

## Design

### Vocabulary (`Sources/PaintCore/Foundation/ColorNicknames.swift`)

A table of entries `(name: String, oklab: SIMD3<Float>)`: a nickname and the exact color it
evokes. Size: 480–640 entries, spread over the gamut so that every paint the pipeline can
produce has at least five entries within ΔE 0.10, including neutrals, near-black, near-white
and pastels (check with the coverage test below). Each entry's anchor is written as a hex
sRGB value in the source for readability and converted once at startup.

Style guide for the names (the lint test enforces the mechanical parts):

- One or two words, Title Case, ASCII letters, spaces and at most one hyphen; at most 16
  characters; no digits.
- Concrete and evocative: things, places, weather, food, materials, times of day. "Harbor
  Fog", "Burnt Honey", "Slate Roof", "Last Light", "Cold Brew", "Fern Shadow", "Plum Ink".
- Never: brand names, people's names, body parts, skin-tone words, anything crude,
  religious, political or medical; no words that are a different color ("Blue Fog" for a
  grey); no plain color words alone ("Green"); no superlatives.
- Varied: no two entries share a leading noun more than 4 times ("Morning X" ×4 at most).
- Each anchor must actually look like its name to a careful person; the reviewer samples 60
  entries at random and rejects the table if more than 3 feel wrong.

### Picking (`ColorNickname.assign`)

```swift
public enum ColorNickname {
    /// A nickname per palette color: accurate (among the nearest anchors), unique within
    /// the palette, and varied by `seed` (the artwork's identity), deterministically.
    public static func assign(_ palette: [PaletteColor], seed: UInt64) -> [String]
}
```

1. For each paint, take the `k = 6` nearest anchors by OKLab distance (true OKLab, not the
   chroma-stretched working space), discarding any beyond ΔE 0.12 (fallback: the structured
   name's English title; never empty).
2. Weight each by `exp(−d / 0.03)` and draw one with `SplitMix64(seed ^ index)`: the
   nearest anchors win most of the time, the same paint gets a different name in a different
   painting, and a very close anchor is almost always chosen.
3. Resolve duplicates in palette order: a paint whose draw is taken moves to its next
   candidate; if all are taken, take the structured name.
4. Return the names in palette order.

The seed is the artwork's id (`UUID` folded to 64 bits) in the app and `GenerationSettings.seed`
in the CLI, so a painting's names never change and two paintings of the same photo differ.

### App

- `PaletteBar`: swatch captions and `current-color` read "12 · Harbor Fog"; the structured
  name stays in the accessibility value ("12, Harbor Fog, dark grayish blue") so VoiceOver
  users get both. A long-press on a swatch shows a small popover with the number, the
  nickname, the structured name and the hex value (also useful for mixing real paint).
- PDF color key: nickname, then the structured name in secondary type, then the hex code.
- Nicknames are English data in PaintCore. They are shown with `Text(verbatim:)` and added to
  `VERBATIM_FILES` / `ALLOWED_LITERALS` in `tools/strings_check.py` as the spec of that script
  requires; when the app runs in a language other than English, the structured (localized)
  name is shown instead of the nickname, everywhere. (A translated vocabulary is a later
  wave; the code path already exists.)
- Settings: "Color Names: Playful / Plain" under Painting (default Playful). Plain shows the
  structured names only.
- `pbn generate` stats gain `colorNicknames`; eval sheets print "Harbor Fog · dark grayish
  blue" under each swatch; `pbn names <template.pbnt> [--seed N]` prints a palette's names
  for review.

## Tests

PaintCore (`ColorNicknameTests`): coverage (a 24³ sweep of in-gamut OKLab colors finds ≥ 5
anchors within 0.10 for every sample that the pipeline can produce, i.e. inside the sRGB
gamut); lint (every rule of the style guide that is mechanical); uniqueness within a
150-color palette; determinism; different seeds give different assignments for the same
palette (at least 30 % of names differ); the fallback is never empty; the nearest anchor is
chosen most often (statistical test over 1000 seeds on one paint: the nearest wins ≥ 50 %).

App: `PreferencesTests` for the Playful/Plain key; `AccessibilityTests` for the swatch
value format; a `LocalizationTests` case that a non-English locale shows the structured
name; `RenderingTests` for the PDF key lines.

UI: `paint` scenario already screenshots the palette; add `paint-names-plain`. A UI test
that long-pressing a swatch opens the popover with the three lines.

## Strings

"Color Names", "Playful", "Plain", the popover's labels ("Number", "Name", "Shade", "Hex").
The nicknames themselves are verbatim data (see above).

## CLAUDE.md

Add the nickname table, its style guide location (this file), the verbatim rule, the
English-only rule, and `pbn names`.

## Acceptance

- The parrots sample's palette shows 24 distinct, apt, charming names; the reviewer signs off
  on the table (sample of 60).
- Nothing in the app shows a nickname in a non-English locale.
- All tests above pass; `tools/strings_check.py` passes.

## Risks

- Taste is subjective: the reviewer gate and the style guide are the control.
- A paint far from every anchor (rare, e.g. a saturated violet) falls back to the structured
  name; the coverage test keeps that rare.
