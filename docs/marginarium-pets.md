# Pets in the Marginarium reader

A standalone Markdown image with a `pet:` URL places an interactive pet at that point in a
chapter, for example `![Pip lifts its lid](pet:pip)`. The importer writes a `pet` block with a
stable catalog key and a `pet` identifier. Its plain-text alt text becomes both the visible
caption and the VoiceOver description; the player adds the pet's localized action hint.
Keep the block's key marker when editing or moving it. Import and validate with
`tools/marginarium.py` as described in its docstring. A guardian's drawing is the guardian,
never its pet (Paul, October 15): its alt text is the guardian's name alone (`![Medea](pet:medea)`),
and prose names the guardian, not "its pet"; only Pip and Colophon are pets, with names of their own.

Pip and Colophon use their existing imagesets, idle timings and tap responses everywhere.
Two More Pets embeds them with the contents page's captions. Pip's imagesets (`pip-idle-0...5`
from atlas row 0, `pip-wave-0...3` from row 3, 192 × 208 at the same 2x slot) are Pip's face
as Codex redrew it, so its lid-lift tap and timings are unchanged.

The guardians' drawings are bundled as `pet-<id>.webp` (the table below): the nineteen the factory
drew, which chapter 2 shows each in a pet block, and Dino's, which Paul made in the Codex app
before Dino joined the Lamp (Who's Who shows it, `MarginariumCast`), and chapter 1's margin notes show them beside the words (next section).
The contents page opens on them all, with Pip and Colophon, as small copies (`MarginariumView`).
The Moon's drawing is withheld: no `pet-moon.webp` ships and its notes show no pet.
To add a future atlas pet, place its sheet in
`App/PaintByNumber/Resources/pet-<id>.webp`, with a lowercase alphanumeric/hyphen identifier,
then use `pet:<id>` in the chapter. The unique filename survives Xcode's flattened resource
copy. The tool checks that the resource exists; runtime decoding checks its dimensions.

`SpriteAtlas` implements the create-pet v2 contract: 1536 × 2288 pixels, eight columns of
192 × 208 cells, top-left origin. Rows contain 6, 8, 8, 4, 5, 8, 6, 6, 6, 8 and 8 usable cells.
The final two rows are the sixteen clockwise looks. The player loops row 0 (idle), plays row 3
(waving) on tap, then returns to idle. Reduce Motion rests on idle cell 0 and cuts to one still
action pose on tap. Pip's lid lift and Colophon's bookmark pose retain their existing behavior.

ImageIO decoding uses `ImageCodec`, and both decoding and cropping run through `Background.run`.
`SpriteAtlasCache` coalesces concurrent loads and reuses the gallery's memory-warning-aware
`ImageCache` with a 32 MiB decoded-byte limit. At four bytes per pixel one sheet occupies
14,057,472 bytes (13.41 MiB), so two fit. Visible players retain their crops; evicted sheets can
decode again. Unreadable or wrong-size sheets produce no image or active button; the caption
stays readable. An unresolved pet identifier omits the block. Missing files and invalid cells
return nil. No force-unwrapping is used in the decoder.

`SpriteAtlasTests` exercises the actual WebP/ImageIO path, all cell rectangles and crop pixels,
bad resources, cache reuse and Reduce Motion plans. Its 2.2 KiB `pet-fixture.webp` contains only
colored geometry and belongs to the test bundle. Reproduce it with
`tools/tests/fixtures/make_sprite_atlas.py <scratch-output.webp>`. Its `thumbnails` test checks
the small cells a margin player keeps. The chapter screenshot demos (`marginarium-chapter`,
`-dark`, `-long-text`) open Two More Pets with Pip visible; `marginarium-chapter2` (also `-dark`
and `-long-text`) scrolls chapter 2 to Medea, and `marginarium-chapter1-margin` and
`-guardians` show the narrator's notes with Colophon and five guardians' notes, each guardian
drawn beside its note.
The reader UI tests also attach pet screenshots, including at accessibility text sizes.

## Pets beside margin notes

`MarginariumMarginNote` shows a small pet (52 pt wide, tappable, a tap waves it) for each
guardian who signed a margin note, once each, in the order they speak. The importer records
every signature of a note as `speakers` (and the last as `speaker`), so the names are the
chapter's own English signatures, never the localized text. `MarginariumSpeakers` is the one
table from a signature to a pet identifier: "the narrator" is Colophon because chapter 1
says "I am Claude, the narrator", "Codex" is Pip, and "the Moon" and "Bart" (who hasn't
hatched) are listed as having none.
`MarginariumSpeakersTests` fails when a speaker in the bundled chapters is in neither the
table nor the list of voices without a pet, or maps to a pet that doesn't resolve.

Where there is no margin column, a note opens in a card under the words it is about
(`MarginariumNoteCard`), and its pets wave as the card opens; beside a margin column, tapping
the words makes the pets of their notes wave (`MarginariumSpritePlayer`'s `greeting`). Chapter 1
has one pet block of its own, Colophon, right after Claude introduces itself, and every chapter
ends with its narrator's pet saying goodnight (Pip for Codex's chapter, Colophon for the rest),
a player with its own identifier, `marginarium-goodnight`, so a page never shows two elements
with the same one.

The pet is beside the note at ordinary text sizes and in a row under it at accessibility
sizes, so the words keep the line. It is hidden from VoiceOver: the note, which names its
speaker, is one element, and the pet adds nothing to repeat. Reduce Motion rests on idle
cell 0 and answers a tap with the still pose, as in chapters. A margin player keeps only the
cells it plays (`SpriteAtlas.thumbnails`: idle row 0 and waving row 3, redrawn to its size) and
lets go of the 14 MiB decoded sheet, which only the bounded cache keeps, so a page of notes by
five guardians holds five small sets, not five sheets. The slot is reserved before the sheet
arrives, so a note doesn't change shape.

## Bundled size budget

Budget: **1 MiB (1,048,576 bytes) encoded per guardian and 20 MiB total** for all of them,
kept as WebP resources instead of expanding every frame into an imageset. This disk budget is
separate from the decoded-memory cache limit above. `BundledPetsTests` checks both limits on
the shipped files, that every sheet loads through `SpriteAtlas` with the v2 contract, and that
its unused cells are transparent.

The factory's lossless v2 sheets (`factory/pets/<id>/spritesheet.webp`, 1536 × 2288) total
25,641,918 bytes, most between 1.0 and 1.9 MB. Five are already under 1 MiB and are copied
unchanged. The other fourteen are written as lossy WebP with the alpha channel kept lossless,
same 1536 × 2288 layout, at the highest Pillow quality (100 down) whose file fits 1 MiB:

```python
Image.open(source).convert("RGBA").save(
    target, "WEBP", lossless=False, quality=q, method=6, alpha_quality=100)
```

(Pillow 12.3.0, libwebp 1.6.0.) Eleven fit at quality 100, two at 98 (`hedge-witch`, `medea`)
and `robber-girl` at 93. Against the lossless sheets the alpha channel is bit-identical, the
unused cells stay fully transparent, and the mean absolute error over the whole sheet is
0.3 to 1.4 of 255 (largest for `robber-girl`), concentrated on hard ink edges. Idle and
waving cells inspected at native size and at 5x, on white and dark backgrounds, showed no
banding, no halo at the alpha edge (the glass droplet's soft rim and the eyes included) and no
colour fringe; the white ermine is among the five sheets kept lossless.

| Pet id | Source SHA-256 (`factory/pets/<id>/spritesheet.webp`) | App bytes | Encoding |
| --- | --- | ---: | --- |
| `baba-yaga` | `34b2be11506b45bf518ba5736b5631c74e64c9a40d5d5905f05542f99962f854` | 718,710 | lossless, copied unchanged |
| `balanchine` | `f4d7625cd1859228e3672497313735731f3e07a90be6add935b4657b25ead83f` | 843,370 | lossless, copied unchanged |
| `bible-school-teacher` | `a657aa4af6dd65c6c17d83c515b6d5d477a6734265f494071ee714f40f0fa5f3` | 798,748 | lossy WebP q100 |
| `bulat-okudzhava` | `a81a4ab70d2c28edff5717a6c1f6ea65319887dd6bc16de0a08cb663704b6eb3` | 976,192 | lossy WebP q100 |
| `child-at-bedtime` | `1885b30bf5f1c1d32ca2e205251ab2295287959f78fc1d1009f940697a3f13d8` | 602,310 | lossless, copied unchanged |
| `dinotopia` | `2352a8abf74dead6198d1fa15e9e8206b7105949b6c0e135550970cd4f4d5bc7` | 647,146 | lossy WebP q100 |
| `emily-dickinson` | `2fbcb5368fdfa4e69617d8afc52f8c34891d665c173fc3e59f09fb5e81d183fa` | 781,558 | lossy WebP q100 |
| `enchanted-workshop` | `949f77dcede148f31e8e06aa12f853e169ce5812843c8799a8f24bdb3ec8835d` | 771,484 | lossy WebP q100 |
| `glassblower` | `be734ac03874e040997e1b393abc0483b14684d3990f8d239d7d654f8faff49b` | 984,672 | lossy WebP q100 |
| `hedge-witch` | `7dde65e0562b8963f517deeac4230b4ee913c8287d9f422a9401dc54bc4e19b9` | 1,019,202 | lossy WebP q98 |
| `medea` | `384ee328a25e8e59205f7f8b4cce29083ed7640ea5131d08781857c8db29a2af` | 1,035,302 | lossy WebP q98 |
| `nutcracker` | `5139e69baa40fdf79a6bc7f033e12ed8d445e51e1398879979aa40e38c3df258` | 857,576 | lossy WebP q100 |
| `open-source-enthusiast` | `e65baf20d2646a4766e3eedb2aab01040ae3a4b269a7b56666e34cd28d0e360a` | 907,624 | lossy WebP q100 |
| `originality` | `041937c51452bbacf19d0218b712ed716e3402182185537726b350adcfd15955` | 674,790 | lossy WebP q100 |
| `painter` | `06415260a6eadfd84e0c48e5cf385c75567a954a3991f066afd3c2420c7f72ff` | 852,478 | lossy WebP q100 |
| `pirosmani` | `f914f776aab8d192e2b46b166dba50c9de7d0200e1b3dd9ba655d8b75f5f6c4c` | 912,802 | lossless, copied unchanged |
| `robber-girl` | `096b6e2b8499ef46ec32587fe5783e0e68993db78b737970d240c1a273e6d332` | 1,025,788 | lossy WebP q93 |
| `scholar` | `76077a95bf847119fced4ef0406b33c00203f37d1cf99c0abc3fe99afbe0760c` | 1,028,674 | lossy WebP q100 |
| `snow-queen` | `60e2057e81601ba9ceca48226e1a86517f24d109dbbc4f029fc5d4842c799979` | 1,033,114 | lossless, copied unchanged |
| `storybook` | `bc13623107ed5a5c83f75c4afd685750f87b050b5e0b083282479a8345e5beba` | 1,016,746 | lossy WebP q100 |
| **The factory's nineteen** | | **16,841,140** | factory lossless total 25,641,918 |
| **All twenty** | | **17,488,286** | |

The sheets in the app total **16,841,140 bytes (16.06 MiB)**, 8,800,778 bytes fewer than the
lossless originals: 4,110,306 in the five copied sheets and 12,730,834 in the fourteen lossy
ones; the largest is `medea` at 1,035,302 bytes. Zipped at DEFLATE level 9 the nineteen add
16,820,351 bytes of payload (16.04 MiB; the archive with headers is 16,822,611), because WebP
compresses almost no further. That measures the raw resources' ZIP contribution, not a signed
Xcode archive; final IPA packaging and signatures add overhead. Pip's ten replacement frames
add about 20 KB over the faceless ones.

Dino's sheet came later, from Paul: his Codex pet, exported from the app as a 1536 × 2288 PNG
(SHA-256 `e38ebb034a4cbafaeeb8e0da841a1d5954ffeb45f0d83079db18fef3826856b0`) that passes the v2
contract, its unused cells fully transparent. The factory keeps it as lossless WebP
(1,258,032 bytes, pixel-identical); the app's copy is lossy at q100 by the recipe above, 647,146
bytes, its alpha bit-identical and its error 0.5 of 255 over the sheet. The twenty sheets total
17,488,286 bytes (16.68 MiB).
