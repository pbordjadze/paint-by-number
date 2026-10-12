# Piece: the pets

One pet per member of the Lamp (the 18 seated guardians, Originality, and the Bible School
Teacher while she waits for a seat): 20 animated companions hatched with the Codex app's `hatch-pet` skill. They
are the jurors' faces on review pages and the collection page, and maybe one day in the app (issue
#16, after the Originality and Open Source guardians have checked OpenAI's terms). Each starts from
the one-line seed already on the collection page (Medea's golden ram, Pirosmani's giraffe,
Okudzhava's trolleybus, …).

## Who decides what

| Decision | Decided by | Why there |
| --- | --- | --- |
| The set's style sheet: the skill's style preset and shared style notes, framing, palette, line, how the nine animation rows read, the set's boundaries | The Lamp, then Paul | It is what makes 20 pets one family, and it costs only text to judge |
| Each pet's brief (appearance, personality, physical expression, emotional range, signature behaviors, boundaries; 150–300 words) | Its own guardian drafts; a jury checks the set; Paul | Character is taste, and the guardian knows its idea best |
| Turning a brief into a pet, within the style sheet | Codex | Generation and execution: a coordinator keeps the set consistent, one agent per pet, at most three image workers at once |
| Technical choices the style sheet leaves open (resolution, frames, export) | Codex | Craft, not taste |
| Whether a hatched pet is done | The Lamp's image review, then Paul | The judge is never the maker |

Codex never changes a pet's creature, personality, boundaries or the style sheet. When a brief
doesn't work as an image, it says so and proposes; the Lamp decides.
Motion numbers in a style sheet guide the drawing. Differences belong in provenance; only the
skill's validators gate a pet. The image jury still judges the resulting character and motion.

## What a pet is (research, 2026-10-11)

- **Made by** the bundled `hatch-pet` skill (Settings › Pets › Create pet, or `$hatch-pet <concept>`):
  one base image plus nine row strips through `$imagegen`, then deterministic scripts that build and
  validate the atlas. About ten image generations per pet, so 200 or more for the set. Image
  generation uses Codex's limits three to five times faster than text.
- **A pet is a folder**, `~/.codex/pets/<id>/`, holding `pet.json` (id, displayName, description,
  spritesheetPath) and `spritesheet.webp`. The sheet is a transparent atlas, 1536 × 1872: eight
  columns of 192 × 208 cells and nine rows, one per animation: idle, running-right, running-left,
  waving, jumping, failed, waiting, running, review. A web page animates it with CSS `steps()`, so
  the collection page and issue #16 can show the pets moving.
- **The skill's inputs** are the hooks for the Lamp's decisions:
  - a style preset, one of auto, pixel, plush, clay, sticker, flat-vector, 3d-toy, painterly or
    brand-inspired;
  - style notes, pasted into all ten prompts;
  - pet notes, also pasted into all ten prompts;
  - optional reference images.
  One preset and one set of style notes shared by every pet is what makes them a family.
- **Personality has no hook of its own.** The rows' prompts are fixed, so each brief adds one
  sentence per row: happiness in waving and jumping, concentration in running and review,
  impatience in waiting, failure in failed.
- **The skill rejects** floating effects, speech bubbles, shadows, text, new props in review, and
  an idle that barely moves. The ground is transparent, so a night ground belongs to the page the
  pets stand on, not to the pets.
- **Bulk:** no documented command, config or API. `codex exec` with `$hatch-pet` may work; pilot one
  pet first. Otherwise it's one chat per pet.
- **Terms:** OpenAI's terms assign the output to the user, and its image docs ask for original
  designs rather than imitations. Re-read the live terms before any pet ships in the app; never
  reuse OpenAI's own pets.

## The run

1. **Style sheet** (one or two rounds of text). The parameter format: the preset; the style notes
   (at most 80 words, shared by all); framing (for example, the full body fills about 75% of the
   cell height on a flat baseline); palette rules; line; the set's boundaries. A jury of six
   shortlists two.
2. **Pilot hatch:** Codex hatches the same two pets in each shortlisted style, an animal and an
   object (Medea's golden ram and Okudzhava's trolleybus). That's about 40 image generations, spent
   before the 200. Hatch idle and running-right first as the identity and gait check, and pilot
   `codex exec` on the way.
3. **Style decision:** a jury of six looks at the pilots' contact sheets and preview GIFs and picks
   one style. Paul approves or vetoes.
4. **Briefs:** each guardian expands its own seed into a brief of 150–300 words, plus the two parts
   the skill needs: pet notes (50–80 words of appearance) and one sentence for each of the nine
   rows.
5. **Set review:** one jury of six reads all 20 briefs side by side and only flags problems:
   off-style, a broken boundary, a franchise look-alike, a real person's likeness. A flagged brief
   goes back to its guardian once. Paul approves the set.
6. **Hatch:** Codex, coordinator plus one agent per pet, at most three image workers at a time.
   Each pet is gated on the skill's `validate_atlas.py` and `validate_pet_quality.py`.
   Codex returns `factory/pets/<id>/`
   (`pet.json`, `spritesheet.webp`, the contact sheet) and a log of what each pet was made from.
7. **Image review:** a jury of six looks at the contact sheets and says keep, or redo with one
   line why. Codex redoes; Paul has the last word.

Before the run, apply the first run's fixes (`How the Panel Named Itself`): agents answer in
their reply instead of writing files (about a third of the tokens), the shared brief stays plain,
a veto must quote the charter line it breaks, Originality gets a glossary, and one seat guards
function. For pets, function means the pet reads at 192 × 208 and in all nine rows.

Rough cost: about 50 Haiku agents on the Claude side (about 1.2 million Haiku tokens with replies
instead of files), and on Codex's side about 40 pilot plus 200 set image generations, more for
redos.

## The Lamp's answers (chapter 6, 2026-10-11)

Chapter 6: https://claude.ai/code/artifact/8a53579f-2e12-4e71-8e26-e81dfa8cd892; replies in
`pieces/chapter-6/replies/`.
- **Every guardian keeps its pet** (18 of 18).
- **Where they live:** the Marginarium first (16 of 18 glad of it); keeping you company while a
  template is made second (13). A companion beside the canvas split the Lamp (10 glad, 4 vetoes:
  the Painter, the Glassblower, the Snow Queen, Balanchine). App icons were vetoed five times.
- **Originality's look-alike list** (Baba Yaga, Hedge Witch, Snow Queen, Robber Girl, Enchanted
  Workshop, Nutcracker, Pirosmani) goes into each pet's brief as a do-not-resemble list.
- **The plan:** the Lamp writes the style sheet (open question: inked outlines vs the Glassblower's
  clear glass) and Paul reads it; one reference pet first; Codex draws the rest three at a time,
  each with its description, the style sheet, the reference pet and its do-not-resemble list; the
  Lamp reviews every image against its charter; a provenance note beside each sheet.
