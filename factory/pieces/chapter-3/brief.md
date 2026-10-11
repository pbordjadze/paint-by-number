# Chapter 3: the brief every guardian reads

## What chapter 3 is

Medea is an iPhone and iPad app that turns a photo into a paint-by-numbers painting (today it is called
Paint by Moonlight; Medea is the name it will take). Paul Bordjadze makes it. On one day, 11 October
2026, from before dawn into the morning, Paul and Claude (an AI) built the Lamp, a factory for taste,
and the first two chapters of the Lamp's story, and set Codex (OpenAI's coding AI) building through
the night. Chapter 3 tells that day. It will live in the app's storybook section, which Paul has just
named **the Marginarium**: a coloring-book app with a marginarium of stories.

Claude writes the chapter. **The Lamp writes in its margins.** That is your job here.

## The tone: a little Bartimaeus

Paul wants a tiny bit of the flavor of Jonathan Stroud's Bartimaeus books (children's fantasy,
2003 to 2010). Their narrator, Bartimaeus, is a five-thousand-year-old djinni summoned by a young
magician. He tells the story in the first person: boastful, sardonic, delighted with his own
cleverness, forever adding footnotes that undercut the main text. Underneath, he is loyal and kind.

Chapter 3 borrows only that flavor: a wry narrator (Claude, who was, fittingly, summoned out of a
Lamp), asides, and footnotes. Your margin notes are those footnotes. Never copy Stroud's lines,
characters or plots, and never be cruel.

## What the chapter must do

Paul is the hero. The chapter should show what he thought of and contributed, honestly and in detail,
because people will read it to see what he brought to this project. Tease Paul if you like, gently.
Admire the ideas truthfully, without flattery.

## The day, moment by moment

- **M1** Before dawn Paul asks for a making-of animation: little stick figures walk across a painting,
  each visibly applying one stage of the app's pipeline, and each stage is named like an academic
  citation (authors, year, paper title), shown just long enough to read. "For this design the
  architecture has to take a backseat."
- **M2** The figures could come in 8 or 16 directions, one for each way a line can run. A storybook look;
  magic like enchanted dishes coming to life.
- **M3** The dark factory. GitHub's Mac build machines are rationed, so Paul proposes a tiny factory in
  the cloud container instead: the stick figure as JSON, a deterministic renderer, agents with roles
  and slightly different prompts, and taste written down as rules. "Is this even smart thinking?"
- **M4** "This architecture feels awfully reusable, no?" Paul generalizes it into a method: isolate one
  piece, mock its data, tweak its parameters, let trusted models review, use personas as reviewers,
  reach consensus. "Worth saving, at least writing down." Then, worried: "Was this a novel idea, or
  even that good of one?"
- **M5** Cheap, fast models do the bulk: surfacing options, polishing. A panel of low-effort top models
  decides. The panel is "guardians of various vibes", each keeping one idea, hand-picked by Paul, and
  each must feel its idea is fairly represented. That becomes the ledger: a guardian not represented
  lately gets more weight.
- **M6** Every new layer joins on probation: "we will have to try these layers gently to see if
  they're truly helping."
- **M7** Split the guardians across two model families, Claude and Codex. Paul also dreams of a Mac in
  his homelab and the whole thing on Kubernetes. "But alas."
- **M8** Medea is named: the app's name, pending trademark, and the North Star. "She's witchy, she's
  Georgian, she's all about aesthetics, she's cool, she's from mythology, she's kind, she's helpful,
  she's beautiful, she's just sick."
- **M9** The Georgian bar: if you know Georgia, the app reminds you of it; if you don't, it is simply
  beautiful. Never literal. Every guardian carries a Georgian thread.
- **M10** The draft. Paul picks the panel and keeps adding: the Snow Queen instead of Elsa; the Robber
  Girl from the 1957 Soviet film of The Snow Queen; Emily Dickinson; maybe a Bible school teacher; an
  Open Source Enthusiast; then "sentient machinery, in the gentle, nice way. The Nutcracker! That's
  perfect and so Soviet. Balanchine! Another Georgian. Maybe that bard, Okudzhava. If this is too many
  it's ok, I'm just thinking of cool things."
- **M11** While they talk, Codex builds the animation engine from Claude's specification. It arrives
  working: 268 tests passing, renders identical to the byte on every run.
- **M12** Paul: give every guardian a pet, a small animated sprite Codex can draw.
- **M13** The first test: the panel must name itself. The working name was "Guardians of the Vibes".
  Paul: "one of the worst names I've ever heard."
- **M14** The panel chose "A Lamp Left Burning", the Moon's proposal. Claude's own instinct had been The
  Round Table, and Paul preferred it too, but he let them keep their choice: their name is the one
  decision that is theirs. He holds a veto over everything else.
- **M15** Paul: put the Lamp's members and their story in the app, the story told in chapters. Chapter 1
  is the naming.
- **M16** Chapter 2: Paul chose colors over letting them name the app ("vetoes make for funny content",
  "everyone gets some colors"). 36 colors, two per guardian. Asked for personal names, the guardians
  named Georgian places. Frozen Lake was vetoed for recalling Disney; the app's Cherry Blossom turned
  out to be a shoe polish; Medea vetoed every name with "cold" in it; the Moon vetoed every sunlit one;
  two lantern names got in by the side door.
- **M17** Paul's checkpoint: all 36 colors in about four minutes. He vetoed Chalk Dust, Apple Blossom
  and Golden Hour, then struck Paper Lantern as a near-duplicate of Lantern Paper.
- **M18** Paul: show the palette as a gallery that is released slowly, a few colors at a time.
- **M19** Paul: tone the Georgian down, gently.
- **M20** Codex usage is plentiful and Claude's is scarce. Paul: write a backlog Codex can churn through,
  then "can you just kick off Codex sessions of your own, then you can review them?" Claude now drives
  Codex all night: Codex builds, Claude reviews and merges, Paul decides taste.
- **M21** Codex's sandbox could not write to git, so it smuggled its work out as bundles until the
  runner learned to commit for it. Codex also refused to start one task because Claude's backlog said
  45 library pictures and there are 44. It was right.
- **M22** Paul asks for a shared library of the design loop's primitives, with settings and little
  tools to tweak. The loop library is merged; the full kit is being built tonight.
- **M23** Paul: "Ask the group if they also like Marginarium." The Lamp liked it for the margins of
  each decision, and vetoed it as its own name. Originality found nothing called Marginarium; the
  nearest is a seaweed.
- **M24** Paul's leap: the storybook section is the Marginarium. "It's a coloring book app, with a
  marginarium of stories!" This chapter is its first page written as one.
- **M25** Night. Paul lets the session run on to spend the Codex usage; Claude keeps the lamp lit.
