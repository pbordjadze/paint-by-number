# The lens, codified

Version 3 of the guardian lineages, after Paul's notes on versions 1 and 2 (October 23): Eno's
version 2 "looks incredible"; Dino's "started to look a bit like AI slop ... the shape doesn't
need to stay THAT exact"; "The moon can just be the moon, it doesn't even need to stay a
crescent, and it can lose the SHAPE of the lamp completely"; Scherenschnitt: "her original shape
is so clearly Reiniger, her new ones shouldn't be"; "More abstract again".

Paul, on reading this: "I just don't want the rule to be too strict, when you're trying to get
LLMs to do creative work it's important to be a little hands off—make sure these sessions feel
free to like, suggest or even try something if it breaks a rule". So everything below is a
default and a way of looking, not a law.

## The rule

**Carry the guardian's idea back, not its picture.** Three jumps back along a sourced line of
influence (`README.md`). At each step ask: *how would this tradition, with its own tools,
conventions and knowledge, make this guardian's subject?* Never: how would it copy today's
drawing.

Each guardian gets a card with three parts:

1. **Essence** (always kept): what the guardian is, in a phrase taken from its charter and
   subject, and how many: a guardian who is one figure stays one (Dino's 1830 plate first came
   out as a herd). The Moon: the moon itself, the one light in the dark. Dino: a long-necked sea
   creature, wonder painted from careful looking.
2. **Rhymes** (optional): at most one or two motifs that may echo from step to step, and only
   where that tradition has its own native form for them. Free in shape, scale, number and pose.
   Eno's two unequal rounds rhyme because rondels, chance fields and initial O's are already
   round. If a tradition has no native form for a rhyme, drop the rhyme there.
3. **Leave behind** (by default): whatever belongs to today's drawing rather than to the idea.
   - Its objects (tape reels, a lantern).
   - Its outline, above all when that outline is itself someone's style (a Reiniger cut bird).
   - Its composition, when that composition is a period convention (the almanac's crescent with a
     face).
   - Its palette, its rendering and its character acting (a sly eye).

## The tests (what to look for, not gates)

1. **Native.** A curator of that period would see an ordinary, well-made object of their own
   tradition: its real medium, conventions and level of knowledge. No tricks: no shape hidden in
   a landscape, no outline filled with a pattern, no double exposure, no object out of its time.
2. **Lineage.** Someone who knows the guardian, with the plate's liner notes, says "that's the
   same thing". The likeness can come from the subject and the trail; it needn't come from an
   outline.
3. **Signature.** If today's drawing is in a named artist's manner, no earlier step looks like
   that artist.

## Room to break it

- A session or a Codex run that sees a better idea than the rule allows should **try it**, not
  just mention it: one extra plate per guardian that breaks a rule on purpose, saved beside the
  others (`step-<N>-wild.png`) with one line saying which rule it breaks and why. It goes on the
  page next to the plate it answers, labelled as a wildcard, for Paul to judge.
- Vary the wildcards. Paul, on the first four: "they all kinda broke the rule in the same way and
  I'd prefer if they didn't". All four went to the real material, today. So a batch gives each
  run a different suggested break from the menu in `wildcards.json` (sideways, forward, a scene,
  an absence, a hybrid, what it inspired, scale, a new subject, the inside, a copy) and names the
  moves earlier wildcards already made. A suggestion, not an order: a run that sees a better
  break takes it.
- Suggestions about the rule itself are welcome too (a better test, a card that's wrong, a lineage
  that should run another way); write them in the run's notes and on the page.
- A redo is for a plate that has lost its idea or its craft, not for one that broke a rule in an
  interesting way. When in doubt, keep both and let Paul choose.
- The cards are a starting point. If a step finds a better essence or rhyme for a guardian, say
  so.

## How it runs

- For the jumps, Codex sees no image at all, only the card and the step (`cards` and `steps` in
  `lineages-v3.json`, assembled by `run_v3.py`). An attached drawing leaks its colours and pose
  (version 1); an attached silhouette forces tricks (version 2). Plate 0 still shows today's
  guardian with its approved drawing.
- Each step names the tradition's real medium and what it natively made (from the sources). The
  card says what to keep; the rule decides the rest.
- One Codex run per guardian (its jumps plus at most one wildcard), and at most one redo per image.
