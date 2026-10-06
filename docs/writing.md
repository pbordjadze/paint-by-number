# Writing: notes and signs drawn legibly

Layered and coloring-book templates draw the writing in a photo, a note, a card, a hand-lettered
sign, as ink a painter can read (`LineArtSettings.keepWriting`, on by default). The stages and
their constants are `Writing`'s doc comment; the app finds the lines of text with Vision
(`TextFinder`) and hands them over as `LineArtInput.writing`; `pbn --writing` reads them as
polygons.

## Why the detectors can't

The owner photographed stuffed animals beside a handwritten note (a line of greeting and a heart,
in ballpoint on lined paper) and no setting made the note legible. Measured on that
photo: the line drawing runs at a long side of 768 px, where the pen is about a pixel and the
letters smear, and holds them at 0.4–0.8; the contour map (HED) draws none of them; the book
draws from 0.6, and tracing drops lines shorter than `minimumStrokeLength` (36 px) and bridges
gaps of 16 px, so what was left became scribbles. Writing has to come from the photo at canvas
resolution, where the template is drawn.

## The corpus

Writing is easy to overfit to one note, so every rule was judged on 53 photos (none committed:
the photos stay where they are published, and the owner's note is private).

- **The owner's note**: the motivating photo, from a feedback bundle (not committed).
- **The regression photos** (`Tests/Corpus`): no text; their templates must not change.
- **Eight Wikimedia Commons photos** of notes and hand-lettered signs, reduced to 2048 px on the
  long side:

  | Name | Commons file | Licence, author |
  | --- | --- | --- |
  | c00 | 2016 366 246 On the cafe door (29128501790).jpg | CC BY 2.0, Edna Winti |
  | c01 | Hand-lettered no smoking (43236006764).jpg | CC BY 2.0, Eric Fischer |
  | c03 | Guest list for a wedding.jpg | CC BY-SA 4.0, Claireneon |
  | c04 | Cancelation of 'Avondje uit' at Immanuël, Winschoten (2019).jpg | CC BY-SA 4.0, Donald Trung Quoc Don |
  | c05 | Central Line closed notice.jpg | CC BY-SA 3.0, Freerick |
  | c07 | Keep them sheep in (53170453485).jpg | CC BY 2.0, Safa Hovinen |
  | c08 | Farmácias de luto Mourning Pharmacies Pharmacies en deuil (8086028792).jpg | CC BY 2.0, Pedro Ribeiro Simões |
  | c09 | Blue sign "Danger! Slippery rocks - Do not take the risk".jpg | CC BY-SA 4.0, Basile Morin |

- **38 HierText images** (validation split; annotations CC BY-SA 4.0 from
  `google-research-datasets/hiertext` `gt/validation.jsonl.gz`, images from Open Images under CC
  BY 2.0, fetched from the `1398listener/Hiertext` mirror's `validation.tgz`): 30 scenes with
  handwriting (at least two legible handwritten lines of three or more characters at least 2 % of
  the short side high, all handwriting covering 0.5–35 % of the picture) and 8 with printed text
  only, sampled with `random.seed(11)`. Their line annotations stand in for Vision's lines.
  Handwritten: `d0643d7b9ccdcf5f f6749f3e0397a464 d44d01dd84a6cae0 ff36a7d36cdb2505
  ddb15f985f5167e7 585376b0f6c85bcf 57744d1d6f07c906 e09a252049f06a5d d681dafad85809ac
  f4305c5610ff670f 2d1d93daf2ffdf7a cf0142eb3037dde5 7bf68a14e5ae8164 3ff6a40f4278e231
  2b031a1466bf4b4f 141c2ff280973553 b0895e45757e51e7 fe42f07e244abf27 49e73a0c5894f7b6
  061730cf6f66b8e6 bc320ceceb4a40a1 743c85d498315a0e 122bba4b08520b1b 0f6dd07d35f2ecee
  0a3bc2f21ec1a7fc ef5f5caabf5e09fa ca53d1296468fadc 399263e9fd005727 7b5260c602c2842b
  dbe0b28f29f07278`; printed: `cde15a6c18360ddf 91f7cbd512961018 c3421dd00e99672d
  5bb91e064329e758 e5b1687bc73d7804 6cbac1608e9170f0 83285ce122bc46d2 dd90edd054effcaa`.

Method: maps from the app's networks run with PyTorch (`tools/models/convert_*.py`, Measuring a
book in `coloring-book.md`); lines of text from the HierText annotations, else EasyOCR's
detections standing in for Vision (it finds more fragments and single words than Vision's
lines); `pbn generate --line-style coloringBook --colors 24 --detail 0.6 --smooth 0.5 --seed 7`
with and without `--writing`; a sheet per photo and a gallery of every area's photo beside its
result, sorted by the stats `lineArt.stats.writing` reports per area (`WritingAreaStats`: the
verdict and the measures each rule reads).

## Results

The final run (the constants in `Writing`): every template valid, no number below legible size, and
the regression photos untouched (only the regatta's sail number has a box). Of 1,785 lines of text,
878 were kept; the rest were left to the detectors: 289 texture, 293 pictures (more ink than
paper), 211 too small or too large, 52 bold, 40 with too little ink, 21 with none and one with too
much. The writing stage took a median of 290 ms per photo with text on this build machine and at
most 1,070 ms (a map with a hundred lines of lettering); a note of a few lines takes tens of
milliseconds.

Legible: the owner's note, all six lines with its heart; the handwritten notices (the Dutch
cancellation, the Underground's line closure), the wedding guest list, the memorial card, the
notebook pages, the whiteboard mural's bubbles, the hand-lettered signs. Bold signs ("DANGER!
SLIPPERY ROCKS") stay the detectors' painted shapes, as before.

Each rule answers a failure the corpus showed:

| What went wrong | Where | Rule |
| --- | --- | --- |
| Chalk taken for dark ink: the board's dark frame lay as far below the board as the chalk above it | the chalkboard menu | polarity from the margin around the box |
| Bold letters' paper taken for ink where they filled the box | the bold test note | the same |
| Fringes of a line already painted out traced as crumbs by the next | dense signs, the menu | every area reads the photo as it is; drawn ink is claimed (`Ink.claim`); one paint-out at the end |
| The edges of bold letters beside small text traced as outlines | a protest sign, a coffee card | `Patch.wideStrokes` |
| A letter's stems on a smudged board taken for a ruled line | the menu | a continuation needs paper on both sides |
| A line taking its neighbours' ascenders and descenders | notes, the menu | ink goes to the box that holds most of it |
| A speech bubble, a globe, a frame touching a line's box | the mural | `coreShare`, `longestStraight` |
| Granite, a halftone print, grunge, spray paint on concrete traced as a mesh | a gravestone, a camera ad, a record cover | `maximumGrain` |
| Faint stamps and print broken into crumbs | a library stamp, a ticket | `maximumPieces` |

Lines kept and line traced on the photos those rules were made for, in the first corpus pass and
now:

| Photo | First pass | Now |
| --- | --- | --- |
| The owner's note | 6 lines, 1,055 px | 6 lines, 1,053 px |
| A gravestone (engraved granite) | 13 lines, 5,973 px of crumbs | 4 lines, 466 px |
| A camera ad (halftone print) | 32 lines, 13,458 px | 1 line, 115 px |
| A record cover (grunge print) | 11 lines, 9,684 px | 2 lines, 852 px |
| Spray paint on concrete | 22 lines, 6,644 px | 6 lines, 507 px |
| A chalkboard menu | 53 lines, 9,665 px | 24 lines, 3,099 px |
| A whiteboard mural | 25 lines, 24,925 px (bubbles and a globe) | 31 lines, 18,524 px |
| The Dutch notice | 15 lines, 10,038 px | 21 lines, 7,853 px |

Limits:

- Chalk on a smudged board comes through in part; much of it is grainy enough to be texture, which
  the detectors don't draw either.
- Engraved and embossed lettering (lit on one side of each stroke, shaded on the other) is texture
  or left out.
- EasyOCR boxes several lines at once where Vision boxes each line; such a box breaks into more
  pieces per height of line, and a few were judged texture.
- Ink touching a drawing that lies mostly beyond the box goes with the drawing.
- Painting the ink out changes the palette, which can move other parts of a book: the
  Underground notice's printed title, left to the detectors, lost a few strokes.

## Vision's lines

`VNRecognizeTextRequest` looks for text at least 1/32 of the photo's height by default; the
owner's note stood 1/51 to 1/22 of its photo's height, and three quarters of HierText's lines are
lower than 1/32. `TextFinder` asks for text down to 1/128 (`minimumTextHeight`), about the
lowest the writing stage keeps (`Writing.minimumHeight`, 10 canvas pixels). Of HierText's
handwritten lines, 93 % stand at least 1/128 of their photo's height, 64 % at least 1/64 and 25 %
at least 1/32. The simulator, which runs Vision's networks on the CPU, asks for 1/48: there text
this small added 10 to 70 s to each 560-pixel picture CI seeded.
