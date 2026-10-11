# The vibe factory and the making-of animation: notes

The engine contract is `SPEC.md`; the guardians and their charters are `GUARDIANS.md`.

## Decided so far

- The show plays when the painter taps Start, over each stage's recorded picture: the pipeline reruns
  once with an observer, so the template stays byte for byte the same. Tap to skip; replay from More.
- One scene per credited method (`ACKNOWLEDGEMENTS.md` › Methods), choreographed to show what the
  method really does. Citation card: New York italic, authors and year first, about 0.5 s + 0.2 s per
  word, at least 2 s. Reduce Motion: cards only, cross-faded.
- Figures: a procedural stick-figure rig with a handmade finish (lines redrawn as they shimmer,
  tapered ink, poses held on twos).
- Factory: a JSON spec (about 25 numbers) → a deterministic Swift rig (spec + time → ink strokes) →
  frames drawn by resvg, clips by ffmpeg. The same rig ships in the app (Metal or CoreGraphics draws
  the strokes).
- Judges see a contact sheet, a motion-trail image, and the figure at app size over a painting, in
  light and dark. Code checks the measurable things first (sliding feet, joints bending the wrong
  way, lines too thin, contrast).
- The agents proposing changes vary; the judges don't. Judging is blind A versus B, in both orders;
  every JSON and verdict is logged.
- Paul's checkpoint every ~3 rounds → `STYLE.md` + a gallery of approved examples the judges must
  match.
- Agents edit only the JSON; a new field is an engineering request.
- First scope: one figure, a walk + one spell gesture + the citation card, ~4 s, on a test scene we
  draw ourselves and run through pbn.
- Baba Yaga starting ideas: mortar and pestle = grinding pigment (the palette), the broom that
  sweeps her tracks away (the texture sweep), the hut on chicken legs, the kerchief, Bilibin,
  Khokhloma (black, red, gold), birch, moss, rowan. Avoid wands, starry hats, owls, lightning bolts,
  robes and house colors.
- First step, no agents: the format, the rig, the scene and one figure tuned by hand.

## Paul's point 1 (architecture): the loop is a reusable way to design things

Paul's framing: isolate the one problem (mock everything else), make the parameters that aren't
settled easy to change, give a model whose taste you trust tools to review the output cheaply, let
one reviewer per distinct persona or vibe judge it, and iterate toward their consensus. Write it
down; reuse it if it works.

Claude's adjustments:
- Consensus means "nobody objects strongly", not the average of everyone's favorites, which
  drifts toward design by committee. Give each persona one axis and a veto on it; one fixed judge
  ranks what survives, and Paul picks.
- Personas should be separate axes (brand fit, legibility, motion craft, charm, restraint), not
  overlapping vibes.
- It fits when the thing can be isolated with realistic stand-in context, can be rendered into
  something a model can perceive, has few parameters that say a lot, and is cheaper to judge than
  to make. It fits poorly for feel on a device, sound and haptics, and anything that only shows
  once the pieces are put together.
- Write it down now; turn it into a repo skill plus a saved workflow only after it has produced
  one result Paul likes.
- Lineage: interactive evolution, where a person picks among variants of a design described by
  parameters (Sims, "Artificial Evolution for Computer Graphics", 1991; Picbreeder, 2008), and
  Marks et al., "Design Galleries" (1997), which set animation parameters by browsing a gallery.
  Its known limit is the person tiring of choosing every generation. Model critics stand in for
  most of those choices; Paul keeps the checkpoints. Panels of model judges: Verga et al.,
  "Replacing Judges with Juries" (2024).

## Paul's point 2 (design): taste vectors, one agent each

Paul listed: storybook; the spell that brings objects to life (Disney's dishes); Baba Yaga (his
lean); cute, green witchy; a little Elsa; not Harry Potter (an explicit avoid); central to the brand
(current tokens, open to new colors); citations that linger just long enough for a quick reader;
the simplicity of a stick figure.

