# Piece: the pets

One pet per member of the Lamp (the 18 seated guardians, Originality, and the Bible School
Teacher while she waits for a seat): 20 animated companions hatched in the Codex desktop app. They
are the jurors' faces on review pages and the collection page, and maybe one day in the app (issue
#16, after the Originality and Open Source guardians have checked OpenAI's terms). Each starts from
the one-line seed already on the collection page (Medea's golden ram, Pirosmani's giraffe,
Okudzhava's trolleybus, …).

## Who decides what

| Decision | Decided by | Why there |
| --- | --- | --- |
| The set's style sheet: medium, line, palette, proportions, scale, ground, how the four states read, the set's boundaries | The Lamp, then Paul | It is what makes 20 pets one family, and it costs only text to judge |
| Each pet's brief (appearance, personality, physical expression, emotional range, signature behaviors, boundaries; 150–300 words) | Its own guardian drafts; a jury checks the set; Paul | Character is taste, and the guardian knows its idea best |
| Turning a brief into a pet, within the style sheet | Codex | Generation and execution: a coordinator keeps the set consistent, one agent per pet, at most three image workers at once |
| Technical choices the style sheet leaves open (resolution, frames, export) | Codex | Craft, not taste |
| Whether a hatched pet is done | The Lamp's image review, then Paul | The judge is never the maker |

Codex never changes a pet's creature, personality, boundaries or the style sheet. When a brief
doesn't work as an image, it says so and proposes; the Lamp decides.

## The run

1. **Research first:** what `/hatch` takes and makes (formats, the four states, export, limits,
   terms). The style sheet's technical lines depend on it.
2. **Style sheet** (one or two rounds): four proposers each write a style sheet; a jury of six
   picks one. Paul approves or vetoes.
3. **Briefs:** each guardian expands its own seed into a brief within the style sheet.
4. **Set review:** one jury of six reads all 20 briefs side by side and only flags (inconsistent
   with the style sheet, breaks a boundary, recalls a franchise, a real person's likeness). A
   flagged brief goes back to its guardian once. Paul approves the set.
5. **Hatch:** Codex, coordinator plus one agent per pet, three at a time. It returns the files
   (`factory/pets/<id>.*`), a contact sheet of every pet in every state, and a log of what each
   pet was made from.
6. **Image review:** a jury of six looks at the contact sheet and says keep, or redo with one
   line why. Codex redoes; Paul has the last word.

Before the run, apply the first run's fixes (`How the Panel Named Itself`): agents answer in
their reply instead of writing files (about a third of the tokens), the shared brief stays plain,
a veto must quote the charter line it breaks, Originality gets a glossary, and one seat guards
function. For pets, function means the pet reads at its real size and in all four states.

Rough cost: about 50 Haiku agents in all. With replies instead of files, that's about 1.2 million
Haiku tokens.
