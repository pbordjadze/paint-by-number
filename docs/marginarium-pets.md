# Pets in the Marginarium reader

A standalone Markdown image with a `pet:` URL places an interactive pet at that point in a
chapter, for example `![Pip lifts its lid](pet:pip)`. The importer writes a `pet` block with a
stable catalog key and a `pet` identifier. Its plain-text alt text becomes both the visible
caption and the VoiceOver description; the player adds the pet's localized action hint.
Keep the block's key marker when editing or moving it. Import and validate with
`tools/marginarium.py` as described in its docstring.

Pip and Colophon use their existing imagesets, idle timings and tap responses everywhere.
Two More Pets embeds them with the contents page's captions. No guardian artwork is bundled.
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
`tools/tests/fixtures/make_sprite_atlas.py <scratch-output.webp>`. The chapter screenshot demos
(`marginarium-chapter`, `-dark`, `-long-text`) open Two More Pets with Pip visible; the reader UI
tests also attach pet screenshots, including at accessibility text sizes.

## Bundled size budget

Measured on 2026-10-12 from the factory's Medea pilot `spritesheet.webp`
(`pilot-style-00-medea/attempt-pz1lsvml/final`, SHA-256
`aaeeebd7304eea0c545a4d5bae84f784c13b6836dadcb08fe93be2e368c33d0b`):

| Measure | Bytes |
| --- | ---: |
| Original v2 WebP | 585,444 |
| ZIP DEFLATE level 9 payload | 585,013 |
| One ZIP member, including archive/member headers | 585,191 |
| Twenty at the same compressed payload size | 11,700,260 |

One such guardian would add about **0.56 MiB** to the IPA; twenty comparable sheets would add
about **11.16 MiB**. This measures a raw bundled resource's ZIP contribution, not a signed Xcode
archive. WebP compresses little further in ZIP; final IPA packaging and signatures add overhead.
The pilot is a size sample, not approval to ship that art or a guarantee of the other pets' sizes.

Proposed budget: **1 MiB encoded per guardian and 20 MiB total for twenty**. Measure the final
approved sheets together before bundling; keep them as WebP resources instead of expanding every
frame into an imageset. This disk budget is separate from the decoded-memory cache limit above.
