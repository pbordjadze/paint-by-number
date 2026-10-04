# The picture library

The paintings and photographs the Samples pane offers: `App/PaintByNumber/Resources/Samples/`
(`<id>.jpg` and `library.json`), read by `Model/Sample.swift`. These are the standing rules for
what ships and how a picture is added or removed.

## The bar

The Samples pane is the first thing a new painter browses. The selection should make them
think "whoever picked these has taste". So:

- **Iconic or simply beautiful.** A mix of pictures people recognize at a glance (the Great
  Wave) and quieter ones that are lovely to look at. No filler, nothing that needs a caption
  to be appreciated.
- **Made for coloring.** Clear subject, a strong light–dark structure, distinct shapes, a
  palette with range but coherence, detail that a Relaxed template carries. Every candidate
  is judged on its generated template, not on the picture alone (Testing every candidate,
  below). Avoid very dark canvases (most Rembrandt): they make muddy templates.
- **A collection, not a pile.** Varied in era, place, subject, palette (warm and cool,
  bright and muted, the four seasons) and aspect ratio; no two pictures that feel like
  duplicates. Look at the whole library as one contact sheet and fix what jars.
- **Tasteful.** No nudity, violence, religious or political iconography as the subject, no
  identifiable living people, no brands or logos, nothing kitsch. Historic portraits are fine
  (a Vermeer); candid photos of strangers are not.

## License rules (hard; reject on any doubt)

Accept a picture only with written evidence on the source's own page:

1. **Paintings and prints:** the creator died in 1955 or earlier *and* the work was published
   or made before 1931 (public domain in the US and in life+70 countries), *and* the image file
   comes from a source that releases it as **CC0 or public domain**: the museum's open-access
   flag or license statement for that object. Preferred sources: The Met Open Access
   (`isPublicDomain`), Art Institute of Chicago (`is_public_domain`, IIIF images), National
   Gallery of Art (open access, CC0), Rijksmuseum (CC0), Cleveland Museum of Art (CC0),
   Smithsonian Open Access (CC0), Yale Center for British Art, Statens Museum for Kunst, Getty
   Open Content, Library of Congress (prints marked "no known restrictions"). Wikimedia
   Commons only when its file page shows a PD tag for the work *and* the source is one of
   these.
2. **Photographs:** CC0, or public domain as a work of the US federal government (NASA,
   NOAA, NPS, USFWS, USGS, Library of Congress FSA/OWI), or published before 1931. A NASA
   image counts only if NASA alone is credited (Hubble and Webb pictures credited to ESA, CSA
   or STScI are not public domain and are rejected). Unsplash, Pexels, Pixabay and Flickr
   "free" licenses are **not** public domain: reject.
3. **Never** works held by Italian state museums (Uffizi, Brera, …): Italian cultural heritage
   law restricts commercial reproduction regardless of copyright. Same caution for any source
   whose terms add their own conditions.
4. Living-artist styles, AI-generated pictures and "PD" claims on aggregator sites are out.

Every record is re-verified from its `source` by an independent check of its `evidence` (an
agent or person other than the one who found the picture) before it ships; anything that
can't be confirmed is dropped.

## The record

`library.json` is the library's single source of truth: which pictures ship, in which order
(`Sample.all` follows the file, so reorder there, not in Swift), and a record per picture:

```json
{ "id": "great-wave", "kind": "painting",
  "title": "The Great Wave", "creator": "Katsushika Hokusai", "year": "c. 1830–32",
  "credit": "The Metropolitan Museum of Art, H. O. Havemeyer Collection, …",
  "license": "CC0 / Public domain", "source": "<object page URL>", "image": "<file URL>",
  "evidence": "<the page's exact license sentence or API field>", "retrieved": "2026-10-02",
  "crop": "<what was cut off, and the resize>", "sha256": "<of the shipped file>",
  "work_title": "<the source's own title, where title shortens it>",
  "evidence_url": "<the page the evidence quotes>" }
```

- Required (`SampleLibraryTests.recordsAreComplete`): every field but the last two, none
  empty; `id` a flat file name (`^[a-z0-9]+(-[a-z0-9]+)*$`, the JPEG is `<id>.jpg`), `kind`
  `painting` or `photograph`, `source` an https URL, `retrieved` a `YYYY-MM-DD` date, no id
  twice. `work_title` and `evidence_url` are optional.
