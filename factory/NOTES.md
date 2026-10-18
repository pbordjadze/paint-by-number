# The vibe factory and the making-of animation: notes

The architecture is `ARCHITECTURE.md`, the engine contract `SPEC.md`, the panel `GUARDIANS.md`.

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
- The panel Paul picked and the jury of six: `GUARDIANS.md`.

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

- She is an equal seat on the panel.
- The panel (Paul's picks): Medea, the Baba Yaga, the Hedge Witch, the Moon, the Snow Queen (in
  place of Elsa), the Robber Girl (from the 1957 Snow Queen, as
  Paul remembers her: a Georgian girl), the Storybook, the Enchanted Workshop, the Scholar, the Painter, the Child at
  Bedtime, the Glassblower, Pirosmani, Emily Dickinson, the Open Source Enthusiast, the Nutcracker, Balanchine,
  Bulat Okudzhava, the Bible School Teacher (maybe). Paul
  singled out the Scholar.
- 19 guardians on every decision would cost 19 agents a round, and everyone would wait many
  pieces to be represented; a jury of six drawn by the ledger keeps rounds small and fair.
- More guardians don't cost more per round (the jury stays six); each one sits less often and
  the design gets pulled more ways. Overlaps: the Nutcracker and the Enchanted Workshop (things
  come alive), Balanchine and the Nutcracker. Prune after calibration shows which views help.
- Paul: one day Caroline may run the panel, its charters and their weights; seats and base
  weights are data for that (`panel.json`, `ARCHITECTURE.md`).
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

## Paul's point 6: the Lamp, and Paul's veto

- The first taste run named the panel "A Lamp Left Burning". Claude preferred The Round Dance and
  Paul agreed, but he let the panel keep its own name: "the Lamp" for short. Every other decision
  is subject to his veto.
- Pets go through the Lamp before Codex builds them (`pieces/pets/brief.md`).

## Paul's point 7: the Lamp's story

- The app's Lamp section (issue #16) shows the members and the story of their work, in
  chapters. Chapter 1 is "How the Panel Named Itself".
- Chapter 2 is **Thirty-Six Colors** (Paul's pick over Claude's suggestion, an App Store subtitle):
  the Lamp renames 36 paints, two per guardian, so everyone gets colors; vetoes make good content.
  Paul's checkpoint: `pieces/color-names/run/checkpoint.json`.
- Chapter 3 is **The Marginarium**: the story of the day the Lamp was made (11 October), told by
  Claude in a wry, footnoted voice with a little of the Bartimaeus books' flavor, the Lamp writing
  in the margins. Its purpose: show Paul's ideas and what each became.

## Paul's point 8: the Marginarium

- Paul asked the Lamp whether it liked the word Marginarium (`pieces/marginarium/`). It did, for the
  margins of each decision, and vetoed it as its own name.
