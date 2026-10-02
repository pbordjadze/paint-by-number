# The default library: 20–30 paintings, 15–20 photographs

## The bar

The Samples pane is the first thing a new painter browses. The selection should make them
think "whoever picked these has taste". So:

- **Iconic or simply beautiful.** A mix of pictures people recognize at a glance (the Great
  Wave) and quieter ones that are lovely to look at. No filler, nothing that needs a caption
  to be appreciated.
- **Made for coloring.** Clear subject, a strong light–dark structure, distinct shapes, a
  palette with range but coherence, detail that a Relaxed template carries. Every candidate
  is judged on its generated template, not on the picture alone (§ Testing).
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

Record every accepted picture in `App/PaintByNumber/Resources/Samples/library.json` (also
the source of the in-app credits, see App changes):

```json
{ "id": "great-wave", "kind": "painting",
  "title": "The Great Wave", "creator": "Katsushika Hokusai", "year": "c. 1831",
  "credit": "The Metropolitan Museum of Art, H. O. Havemeyer Collection",
  "license": "CC0 / Public domain", "source": "<object page URL>", "image": "<file URL>",
  "evidence": "<the page's exact license sentence or API field>", "retrieved": "2026-10-03",
  "crop": "removed mount, 0 px rotation", "sha256": "<of the shipped file>" }
```

The license auditor (an independent agent) re-opens every `source` URL and confirms the
`evidence` before the orchestrator curates. Anything it can't confirm is dropped.

## Scouting

Over-gather, then cut: ~50 painting candidates and ~35 photo candidates, so the final picks
are a real selection. The leads below are starting points to verify, not decisions; find
better ones where you can.

Paintings, by group (aim for the spread, not these exact works):

- *Japanese prints* (flat color and line, ideal for coloring, and the line-art study's best
  test case): Hokusai's Great Wave and Red Fuji, Hiroshige's Sudden Shower over Shin-Ōhashi
  and Plum Park in Kameido (Met, AIC, Brooklyn).
- *Impressionist and Post-Impressionist*: Van Gogh's Wheat Field with Cypresses (Met), The
  Bedroom (AIC), Irises (Getty); Monet's water lilies and Bridge over a Pond of Water Lilies
  (Met, AIC); Caillebotte's Paris Street; Rainy Day (AIC); Cézanne still lifes (Met, NGA);
  Gauguin's Ia Orana Maria (Met).
- *Dutch Golden Age*: Vermeer's The Milkmaid (Rijksmuseum). Avoid very dark canvases
  (most Rembrandt): they make muddy templates.
- *Decorative and natural history*: Mucha posters, William Morris designs, Haeckel's
  Kunstformen der Natur plates, Audubon's Birds of America.
- *American and British*: Winslow Homer (NGA), Sargent (Met), Turner (Yale Center for British
  Art).
- *Early modern*: Klimt's portrait of Mäda Primavesi (Met), Franz Marc, Kandinsky works before
  1931 — only where a CC0 image source exists.

Photographs, by group:

- *Earth from space*: Apollo 8 "Earthrise", Apollo 17 "Blue Marble" (NASA).
- *Landscapes*: national parks from NPS (Grand Prismatic Spring, Yosemite, Arches, autumn
  forests), USGS.
- *Wildlife*: USFWS and NOAA (puffins, wood duck, monarch butterflies, sea turtle, coral
  reef, bison).
- *Historic color*: Prokudin-Gorsky's color photographs of the Russian Empire (Library of
  Congress) and the FSA/OWI Kodachromes (1939–45): rare, beautiful, and stories in
  themselves.
- *Flowers and close-ups*: CC0 or US-government macro photographs.

Get the largest image the source offers; ship it at 2048 px on the long edge
(`ArtworkStore.sourceMaxPixelSize`), sRGB, JPEG at the quality that keeps the whole library
≤ 25 MB (measure; report the total). Crop only frames, mounts, color bars and scan borders;
never reframe a composition. Straighten scans that are visibly rotated.