- `creator`, `year`, `credit` and `license` are proper names and facts: the app reads them at
  runtime and shows them verbatim in every language (Settings › Acknowledgements, the
  painting tiles' creator line and VoiceOver labels), so they stay in the audited record
  instead of a Swift copy that could drift from it.
- `title` is short and natural ("The Great Wave", "Earthrise", "The Milkmaid"): the work's
  common English title, shortened if it is long. It is translatable: the app shows the
  string catalog's `sample.<id>`, whose English must equal `title`.

## Preparing the file

Get the largest image the source offers and ship it at 2048 px on the long edge
(`ArtworkStore.sourceMaxPixelSize`; `SampleLibraryTests` accepts 1024–2048), sRGB, metadata
stripped, JPEG at the quality that keeps the whole library at most 25 MB (measure the total).
Crop only frames, mounts, color bars and scan borders, and say so in `crop`; never reframe a
composition. Straighten scans that are visibly rotated.

## Testing every candidate through the pipeline

Before curating, run each candidate the way the app will: `tools/eval.py run <pictures> --out
DIR -- --auto --length relaxed` (and `quick`), which converts the JPEGs for pbn and captions
the chosen settings, then read the sheets. New paintings are coloring books, so judge the book
too (`tools/eval.py book` with the maps made as [`coloring-book.md`](coloring-book.md),
Measuring a book, says). Drop candidates whose template is muddy, a crumble of tiny regions,
a stack of posterized bands, or whose numbers crowd. This is a taste gate, not a baseline: the
regression gate and the benchmark run on the six corpus photos of `Tests/Corpus`, pinned by
name (`SAMPLE_NAMES` in `tools/regression.py`), so curating the library moves no baseline and
no CI time.

## Order and starters

- **Order:** lead with showpieces; alternate paintings and photos, warm and cool, so the first
  screen of tiles looks curated on both iPad and iPhone widths. The pane shows Paintings, then
  Photographs, each in the file's order (`Sample.all(of:)`).
- **Starters** (`Sample.starters`, prepared on first launch): two, a painting and a
  photograph, chosen as the best first impression.
- The demo scenarios a viewer judges the app by (`gallery`, `create-preview`,
  `create-suggested`, the Samples pane) show the library by position, so reordering needs no
  demo edit; their screenshots change with it.

## Adding or removing a picture

Adding one touches four places, in the library's order:

1. `Resources/Samples/<id>.jpg`, prepared as above.
2. Its record in `library.json`, at its place in the order.
3. The `sample.<id>` entry of `Resources/Localizable.xcstrings`: a `comment` naming the work
   for translators (and where the title shows), `"extractionState": "manual"`, and
   `localizations.en` equal to the record's `title`.
4. Its `### <title>` entry at the same place in `ACKNOWLEDGEMENTS.md`'s Pictures section: the
   "creator, year" line, the credit line and the license line.

Removing one undoes the same four. Synchronized folders need no project edit either way.
Pictures are also named by id in code: `Sample.starters`, the demos' fixed pictures
(`ShellDemo.fixedPictures`, which UI tests launched with `-demoFixedPictures YES` look for by
title), the paint and file-opening demos, and unit tests. Search the app's sources for the id
and replace the picture there before removing it. A painting keeps its own copy of the photo
(`source.jpg`); one saved without it regenerates from the library picture its `sampleName`
names while the library offers it, and once that picture is gone it still opens but can no
longer be regenerated.

The checks:

- `SampleLibraryTests`: every record offered in order with the catalog's title equal to its
  `title` and its facts; complete records; every listed file bundled with its checksum and a
  long edge of 1024–2048 px; every bundled JPEG listed (no uncredited picture ships); starters
  a painting and a photograph.
- `AboutTests`: `ACKNOWLEDGEMENTS.md`'s Pictures section credits the same pictures in the
  same order with the app's lines.
- `tools/strings_check.py`: every record has its `sample.<id>` catalog entry with the
  record's title as its English, and no `sample.<id>` entry outlives its record.