Claude added: motion craft; legibility at app size; moonlight (the app's own name: magic done at
night, as in the elves and the shoemaker); originality beyond Harry Potter (Disney, Frozen);
warmth and respect (a friendly witch, not the fearsome folklore one, and no hook-nosed crone);
restraint and rewatchability (it plays on every painting); truth to the method (later scenes).

Proposed casting (first scope, 8 agents + 1 ranker per round):
- Proposers (the moods, for variety): Baba Yaga folk tale; green hedge witch; moonlight and frost
  (the bit of Elsa); enchanted workshop (the tools come alive). Every brief carries the avoid
  list.
- Critics (the axes, one veto each): motion craft; legibility at size; brand and moonlight;
  originality; warmth and respect. Restraint joins once a full show exists; truth to the method
  once there are scenes.
- One fixed ranker orders what no critic vetoed; Paul picks at checkpoints.

## Paul's point 3: a cheap tier (Jev) to run the loop at volume

- A tiered cascade: a cheap model prunes many candidates → Opus judges the few → Paul picks. The
  cheap tier only removes obvious losers, never picks winners.
- Jev (TypeSafe AI): built for fast structured decisions (classification, routing). Early access,
  self-reported benchmarks; one independent test put it at ~90% accuracy against frontier models'
  95–97%. Image input unknown: if it's text-only, it can sort critiques into vetoes and parameter
  edits but can't judge a picture.
- Guards: (1) calibration: every judge (Jev, Haiku 5.5, the Opus critics) is scored on pairs
  Paul has already judged, and gets the authority its agreement with him earns; (2) Opus's named
  edits guide the search, rather than random sampling, so spamming doesn't just find the cheap
  judge's blind spots.
- Haiku 5.5 is a cheap tier available now (a subagent that sees images, no integration needed);
  test Jev against it on the same pairs.
- Across the app: the brand's custom moments (animations, sparkles, icon, illustrations, the
  citation card), not the native screens (system controls stay system controls, and they only
  render on CI).
- Integration needs: Jev's API key in the environment settings, and its host allowed by the
  network policy.
- Order: prove the loop with Opus → calibration pairs from the first checkpoint → test the cheap
  tiers → then run at volume.

## Paul's point 4: a week of OpenAI Codex usage

- OpenAI's cheap, fast tier is its nano/mini models (some listed as taking images). Those are the
  API, billed per token; a ChatGPT plan's Codex usage runs the Codex agent on larger models, so
  it isn't a Jev.
- Best use of the week: one critic from a second model family, whose blind spots differ from
  Opus's. Calibrate it against Paul's picks like every other judge.
- Run through `codex exec` (non-interactive) here: needs installing and signing in from this
  container. Image input in `exec` is unconfirmed; check first.
- The week is a deadline: reach Paul's first checkpoint inside it.

## Decided: Haiku 5.5 is the cheap tier

- It runs as subagents in this session, sees images, and needs no key or integration. Jev and
  Codex are parked.
- Each factory layer joins on probation, one at a time, and stays only if it measurably helps:
  the judges agree with Paul's picks more often, or he reaches a pick he likes in fewer rounds.
  His checkpoint picks are the yardstick for every layer, not just for the judges.

## Paul's point 5: a panel of guardians redesigns the app's brand

- Haiku makes and surfaces options in bulk; a low-effort Opus panel decides. Paul hand-picks the
  panel: each Opus guards one vibe or idea, and whatever the panel decides must represent each
  guardian's idea fairly.
- Scope: everything designable, piece by piece: the stick figure (ink only) → the palette (tested
  on the figure, the canvas and the icon) → the logo and icon → the rest (sparkles, the finish,
  the citation card, empty states).
- Fixed unless Paul says otherwise: the name Paint by Moonlight, native system controls,
  accessibility (contrast, Dynamic Type, dark mode, Reduce Motion), localization. The current
  design rules (gold only for sparkles and the crescent, New York titles) are open; an approved
  change updates the design system, `Theme` and the CLAUDE.md rules.
