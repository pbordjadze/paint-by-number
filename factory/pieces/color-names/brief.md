# Piece: the paints' nicknames

The Lamp improves the nicknames the app gives each paint, without renaming a single paint in a saved
painting. Research of 2026-10-11 (file:line references are to `main` at that date).

## How nicknames work today

- `ColorNicknameVocabulary.swift:24`: 640 lines of `RRGGBB Name`, exactly at the test's cap
  (`ColorNicknameTests.swift:33`, 480 to 640). 135 one-word names, 347 distinct first words. Thin
  around cyan-blue (about 11 anchors at 210–240°), 88 neutrals.
- `ColorNickname.swift`: a paint's candidates are the anchors within OKLab ΔE 0.12 (`:81`, up to
  24). It draws among the six nearest within 0.02 of the nearest (`:65`), weighted
  `exp(-d/0.03)` rounded at ×1e6 (`:93`), with `SplitMix64(seed ^ index) % total` (`:63,96`). The
  seed folds the artwork's UUID (`:108`). Paints resolve in palette order; a taken name moves a
  paint down its list, and with none left the app shows the structured color name
  (`ColorNameText.swift:56-61`).
- The style guide is the table's doc comment (`ColorNicknameVocabulary.swift:2-23`), linted by
  `namesFollowTheStyleGuide`, `namesAvoidWhatTheStyleGuideForbids`,
  `colorWordsInNamesMatchTheAnchor` and `vocabularyCoversTheGamut`.

## Never rename a saved painting

Nothing is stored, so changing any of the following renames saved paintings silently: a name, a
hex, the order, the constants, the draw, the seed fold, `SplitMix64`, the OKLab math, or
`ColorName`'s thresholds. One changed anchor can rename other paints in the same painting
through the taken-name cascade.

**Design: frozen, versioned vocabularies, with the version recorded per artwork in `meta.json`.**
- `meta.json` is where the seed (`artwork.id`) already lives; the template has no UUID.
- Decode it like `settingsOrigin` (`Artwork.swift:161`): absent or unreadable means 1. Never
  `?? current`, which would silently upgrade old paintings.
- New artworks record the current version. An unknown future value is kept as written and
  resolves to the newest version this build knows.
- No bump of `Artwork.currentFormat`, the template format or `pipelineVersion`.
- An older build that rewrites `meta.json` drops the field. The painting then shows v1 names
  again, which is what that build showed anyway.
- Regeneration keeps the recorded version.
- Rejected: storing the resolved names. That reverses the root rule that nicknames are derived,
  never stored.

**First step, with no visible change:** ship the versioned engine at version 1. Pin v1 with a
digest of the table, and pin a palette in `App/PaintByNumberTests` too, so Apple's math is
checked. Today's one pin, `parrotsPaletteGetsDistinctNicknames`, runs only in Linux CI.

**Possible risk, to verify in Swift.** The integer weights feed `% total`, so a one-unit change
in any weight re-rolls a whole draw. A Python simulation found that a last-bit nudge changed many
picks. Its port of `assign` did not reproduce the parrots pin, so treat this as a lead, not a
finding. If it holds, an iOS update to its math library could rename paints in saved paintings.
The Apple-side pin above would catch it, and v2 should use a draw quantized to integers (distance
rounded to 0.001, weights from a table).

## The piece

- **Names only first.** Hexes, order and the draw stay; v2 changes strings only, so coverage and
  draw behaviour don't move. Moving or adding anchors comes later.
- **A batch** is about 20 anchors of one color family and lightness, ordered by traffic (how
  often paints in the 45 library pictures draw them). Each anchor is a slot with five candidates:
  the incumbent plus up to four proposals.
- **Agents edit** `{"batch", "edits": [{"hex", "name", "why"}]}`. Code merges winners into a
  `champion.tsv` and writes the Swift table; the loop never edits Swift.
- **The renderer:** a sheet of swatch cards with lettered names, shuffled per juror. Each name
  is also shown in use: the palette caption ("12 · Harbor Fog"), the VoiceOver line ("12, Harbor
  Fog, dark grayish blue"), the PDF key, and real assignments for six palettes × three seeds.
- **Craft checks:** the style-guide lints as a library oracle (`pbn vocab check`), plus unique
  names, a cap on magnet words (lamp, moon, night…), and the draw's pool sizes and fallbacks.
- **The guardians who matter most:**
  - the Scholar: does the name fit the swatch; real pigment lore;
  - Emily Dickinson: compression;
  - the Painter: the function seat, sayable and never upstaging the picture;
  - the Child at Bedtime, for dark and red batches: v1 has Void, Tar Pit and Event Horizon, and
    the lint misses Oxblood;
  - Originality: food names in the skin-tone range;
  - by region: the Hedge Witch for greens, the Moon for darks, the Snow Queen for pale cool
    colors, Pirosmani for warm earth, Nina for saturated colors.
- **The Georgian thread:** materials and gardens only (tarragon, walnut, qvevri clay), capped
  around 3% of names.
- **Calibration:** Paul rates 40–60 v1 cards keep or replace before any agent runs. His keeps
  carry into v2 and become the first calibration pairs. The first batch plants known-bad names:
  right grammar on the wrong swatch, a scary name, a cliché.

## The plan

1. Paul decides: new paintings only (recommended), names only first (recommended). He rates the
   v1 cards.
2. The versioned engine at version 1, with the pins. Needs CI.
3. Generalize `taste.py`: a loop plus a plug-in per piece, deciding slot by slot. Apply the eight
   fixes from the first run.
4. A calibration batch, run as a bake-off: the Lamp against one strong writer working from
   Paul's keep list. Paul picks blind. The Lamp runs the production batches only if it wins.
   Production would be about 12–16 batches, 150–250 agents.
5. A set review, then Paul's checkpoint with before-and-after sheets and real sample paintings.
   Then v2 ships as the current version.
