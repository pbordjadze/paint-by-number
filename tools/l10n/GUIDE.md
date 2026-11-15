# Translating Paint by Moonlight

How the app's words are carried into other languages. The mechanics are `tools/l10n.py`'s
docstring; this is the voice and the words. Every translator, person or model, reads it first.

## The voice

The app is a quiet place to paint on a rough day, and a capable studio on a good one. Its English
is plain, warm and unhurried: short sentences, everyday words, no exclamation marks, no hype, no
jargon, never cute. It speaks to the painter as a friend would across a table, and it never
scolds: something that can't be done is said gently, with what to do instead.

- Write what a native speaker would write for this screen, not a word-for-word copy. Keep the
  meaning, the warmth and the length roughly; shorter is better on buttons and titles.
- Address the painter informally where the language's best calm, friendly apps do: German `du`,
  French `vous` (Apple's own French is `vous`; keep it), Spanish `tú`, Italian `tu`, Portuguese
  (Brazil) `você`, Dutch `je`. Japanese: polite です/ます in sentences, plain noun phrases on
  buttons and titles. Korean: polite 해요체 in sentences, nouns on buttons. Chinese: no 您 for
  every sentence; plain, gentle, use 你 (Traditional: 你 as well).
- Follow Apple's own conventions for the language: its words for system things (Settings,
  Photos, Files, Share, Apple Pencil, VoiceOver, Dynamic Type, iPad, iPhone, App Store), its
  capitalization (English Title Case becomes the language's own: sentence case in French,
  Spanish, Italian, Portuguese, Dutch; German capitalizes nouns only), its punctuation (French
  non-breaking space before `: ; ? !` as Apple writes it, Japanese and Chinese full-width
  punctuation, German „…“ quotes, French « … »), and its ellipsis character `…`.
- Typographic apostrophes and quotes as the English uses (’ “ ”), adapted to the language.

## What must not change

- Placeholders: `%@`, `%lld`, `%1$@`, `%2$lld`. Every one the English has, of the same type. To
  reorder, number them (`%2$lld … %1$@`). `tools/l10n.py apply` refuses anything else.
- The Tool Guide's links `[words](guide:merge)`: translate the words, keep the target exactly.
  Its Markdown stays: `## ` headings, `- ` lists, `**bold**`, blank lines between paragraphs.
- Names: **Paint by Moonlight** and **Paint by Mosaic** stay in English everywhere (the brand).
  Apple product names stay as Apple writes them. Artists' names follow the language's usual
  spelling (Hokusai is 葛飾北斎 in Japanese, 葛饰北斋 / 葛飾北齋 in Chinese).
- Keyboard keys and symbols (⌘, ⇧, `]`, ✎) stay as they are.
- Keys starting `sample.` are titles of famous artworks and photographs: use the title the work
  is known by in that language (The Great Wave → „Die große Welle“, 神奈川沖浪裏), else translate.

## The app's own words

Keep each of these one consistent term per language across every screen (decide once, at the
start, and list them at the top of your work):

| English | What it is |
| --- | --- |
| painting | a paint-by-numbers picture the painter paints in the app |
| template | the numbered drawing a painting is made from, printed or shared |
| area | one numbered region to fill |
| cell | Refine/Edit's word for an area while drawing (the Cells tools) |
| paint, color | a numbered paint of the palette (both words appear; keep the distinction) |
| palette, swatch | the row of paints, one paint's button |
| Refine, Edit | the drawing tools (Edit is the newer name of the same thing) |
| Tool Guide | the pages that teach each drawing tool |
| Ink, Pen, Shapes, Eraser, Line Eraser, Bend Line, Select, Cell Edge, Merge, Move Edge, Make Cell, Bucket, Paint Brush, Eyedropper, Edit Paint, Looks, Move Number, Writing, Try Painting, Layers, Snap | the drawing tools and options, named like a drawing app's in that language (Procreate's own localization is a good reference) |
| Zen Mode | the mode that glides from area to area |
| Hint | finds the next area of the paint |
| The Making-of | the show of a photo becoming a painting |
| Unlimited Paintings | the one purchase; free paintings are counted before it |
| Painting Length: Quick, Relaxed, Detailed | how long a new painting takes |
| Sun, Moon, Auto | the music's two moods and the clock that picks |
| Tonight’s Picture | a library picture a day |
| Blank Page | drawing a picture of your own to paint |
| Paper (light, dark), Line Weight (Fine, Regular, Bold) | settings |
| mosaic, tile | Paint by Mosaic's painting and its areas |

## Checking your work

`tools/l10n.py apply <lang> <file> --dry-run` checks placeholders, plural categories and links.
Read the comment of each string: it says where it shows and what its placeholders are. Watch
length on buttons, tabs, segmented controls and swatch labels; the app is tested with doubled
English (`long-text` screenshots), so a translation up to twice the English fits, but shorter
reads calmer. VoiceOver strings (labels, hints, values, announcements) are spoken: write them to
be heard.
