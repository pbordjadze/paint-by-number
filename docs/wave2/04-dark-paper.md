# W4 — Dark paper

Model: Sonnet 5.5.

## Goal

A Paper preference (Light, Dark, Automatic) for the painting canvas. Dark paper is a deep
warm grey with light outlines and numbers, for painting in the evening or in dark rooms.
Paint colors are unchanged: paint is paint.

## Today (wave 1)

- `CanvasPalette` (`App/.../Canvas/CanvasTypes.swift`) holds the chrome colors (paper,
  backdrop, shadow) for light and dark *appearance*; `CanvasView` picks
  `CanvasPalette.appearance(dark:)` from the trait collection. In dark mode only the backdrop
  darkens; the paper stays light (0.925 vs 0.998) with a stronger shadow.
- Outline ink, number ink, the selected-color tint and hatching, the wrong-paint flash and
  the hint pulse are constants in `Shaders.metal` and `CanvasUniforms` (check each: some are
  passed as uniforms, some are literals in the shader).
- `TemplateRasterizer` (thumbnails, share images, PDF) has its own `Style.paper`; the
  create-flow previews use it too.
- Photo peek draws the photo over the canvas; its blend assumes light paper only in the
  shadow margin.

## Design

- Preference `paperAppearance` ∈ {light, dark, automatic}; default `light` (today's look).
  `automatic` follows the system appearance. Settings › Painting: a Picker "Paper" with the
  three options and a footer "Dark paper is easier on the eyes in a dark room."
- `CanvasPalette` gains a `darkPaper` variant used when the preference resolves to dark:
  paper sRGB ≈ (0.13, 0.125, 0.12), backdrop (0.06), shadow 0 (no drop shadow on dark; a
  1-px lighter rim instead), outline ink ≈ (0.78, 0.77, 0.75), number ink the same, the
  selected-color hatching and tint derived from the paint color but lightened to keep
  contrast against dark paper, wrong-paint flash and hint pulse lightened likewise. Every
  color that was a literal in the shader becomes a uniform (`CanvasUniforms` grows an `ink`
  and `accent` field), so the shader has one code path.
- Numbers: the SDF digit pass already takes a color; on dark paper the number color is the
  ink above, with the selected color's numbers bolder as today.
- Wet-paint darkening, the gloss sweep and the fill animation are unchanged; verify by eye
  that the gloss still reads on dark paper (the sweep is additive light; it should).
- Thumbnails, share pictures, PDFs and create-flow previews stay on light paper: the gallery
  and prints are paper-themed, and a painting's share picture should look the same whatever
  the canvas preference. The Settings footer does not need to say so.
- Photo peek: unchanged; check the margin blend on dark paper.
- Accessibility: contrast between ink and paper ≥ 4.5:1 in both palettes (a unit test
  computes it from the palette constants).

## Steps

1. Add the preference (`SettingsKey.paperAppearance`, `Preferences.paperAppearance`,
   `SettingsView` picker, `PreferencesTests`).
2. Move shader literals into uniforms; add the `darkPaper` palette; resolve the palette in
   `CanvasView` from the preference and the trait collection (`UITraitCollection` change →
   re-resolve), through the same path the light/dark appearance uses today.
3. Demo scenario `paint-dark-paper`: the painting screen on dark paper with some progress
   and a selected color, so the hatching and the numbers are both in the screenshot.
4. Tests: `CanvasRenderTests` renders a small template on dark paper and checks a paper pixel
   is dark, a number pixel is light, a painted region keeps its paint color; the contrast
   test; `PreferencesTests`.
5. UI test: Settings picker changes the value; the painting screen reflects it (query the
   canvas's accessibility value or the uniform via a `-tracePaper` launch argument, as
   `-tracePhotoPeek` does).

## Strings

"Paper", "Light", "Dark", "Automatic", the footer.

## CLAUDE.md

One line under the canvas notes: paper appearance preference, `CanvasPalette.darkPaper`,
chrome colors are uniforms.

## Acceptance

- Screenshot of `paint-dark-paper` looks right on iPad and iPhone; numbers legible at every
  zoom; selected-color hatching visible; gloss visible on completion.
- Light paper is pixel-identical to before (compare the `paint` scenario screenshot).

## Risks

- Shader literal hunting: list every literal color in `Shaders.metal` in the report, and
  which uniform now carries it.