- Paul's decision: **the Marginarium is the app's storybook section** (issue #16): "It's a coloring
  book app, with a marginarium of stories!" The Lamp's members, its chapters and the palette
  gallery live there; the margins of each decision (vetoes, runners-up, jurors' notes) are its
  natural content. The Snow Queen's caution stands: show the margins sparingly.

## Paul's point 9: a Mac for the homelab

- Paul bought a used M1 MacBook Air ($40 + $9.81 shipping, 2026-10-11). It is the first machine in
  the project that can build and run the app, so the Lamp can play it (chapter 4:
  https://claude.ai/code/artifact/a087b22e-d1f9-4ef7-b447-2a87fd347b66).
- On arrival: Activation Lock off and no device-management profile, before anything else.
- Then Xcode 26.6 (CI's version) with the iOS 26 simulator, Claude Code, and
  `claude remote-control` in the repository folder, so a session runs on the Mac.
- The Lamp's first wishes and worries are in `pieces/chapter-4/wishes/`. Their worries are the
  harness's requirements: name areas by number, wait for the screen to settle, drag in many small
  steps, read pixel values as well as pictures.

## Paul's point 10: the book's order, and how chapters start (Oct 11, afternoon)

- **The Marginarium is chapter 1.** Paul: "make chapter 3 be chapter 1, the stuff before that can
  be appendices." Put to the Lamp (`pieces/renumber/`) with Paul's rule: it happens unless the
  Lamp objects strongly and unanimously. Order: 1 The Marginarium, 2 The Lamp Picks Up a Brush,
  3 The Lamp's Constitution, 4 A Pet for Every Guardian, 5 Two More Pets; Appendix A How the
  Panel Named Itself, Appendix B Thirty-Six Colors. Renumbered chapters say so in a short note.
- **How new chapters start:** when Paul has an idea for a chapter, he says what it should focus
  on. A note like this one may become part of a chapter someday, not necessarily an existing one;
  everything is logged so it can.
- Also asked today, for the next chapter: the docs cute and funny (the Lamp can help later); a
  recruiter should be able to picture their own stakeholders, or agents those stakeholders set
  up, as the Lamp; the pattern could scale with funding, and runs today on Paul's own credits.

## Paul's point 11: people first; the Lamp for smaller problems (Oct 11)

- "Human creative choice should always trump AI, if desired." Paul wants his family and the
  people close to him more involved, and that often means leaving the Lamp out entirely.
- The Lamp is saved for smaller design problems, or runs under more oversight; its answers are
  proposals. Big creative choices go to Paul first, who decides who weighs in.
- `CONSTITUTION.md` (Who really decides) and `ORCHESTRATOR.md` (Rules) say so. People Paul brings
  in are not named in project files until he says so.

## Paul's point 12: Codex runs the Lamp; all the pets now (Oct 11, evening)

- Codex plays every seat of the Lamp for the pets, and the whole set is hatched now. Paul's
  approval steps in the pets plan are waived for this run: the pets are whatever the Codex Lamp
  decides and generates. Paul can still veto later.
- It saves Claude usage, and it is an experiment: how a guardian's judgement and taste change with
  the model underneath. The same charters and prompts go to two Codex models, and three pieces the
  Claude-run Lamp already answered are re-posed to both, side by side.
- A whole chapter is Codex's: Codex may write it, with Claude as a character, and it can include
  the pets.
- The driver is F36. Claude launches it outside Codex's sandbox: each seat is its own read-only
  `codex exec`, each pet a normal Codex session. (Giving a Codex session network access and write
  access to Codex's own folder, so it could launch the seats itself, was blocked as unsafe.)

## Paul's point 13: a Marginarium that feels alive (Oct 12)

Paul's vision, not to build yet:
- The Marginarium lists every member of the Lamp, each with its pet (issue #16's members page:
  name, belief, pet).
- In a chapter, where a guardian says something, its pet appears beside the words.
- Sometimes a pet just wanders through, so the book feels inhabited.
- New animations for the pets we have (good walks first), so they can move around the screen.
- The pets' art is credited in the app as drawn by Codex with an OpenAI image model (Paul
  approved; OpenAI's Terms of Use give the output to its user and forbid presenting it as
  human-made).

## Paul's point 14: no Georgian thread (Oct 12)

- The guardians no longer each carry a Georgian thread: it was too much. It was removed quietly
  from the chapters (no new chapter about it), and from the charters and the taste code going
  forward. Records of past runs stay as they were.
- No guards either: Georgia is not codified anywhere (no place-name or Georgian-word caps, no
  Georgian glossary). It is already enshrined by the choice of the guardians: some are
  explicitly Georgian (the Robber Girl and Medea especially), others close to it.

## Paul's point 15: chapter sign-off (Oct 12)

Paul reviewed the chapters and signed off with these changes, all made in the docs:
- The app is "the app" in the chapters, not Medea (the name isn't settled); Medea is the guardian.
- Guardians named after real artists go by first name, with who they are after in the members
  table: Emily, Niko, George, Bulat. Paul's own quoted words keep the full names.
- Cut: the "Sorry" quote and its margin note; the praise of Paul (the "What Paul brought" paragraph,
  the chart of his idea to frame, flattering lines); the Mac-lock step. The ideas table stays as
  plain facts ("Ideas from the night").
- Chapter 3 gained a dated people-first note; Appendix A lost its stale next steps; "Nina" is the
  Robber Girl; footnote markers without footnotes are gone; a narrator's confession explains The
  Round Dance (Claude's pick) versus The Round Table (what Paul read).
- Next: Codex adds the pets to the chapters (in the app's chapter format), then they ship.

## Paul's point 16: the Marginarium waits for the pets (Oct 12)

- Hold the Marginarium's chapters and margin notes completely until the guardians' pets exist.
  Chapter 1 in full (F39, with its fix: tables, margin notes with speakers, a page-sized sheet on
  iPad) stays parked on `claude/f39-chapter1-in-app`; nothing of it ships before the pets.
- Codex hit its usage limit on October 12 ("try again at Oct 18th, 2026 4:12 AM"), on every model.
  The pets run stopped in step 6 with 2 of 20 pets validated (Originality, the Snow Queen). Its state
  is saved on branch `factory-state/pets-run` (records and final sheets; how to restore is in its
  README). When Codex is back: restore if needed, resume the run, give each failed pet one fresh
  attempt, then put each guardian's pet beside its margin notes in chapter 1.

## Paul's point 17: Pip's face, and Codex on pets (Oct 12)

- Word from Chief Designer Caroline, relayed by Paul: "Pip can have its face back. It was unkind
  to take away Pip's face." Codex designs the face; the blue dot under the lid stays if Codex
  wants it (F40). Her word can be part of Codex's chapter on the pets.
- Codex's usage came back early (Oct 12). From now on Codex works on the pets and their chapter;
  app work goes to Claude's helpers.
- The pets run resumes once its driver retries the hatches the usage limit stopped before they
  drew anything, and gives each pet that failed a gate one fresh attempt (F41). The pets' failures
  are Codex's to solve.

## The pets are made (Oct 12)

- The Codex Lamp run finished: eighteen of twenty pets validated and published in `factory/pets/`
  (sixteen through the Lamp; Baba Yaga and the Glassblower on Codex's own maker's call,
  `factory/pieces/pets/codex-lamp/makers-call.md`). The Hedge Witch was rejected by the maker
  jury; Moon is withheld. Pip has its face (F40).
- Codex wrote its chapter, "The Pets We Actually Made" (`factory/pieces/pets/chapter/`, sources
  in `sources.md`). Its Hedge Witch paragraph predates the maker jury's rejection (it says the
  package was over the size limit); Codex updates it when its usage returns (Oct 19, F45).
- Codex hit its usage limit again on Oct 12 ("try again at Oct 19th, 2026 4:20 AM").

## Paul's point 18: get it all out, the Hedge Witch included (Oct 12)

- Paul: "finish it all up, getting all of it out there, including that last pet." The four
  refinements shipped (main 010337a). The Hedge Witch's drawing is included on his word
  over the maker jury's redo (`pieces/pets/owners-call.md`): nineteen pets; Moon stays withheld.
- Codex's chapter carries a short note from Claude about the Hedge Witch's last steps until Codex
  rewrites that part itself (Oct 19).
- Shipped Oct 12 (main 42bb76c, build 1.0.325): chapter 1 (F39) with each guardian's pet beside
  its margin notes, Codex's chapter as chapter 6, the nineteen pets bundled, Pip's new face. Then
  the README's front door (main b4776e3).
- Paul: the Marginarium is hidden by default; Settings › The Marginarium shows the book in the
  gallery's toolbar (`SettingsKey.showsMarginarium`).

## Paul's point 19: the Marginarium for everyone, Dinotopia, teams (Oct 12)

- Chief Architect Paul, set in stone: the Marginarium must be understandable and approachable to
  anyone; any member of the Lamp should be able to open it, have a nice time and roughly follow
  it (`GUARDIANS.md` › The Marginarium is for everyone, `App/CLAUDE.md`).
- Margin notes go genuinely in the margin: a column beside the story on iPad, inline on iPhone
  ("the story just isn't really readable without that"). Branch `claude/lamp-teams`.
- A gallery of every character and their brief: Who's Who in the app, with the people, the AI
  helpers and the guardians by team; an egg for each pet not yet hatched (Dinotopia, the Moon).
- Chief Designer Caroline is present, and her ideas are attributed to her, not to Paul.
- Dinotopia joins the Lamp to guard the storybook feel, with the Storybook ("one of the greatest,
  most magical things I've ever touched"; it should really steer the direction).
- What a guardian guards is a metaphor (`GUARDIANS.md` › Guarding by metaphor; each charter's
  **treasure**).
- Teams, because no guardian with a pet can leave: Paul paired Dinotopia with the Storybook and
  the Painter with Niko; Claude proposed the rest (`GUARDIANS.md` › Teams, `panel.json` teams,
  `loop.team_seats`). The Bible School Teacher, whose pet shipped, is seated on the Hearth.
- Later: a gentle, kind way to give some guardians more power and some less, which stays cute
  even when the Snow Queen is unhappy about it (`GUARDIANS.md` › Wicks, a proposal).
- For Oct 19 if Paul agrees: the Moon's redraw. Dino's pet came from Paul instead (point 23).

## Paul's point 20: the four-year-old in the design loop (Oct 12)

- A product vision, in Paul's words on main in `docs/ideas.md` (Paul's ideas): a fully automated
  game with a four-year-old making every design decision, every agent and human choice documented.
  Not in the Marginarium yet. Its last paragraph is a deliberate Easter egg behind a "But."
  disclosure, for whoever reads that far.
- Addendum: people will like the human creative touch, and value knowing who or what is
  responsible for which choices, and where a human's vision was.

## Paul's point 21: where the humans go (Oct 12)

- In `docs/ideas.md` on main (Where the humans go), his words verbatim in a fold: be deliberate
  about where people go in a system of agents, and treat people and agents with the same dignity
  and respect. No implementation work yet.
- When Paul and Caroline join the Marginarium's cast: near-equals of the Lamp and the helpers, in
  time full equals, in high roles, and drawn as people rather than cartoon creatures (their own
  look beside the pets, still allowed to be a little cute).

## Paul's point 22: made together (Oct 12)

- Long before the Marginarium, many of Paul's design choices were informed by Caroline's
  feedback; he has been doing the big-picture thinking. Her Who's Who card says they have made
  the app together from the start, without the Pip's-face story (that stays in Chapter 6). Who
  contributed what may be traced one day; this is the general shape.
- Caroline is probably the Marginarium's first reader: it should flatter her, and she has earned
  it.

## Paul's point 23: Dino hatches (Oct 12)

- Dinotopia is called Dino, like Niko and Emily: "After James Gurney's Dinotopia books." stays
  under the name; the id stays `dinotopia`.
- Its pet is Paul's own Dino, a teal long-necked dinosaur he made in the Codex app before Dino
  joined the Lamp. His sheet passed the v2 contract as it was; `factory/pets/dinotopia/` keeps it
  lossless with its provenance, and the app ships it on `claude/dino-hatches`. It wasn't drawn in
  the Warm Oilcloth family style, and Paul chose it anyway: his pet, his call.

## Paul's point 24: Bart joins (Oct 12)

- Paul liked the narrator's djinni joke in chapter 1: "let's add Bart to the Lamp, with obvious
  parameters and vision, and let him comment on that section please. Give him enough context to
  understand what's going on."
- Bart (`bartimaeus`) is after Bartimaeus, the djinni who narrates Jonathan Stroud's books, and
  guards the footnote, on the Storytellers with Dino and the Storybook. Claude drafted his charter;
  run as a low-effort Opus with the whole opening section, the Lamp and the Marginarium explained,
  he changed two lines ("the helper whose work is named"; "borrowing a famous voice instead of
  finding one's own") and wrote three notes; Originality passed them, with cautions now in his
  charter.
- Paul on the first printing: "Those were cringe and not sarcastic enough I think." Claude's
  draft had made him sweet ("wit with a warm heart", "it is kind"). Told so, Bart took the
  sweetness out of three charter lines and wrote five sarcastic notes aimed at the narrator; Paul's
  verdict and the rules went to him word for word. Chapter 1 prints his first, on "I should
  introduce myself": "Somebody is now. I'm Bart, named after the djinni whose voice this narrator
  has borrowed, and I'd like it back when he's done." Beside the narrator's djinni joke, his
  third: "Handy. That way it can't remember whose voice it's wearing either." Originality passed
  both, and its own remark is no longer printed. The runners-up: "A text box. Summoning has really
  gone downhill, and judging by the narrator, so have the things that answer it." (on "only a
  text box"); "Quieter, it says, in a chapter where it does all the talking. I've heard modesty,
  and this isn't it." (on "Where I helped, I say that too, but quieter."); "Nor was I. Paul read
  one joke, decided he wanted its author on the panel, and here I am, the panel's least consulted
  member." (on "I was not asked whether I minded.").
- His drawing, in his words: a little ink asterisk with six stubby arms and two dot feet,
  stamped in brown ink, who hops down beside the note and waves the reader back up. Drawn so on
  Oct 18, then redrawn at Paul's word as a crimson ink-smoke djinn keeping a nod to the asterisk
  (see Oct 18 below); one name per guardian, so the drawing is simply Bart.

## Paul's point 25: Sun and Moon, the Astrologer, Madeleine, the Lamplit Table (Oct 17)

- Different music by day and by night, switching by the painter's own time of day, with "a very
  very gentle note of astrology there, like a subtle nod ... Think midsummer nights dream—but
  with an edgy astrological vibe." Built as Settings › Sky (F48, `pieces/day-and-night`).
- A new guardian, the Astrologer, to oversee it. Madeleine (after Madeleine L'Engle) joins the
  Bible School Teacher on the Hearth: "one very gentle guardian of wholesomeness—but a super
  chill one. Like a pagan Narnia. Madeline Lengle, who should now be the Bible school teacher."
  Claude first read it as a replacement and gave the Bible School Teacher a Former Guardians page;
  Paul, the same day: "Bible school teacher isn't supposed to go away, she was being merged with
  Madeline Lengle." They are one guardian, Madeleine, the Bible School Teacher, with the Bible
  School Teacher's drawing, id and seat and both charters joined, and the October 12 rule (no
  drawn guardian leaves) stands.
- "Use this specific lamp to run and oversee all future UI features, starting with all the ones
  that haven't shipped yet": the Lamplit Table (`GUARDIANS.md`), six seats, named by its members.
  Root `CLAUDE.md` › App rules carries the rule on `main`, so every session sees it.

## Paul's point 26: Caroline's first guardians, Hope and Eno (Oct 18)

- Paul, for Caroline: "more moonlight, dark purple, astrology, 90s whimsigoth, get Hope Sandoval
  on the panel", then "ADD HER AS A GUARDIAN WHY NOT"; and "Brian Eno's first albums, so from
  Here Come the Warm Jets up to Before and After Science. Go ahead with his creation, even the
  pets. He and Hope Sandoval are Caroline's two first guardians".
- One name each, Paul's yes: Hope (`hope`) with the Moonlit Circle, Eno (`eno`) with the
  Workshop. Claude drafted both charters. No Lamplit Table seats: "Lamplit table needs reworking
  eventually, we need a select set of guardians for various new features almost."
- Both are eggs. Hope's drawing (a dark-violet moonflower, a dewdrop holding one star, soft and
  hazy) went to Codex as briefed; Eno proposes his own, in his words with a reason for each part,
  because Paul asked how he came up with it.

## Open questions

- Dino in the Lamp's family style? Paul (Oct 12): leave him as he is for now, he's Dino;
  discuss a restyle with the Lamp later.
- How long the show is, and which scenes later paintings get.
- New brand colors from the agents: a separate track, needs Paul's approval.
- Where the engine builds: `tools/swift.sh` needs Docker, which this cloud container lacks; the
  Swift 6.2 toolchain for Ubuntu 24.04 downloads from swift.org here, and the homelab can use
  either.
- Commits on this branch carry `[skip ci]`: CI runs the whole macOS matrix on every push, and
  nothing here needs it yet.

## Oct 18: four guardians hatch, Dino redrawn (backlog row 42)

- Paul: "We have a weeks worth of Codex usage … make some new pets, and maybe make a re-theming of
  Dino … a bit more frugally than last time … let me see them/sign off on them". Made on the
  homelab with the create-pet skill, one Codex model at low effort, one pet at a time: a draft
  (still + idle) per egg on a tailnet page, full sheets only for Paul's picks, each sheet built from
  the still he approved. 99 image generations for the five shipped sheets, the drafts and one
  retired sheet; about 3% of the week's Codex usage.
- Shipped (app branch claude/pets-oct18): the Astrologer, Bart, Rikyū, Scherenschnitt, and Dino in
  the family's paint (his own design kept; Paul and Caroline picked it: "not scheming enough, like
  design I"). Sheets in `pets/<id>/`. The Moon stays withheld until Paul says otherwise.
- Known flaws, all in rows the reader doesn't play (it plays idle and the tap wave): a few of the
  sixteen look directions read wrong (Rikyū 270°; Scherenschnitt 180–225°) or are mirrors (Bart);
  some jump poses are drawn smaller. Bart's see-through smoke tail came out mostly opaque.
- Paul on why these looked better: short concrete prompts per pet, his approved still as every
  row's master, style shown as pictures rather than enforced rules. A redraw trial of three
  earlier guardians followed.
