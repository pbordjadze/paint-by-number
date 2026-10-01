# W4 — Dark paper (Sonnet 5.5) — report

Branch `wt/w4-dark-paper`, head `87fd927`. Uncompiled here; strings_check ok (271), self-test passed.

## Changed
- `PaperAppearance` (light/dark/automatic, default light), `SettingsKey.paperAppearance`,
  `Preferences.paperAppearance` (unknown → light). Settings: "Paper" picker
  (`paper-appearance`) in its own header-less section after Painting (Painting already has a
  footer), with the spec's footer. Keys `paper.light/dark/automatic`, "Paper", footer.
- `CanvasPalette.darkPaper`: paper sRGB (0.13, 0.125, 0.12), backdrop (0.06, 0.06, 0.065), ink
  (0.78, 0.77, 0.75), no shadow, rim 0.3, `accentFloor` 0.35, `hatchCeiling` 1, outline 0.5.
  `CanvasPalette.resolve(_:interfaceIsDark:)`; Light under dark appearance keeps today's `.dark`.
- `PaintView` (`@AppStorage`) → `PaintCanvas` → `CanvasView.paperAppearance` → `canvasPalette`
  per frame and on trait change. `paperFragment` draws a 1-px light rim outside the sheet.
- Light paper unchanged: `accent(for:)` returns the paint when `accentFloor` is 0; rim alpha 0.
  Exports, thumbnails, time-lapse, `TemplateRasterizer` stay light (`CanvasSnapshot.Options.palette`,
  default light, replaces the unused `dark`).
- `CanvasUniforms`/`FrameUniforms`: 16 float4/int4 fields in the same order on both sides,
  `accent` and `rim` after `selected`; stride 224 → 256 (stride test updated). Both fill sites
  (`CanvasView.makeUniforms`, `CanvasSnapshot.uniforms`) use `setChrome`/`select`.
- Scenario `paint-dark-paper` (`paint-progress` on dark paper; registers the default instead of
  storing it). `-tracePaper YES` (DEBUG) sets `canvas-paper-light|dark` on the canvas.
- CLAUDE.md: one "Paper:" bullet after Photo peek.

## Shader literals
Already uniforms: paper (`u.paper`), backdrop (`u.background`), outline/number ink (`u.ink`),
hatch strength (`u.outline.z`), number opacities (`u.numbers`).
Moved: `highlightPaper` selected paint `u.selected.rgb` → `u.accent.rgb`; hatch-ink luminance cap
`0.4` → `u.accent.a` (light 0.4, dark 1); hover tint and hint pulse `u.selected.rgb` → `u.accent.rgb`;
paper shadow opacity `u.paper.a` (0 on dark); new `u.rim`.
Kept literal (not paper chrome): brush (selected paint, 0.28 fill, 0.95 white rim, 0.25 halo),
finishing sweep and wet meniscus sheen math, luminance coefficients, tint/hatch mix weights.

## Tests
CanvasRenderTests (dark render: dark paper, light number, paint kept, dark paint's highlight
visible; rim; stride; offscreen stays light), CanvasPaletteTests (contrast ≥ 4.5:1 for all
palettes, accent rules, resolution, CanvasView from preference + dark trait), PreferencesTests
`paperAppearanceDefaultsAndParses`, UI SettingsTests picker + DarkPaperTests.

## Open
1. UI tests assume XCUITest exposes the canvas container's identifier and menu items as buttons.
2. Light appearance + Dark paper: glass bars over a dark canvas; scenario captured in dark only.
3. Possible one-frame light flash before the first dark-paper draw (view backgrounds stay
   `systemGroupedBackground`).
4. Photo peek has no margin blend (margin 0): nothing to change.
5. `accentFloor` 0.35 and outline 0.5 are untuned: judge from screenshots.