- Decision rule:
  1. Haiku makes options; code drops the broken ones.
  2. Each guardian sees the shortlist blind and says, for each option: where its idea lives in it
     (or that it doesn't), whether it betrays its idea (a veto, with a reason), and its ranking.
  3. The winner is the best combined ranking among options nobody vetoed, with extra weight for
     guardians the ledger shows are underrepresented so far.
  4. Ledger: for each piece, each guardian's one line on where it lives in the winner. Fairness
     is judged across the whole app, so no single piece has to carry every vibe.
  5. Paul approves at checkpoints, with the ledger in front of him.
- The guardians are asked "where is your idea in this?", not "is this good?", because the first is
  where they differ.
- Craft and originality are veto-only seats (code checks where possible), never outvoted on taste.
- Guardian charter: name; what it believes; what it champions; what it guards against;
  touchstones; how it recognizes its idea in a design.
- The panel Paul picked, its shared Georgian bar and the jury of six: `GUARDIANS.md`.

## Budget and where it runs (Oct 11)

- Claude weekly usage: 74% used, resets Tue 6:59 PM; usage credits on, balance 0, so work stops at
  the limit. This session and every subagent draw on that one allowance, wherever Claude Code
  runs.
- A taste round (≈4 Haiku + 6 low-effort Opus) is small; building the engine is the large cost.
  Read the meter before and after the first round to learn what a round really costs.
- Split: Codex (its own allowance) builds the deterministic engine on Paul's homelab against a spec
  Claude writes; Claude's allowance goes to the spec, review and taste. The homelab also persists
  (this container doesn't), and with a Mac it could run the simulator locally instead of CI.
- Guardians on two model families: later, as a layer on probation. Varying the model and the vibe
  at once makes it impossible to tell which caused a disagreement.

## Medea: the app's name and its design North Star

Paul: she's witchy, Georgian (Colchis), all about aesthetics, cool, from mythology, kind,
helpful, beautiful.

- She is an equal seat on the panel. Georgia is the North Star instead, a bar every guardian
  carries: if you know Georgia, the app reminds you of it; nobody else should notice it's
  Georgian.
- The panel (Paul's picks): Medea, the Baba Yaga, the Hedge Witch, the Moon, the Snow Queen (in
  place of Elsa), the Robber Girl (to confirm: the Georgian girl Paul remembers from the 1957
  Snow Queen), the Storybook, the Enchanted Workshop, the Scholar, the Painter, the Child at
  Bedtime, the Glassblower, Pirosmani, Emily Dickinson, the Open Source Enthusiast, the Bible School Teacher
  (maybe). Paul
  singled out the Scholar.
- 16 guardians on every decision would cost 16 agents a round, and everyone would wait many
  pieces to be represented; a jury of six drawn by the ledger keeps rounds small and fair.
- The animation stays stick figures for now: converge, see whether the factory works, then
  revisit.

- Before the rename ships: a trademark search in the app's classes (software, games) and the App
  Store's name availability. Tyler Perry's Madea sounds nearly the same; include it in the
  search.
- Many people know Medea first from Euripides' play, in which she kills her children. Her charter
  says which Medea this is: Ovid's (Metamorphoses, Book 7), who gathers herbs by moonlight and
  makes the old young again.
- The rename touches the display name, gallery title, permission texts, PDF footer, string
  catalogs, the design system, the icon and the identity rules in CLAUDE.md. Nothing changes
  until the name clears.

## Open questions

- How long the show is, and which scenes later paintings get.
- New brand colors from the agents: a separate track, needs Paul's approval.
- Where the engine builds: `tools/swift.sh` needs Docker, which this cloud container lacks; the
  Swift 6.2 toolchain for Ubuntu 24.04 downloads from swift.org here, and the homelab can use
  either.
- Commits on this branch carry `[skip ci]`: CI runs the whole macOS matrix on every push, and
  nothing here needs it yet.
