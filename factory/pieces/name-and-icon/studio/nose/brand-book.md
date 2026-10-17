# Photo Paint

**Name: Photo Paint (working name).** On the App Store: name "Photo Paint", subtitle "Turn any photo into a painting" (30 characters). The name is deliberately plain and descriptive for now, saying what the app does and leaving the mood to the icon and palette; it is a placeholder until a final name is chosen. In prose and store copy it is always written in title case, "Photo Paint".

Photo Paint turns any photo into a paint-by-numbers template. The generation quality is the product; the brand's job is to feel as polished as native iOS while carrying a small, darker, slightly witchy personality: midnight skies, gold stars, a plum signature, paper waiting to be painted.

## Principles

- **Native first.** SF Pro for interface text, standard navigation bars, segmented controls, sheets and lists. Photo Paint adds colour and a few motifs; it never restyles system controls into something custom.
- **Dark first.** Dark mode is the hero theme. Light mode uses the same tokens and stays clean and quiet.
- **Whimsy, sparingly.** Stars, sparkles and the crescent appear in the icon, empty states, and the fill moment. Never as wallpaper, never on every screen.
- **The template is paper.** Unpainted regions are always `paper`, outlined in `outline`, with numerals in New York. That look is the core identity and doubles as decoration.

## Colour

- `nightshade` is the signature: primary buttons (label in `paper`), selection, emphasis. One primary button per screen.
- `tint` is the SwiftUI accent: antique gold for text buttons in dark mode, nightshade in light mode.
- `surface-base`, `surface-elevated`, `surface-control` map to SwiftUI's background, secondary grouped background and fill roles.
- Paint pots `pot-1-midnight` through `pot-6-lavender` are the brand's illustration palette and the colours used in marketing and empty states. Real templates use colours generated from the photo; the pots never replace them.
- Gold (`pot-3-gold`) is the only colour for stars, sparkles and the crescent.

## Type

- Display: New York, Apple's system serif (`.fontDesign(.serif)` in SwiftUI). Use it for large titles, screen titles, empty-state headings, numerals in swatch chips and template regions, and the wordmark. It ships with iOS, supports Dynamic Type and needs no bundling.
- Interface text: the system font (SF Pro) at Dynamic Type sizes, matching the `Text` group — body, buttons, labels, lists.
- Numerals are New York Bold. In very small template regions (under 10pt) they may fall back to SF Pro Semibold for legibility.

## Wordmark

"Photo Paint" in New York Bold, title case, tracking −2%, always on one line. The dot of the "i" in "Paint" (only that one) is replaced by a four-point gold star (see Motifs/sparkle.svg); on light grounds the star is `nightshade`. Ink is `ink` on its theme's `surface-base`. Pair it with the app icon at roughly the wordmark's x-height to cap height.

## App icon

Direction C, "Landscape", v3 — Logos/app-icon-v3.svg at 1024×1024, full-bleed (iOS applies the mask). A midnight sky with a soft vertical gradient (#1B2448 at the top to #3E5290 at the horizon); a gold crescent with a faint radial glow; four sparkles and three pinpoint stars at varied sizes and opacity; a distant violet ridge; the nightshade hill with a gentle top-left light (#9A55A0 to #5A2B5E); and three regions still unpainted on warm paper — the foreground split into two (numerals "4" and "2") plus a patch of the hill ("7") — in New York Bold, sized down from front to back so the scene reads as a template in progress rather than a single labelled shape. v2 (a lone "4") is kept for reference. Gradients stay subtle, in the spirit of Apple's current icons: no gloss, no hard highlights. Outline the numerals to paths before exporting the final PNG so it does not depend on an installed font.

## Motifs

- **Numbered swatch chips:** circles filled with a paint colour, numeral centred in New York Bold; selected chip gets a 3pt `surface-elevated` gap ring then a 3pt `ink` ring.
- **The fill moment:** when a region is completed, colour floods outward from the tap point inside the region's outline, and two gold sparkles pop at the edge and fade. This is the signature animation.
- **Outline-and-numeral empty states:** an unpainted night landscape (outlines in `outline`, crescent outline in gold) above a New York title and one primary button.
- **Progress in paint:** a 16pt track in `surface-control` filled with segments in the colours already painted, labelled "18 of 48 regions painted".

## Consuming in SwiftUI

Create one colour set per colour token in the asset catalog with the token's name, using the Dark and Light values as the appearance variants. Set the app's accent colour to `tint`. Use `.fontDesign(.serif)` for the Display group and the default design elsewhere. Corner radii: `radius-md` for buttons and cards with `.continuous` corner style.
