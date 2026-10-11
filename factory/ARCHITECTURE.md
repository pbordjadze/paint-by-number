# The vibe factory: architecture

How the factory turns a design question into a decision Paul approves, and what gets built in
which order. The figure engine's contract is `SPEC.md`, the panel is `GUARDIANS.md`, and how
we got here is in `NOTES.md`.

## Layers

| Layer | What it does | Who runs it |
| --- | --- | --- |
| Renderer | Parameters in, review sheets and code checks out; deterministic | Code (v0: the figure engine) |
| Proposers | Write new parameter files, each from one guardian's point of view | Haiku 5.5 |
| Craft | Drops candidates that fail a code check | Code (`checks.json`) |
| Jury | Six jurors judge the survivors blind | Low-effort Opus 5.5 |
| Decision | Combines the verdicts, updates the ledger and the champion | Code |
| Checkpoint | Paul picks among the best and says why | Paul, on a review page |
| Style | Paul's picks and reasons become rules everyone reads | Claude drafts, Paul approves |

Every layer beyond the renderer joins on probation and stays only if it measurably helps: the
jury agrees with Paul's picks more often, or he reaches a pick he likes in fewer rounds.

## Pieces

A piece is one thing being designed. Each piece has:

- a parameter format (for the hero figure: the figure spec);
- a renderer that writes review sheets and `checks.json`;
- a brief (`brief.md`): what the piece is for, where it appears, and which guardians it most
  concerns.

The first piece is the hero figure clip (`SPEC.md`'s scope). The palette, the logo and the
pipeline-stage scenes come later, each with its own small format and renderer.

## A round

1. **Draw.** Code draws the jury: Originality, then the five guardians the ledger shows least
   represented (ties go to the brief's guardians; Paul can name jurors). The four
   least-represented guardians not seated become the proposers' points of view.
2. **Propose.** Four Haiku agents each see the champion's sheets, the parameter table, their
   guardian's charter, `STYLE.md` and the approved examples. Each writes one parameter file and
   one line on why. A file the renderer rejects goes back once, with the error.
3. **Render.** The renderer renders the champion and each proposal. A candidate that fails a
   code check is out.
4. **Judge.** Each juror sees the survivors and the champion as letters, in an order shuffled for
   that juror, with every candidate's sheets. Each answers, for each candidate: where its idea
   lives in it (or that it doesn't), a veto with a reason or none, and a full ranking.
5. **Decide.** Vetoed candidates are out. Each ranking scores points (n − 1 for first down to 0
   for last), multiplied by the juror's weight: 1, plus 0.5 for each piece since the ledger last
   found that guardian in a winner, capped at 2. The highest total wins; ties go to the candidate
   more jurors ranked first, then to the champion. The winner becomes the champion.
6. **Record.** The ledger gets each juror's line on where it lives in the winner.

A round is 4 Haiku and 6 low-effort Opus agents. It runs as one Workflow script; the script is
saved to `.claude/workflows/` only after it has produced a round Paul likes.

## Checkpoints

After three rounds, or sooner once the champion survives two rounds in a row, Claude publishes a
private review page: the top three or four clips side by side, each with its jurors' lines, and
the ledger. Paul picks one and says why in a sentence; the page stores the pick, and Claude reads
it from there.

- Each pick becomes a **calibration pair** (the picked clip against each one not picked). Every
  juror and the Haiku tier are scored on how often they agree with Paul. Calibration changes how
  much a juror's ranking counts in the decision, never whether it has a seat; seats are Paul's.
- Claude distills Paul's reasons into numbered rules in `STYLE.md` and his picks into the
  approved examples, both for him to approve. Every proposer and juror reads them.
- Paul reads the usage meter before and after the first round, to learn what a round costs.

## Files

```
factory/
  ARCHITECTURE.md  SPEC.md  GUARDIANS.md  NOTES.md
  STYLE.md                          Paul's approved rules (starts empty)
  pieces/<piece>/
    brief.md
    champion.json                   the current winner's parameters
    ledger.json                     per decided round: each guardian's line on the winner
    picks.json                      Paul's checkpoint picks and reasons
    anchors/                        the approved examples' parameter files
    rounds/NNN/
      draw.json                     jurors and proposers
      proposals/<guardian>.json     each proposal and its line on why
      verdicts/<guardian>.json      each juror's answers
      decision.json                 the scores, the vetoes and the winner
```

Only text is committed (parameters, verdicts, decisions, rules). Frames, clips and sheets are
render output: they live outside the repo (`$FACTORY_OUT`, default `~/factory-out`), and the
review pages carry the clips. Commits on this branch carry `[skip ci]`.

## Roadmap

1. **Engine v0** (Codex, now): `SPEC.md`.
2. **The loop** (Claude, once v0 lands): the hero figure's brief and baseline, the round script,
   the first rounds, the first checkpoint.
3. **Calibration** (after Paul's first checkpoint): score the jurors and the Haiku tier; keep
   what helps.
4. **More pieces**: the palette (OKLab colors with contrast checked in code), then the logo and
   icon (SVG variants), then the pipeline-stage scenes (props, reveal timing, the citation
   cards).
5. **The app**: `FigureRig` drawn on the Metal canvas; the pipeline rerun with a snapshot
   observer that leaves templates byte for byte the same; the making-of show on Start, skippable,
   with Reduce Motion, VoiceOver and a CI screenshot scenario; the rename to Medea once the name
   clears. This is when the app's rules in `CLAUDE.md` change with the design.