## Testing every candidate through the pipeline

Before curating, run each candidate the way the app will: `pbn generate --auto --length
relaxed` (and `quick`), then `tools/eval.py run … -- --auto` for sheets. Read the sheets. Drop
candidates whose template is muddy, a crumble of tiny regions, a stack of posterized bands,
or whose numbers crowd. Note the chosen colors, detail and region count. Pipeline output
for the picture library is not a baseline (see Regression) — it's a taste gate.

## Curation

The orchestrator picks the final set: 20–30 paintings, 15–20 photos. Then:

- **Order** for `Sample.all`: lead with showpieces; alternate paintings and photos and warm
  and cool, so the first screen of tiles looks curated on both iPad and iPhone widths.
- **Starters** (`Sample.starters`, prepared on first launch): two, one painting and one
  photo, chosen as the best first impression.
- **Titles**: short and natural ("The Great Wave", "Earthrise", "The Milkmaid"); the
  painting's common English title, shortened if it's long.
- A contact sheet of the final library (every picture, in order, with its Relaxed template
  beside it) goes on the morning page, with the 8–12 alternates and why each was cut.

## App changes (on `claude/library-v2`)

Keep it native and small; no new screens.

- `Resources/Samples/`: the new JPEGs (flat names `<id>.jpg`) and `library.json`.
- `Sample` (`Model/Sample.swift`): add `kind` (painting, photograph), `creator`, `year`,
  `credit`. Titles stay catalog strings (`sample.<id>`, translatable); creator, year and credit
  are proper names and facts shown verbatim, read from `library.json` (or kept in a file listed
  in `VERBATIM_FILES` of `tools/strings_check.py`; choose one and say why). `Sample.all`
  follows the curated order.
- Samples pane (`Features/Create/PhotoSourceView.swift`): two sections, Paintings and
  Photographs (catalog strings), each tile's accessibility label gains the creator; a
  painting tile shows the creator under the title if the tile design has room (look at the
  long-text screenshots).
- Credits: Settings › About › Acknowledgements gains a "Pictures" section listing every
  sample (title, creator, year, credit, license), and `ACKNOWLEDGEMENTS.md` gains the same
  list; extend `AboutTests` so the two stay in step and every `Sample` has a credit.
- **The six former samples** (parrots, hibiscus, lighthouse, barn, espresso, regatta) leave
  the picker but stay in the bundle as `Sample.retired` (resolved by `Sample.named`, not
  listed): saved artworks reference them by `sampleName`, and regeneration falls back to the
  bundled photo when an artwork has no `source.jpg`. Never lose a painting. Their provenance
  is unrecorded, so they must not appear in the picker.
- Regression and bench: `tools/regression.py` and the `pbn bench` step in
  `.github/workflows/ci.yml` read every JPEG in `Samples/`. Pin both to the six retired
  samples by name (a list in `regression.py`), so `tools/baseline/*.json` stay valid and CI
  time doesn't grow tenfold. No baseline update is needed; if one happens, something else
  changed.
- Tests and demos: every reference to the old sample ids (`ShellDemo`, `DemoMode`,
  `PaintDemoView`, `PipelineCheckView`, UI tests, `LibraryTests`, `Fixtures`, …) keeps working:
  point demos at new showpieces where they show the picker or the gallery to a viewer
  (`gallery`, `create-samples`, `create-preview`, `create-suggested`), keep test fixtures on
  whatever is cheapest and stable. Add demo scenario `create-samples-paintings` (Samples
  pane scrolled to the paintings section) to `ci/scenarios.txt`.
- Strings: every new string in `Localizable.xcstrings` with comment and
  `extractionState: manual`; `python3 tools/strings_check.py` passes.
- `CLAUDE.md`: the library, `library.json`, the license rules (short), the retired samples
  and the regression pin.
- CI: read the iPad and iPhone screenshots of `create`, `create-samples`, the new scenario,
  `gallery` and `settings-acknowledgements` before merging; the Samples pane must look
  curated at both widths.
