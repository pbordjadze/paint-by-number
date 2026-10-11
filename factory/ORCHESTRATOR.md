# Orchestrating Codex

How Claude drives Codex through `BACKLOG.md` from the cloud session: Codex builds, Claude reviews
and merges, Paul decides taste. Everything the factory is and why lives in `NOTES.md`,
`ARCHITECTURE.md`, `SPEC.md`, `GUARDIANS.md` and `pieces/*/brief.md`; this file is only the
driving manual and the state of play.

## Driving an item

1. Worktree per item, outside the repo:
   `git worktree add <scratch>/wt/<id> -b codex/<id>-<slug> origin/claude/vibe-factory`.
2. Run Codex there, in the background, at the model Paul chose (GPT-6.1 Sol or Astra) and high
   reasoning effort, sandboxed to the worktree (`codex exec -C <worktree> -m <model>
   -c model_reasoning_effort="high" -s workspace-write --json`). The Swift 6.2 toolchain from the
   scratchpad goes on `PATH`. Prompt: `BACKLOG.md`'s "How to work an item", the item ID, and
   "commit locally; Claude pushes".
3. When it finishes: read its report, `git diff origin/claude/vibe-factory...`, run the item's
   checks yourself (`swift build`, the tests it names, determinism by rendering twice).
   First-pass reviews can go to a Sonnet subagent to save Claude budget; Claude reads the
   verdict and the risky parts.
4. Codex's sandbox keeps git metadata read-only, so Codex leaves its work uncommitted and writes
   its commit message to `/root/factory-out/<id>/commit-message.txt`; the runner (`run_item2.sh`
   in the scratchpad) commits it and pushes `codex/<id>-<slug>` as soon as the session ends, but
   only if every commit says `[skip ci]`; the container can be wiped while idle. Good:
   merge it into `claude/vibe-factory` and note it below. Not good: give Codex the review in the same worktree and run again; after two rounds,
   fix it yourself or park it with a note.
5. One Codex session per item, at most three at once, on items that don't touch the same files.

## Rules

- Never push `main`, `sidestore` or other people's branches. Every commit has `[skip ci]` (macOS
  runners are rationed).
- Taste decisions are not Codex's. People first: Paul, and the family and people he invites; a
  human creative choice always wins over an AI one when a person wants it to. The Lamp gets only
  smaller design problems, and its answers are proposals. Ask Paul before taking a big creative
  choice to the Lamp.
- Building is Codex's by default, app work included (Paul, Oct 11): Claude subagents are for the
  Lamp, reviews and reading. Use a Claude agent to build only when there's a reason, and say it.
- Paul's veto stands over everything but the Lamp's own name.
- `CONSTITUTION.md` binds every session. A chapter Paul has read changes only out loud (say what
  and why), and a guardian's own words most carefully of all.
- Credentials: Codex is signed in to Paul's ChatGPT plan in this container only; never print or
  copy its auth file.

## State of play

| Item | State |
| --- | --- |
| v0 engine (8c5683e) | Merged. Claude checked: builds, 17 tests, checks pass, byte-identical renders. Its review is F1 in the backlog; the Charter credit doesn't break AboutTests (drift only, fixed in F1) |
| F2 (2f65485) | Merged. Claude checked: 37 taste tests pass, both recorded runs replay byte for byte; `nina` is now `robber-girl` with an alias |
| F4 (d704433) | Merged. Claude checked: 271 tests; the v1 SHA-256 pin matches the base table; parrots pin unchanged; `pbn vocab check` works. The pin test shells out to `sha256sum`/`shasum` (Linux and macOS only) |
| F1 (3206005) | Merged. Claude checked: byte-identical renders, all checks; review 118 s on a loaded container (42 s alone) |
| F6 (65e2f7b) | Merged. Claude checked keyframe timings, reduced motion and tests; not yet seen in a browser with a real pet |
| F5 (b0eaf34) | Merged: traffic.json over 44 pictures x 5 seeds; Linux pbn has no line detection, so it follows the default generator |
| F13 (3a2d0c1) | Merged: the design-loop kit; 58 factory tests, both runs replay byte for byte; live model calls untested |
| F8 (457dc29) | Merged: 275 tests; regression templates byte-identical to the base |
| F12 (d23676b) | Merged: the palette gallery; follow-ups: "The Writer" wording, hide the writer's empty reasons; drops.json waits on Paul |
| F9 (de4826c) | Merged: reveal fields and worker paths; follow-up: a one-centroid path is stationary |
| F3 (876b406) | Merged: the figure piece, dry-run only; the Lamp runs it later |
| F10 (4859d5e) | Merged: engine v1 (props, sweep, ink, several actors); 307 tests with F9; hero digests unchanged |
| F14 | Merged: v1 and v2 pet sheets on the collection page; gallery wording |
| F15 | Merged: walkable reveal paths; renders byte-identical |
| F7 | Merged: a v2 teapot in 21 image generations and 18 min, validated, nothing uploaded; one Codex session per pet |
| F17 (5ea39a2) | Merged: moves, driver interface, mock driver, play piece, replay |
| F16 | Merged: the making-of movie; citations checked word for word; renders byte-identical. Test photos were thumbnails, so a full-size render is next |
| F18 | Merged: Pip (13 generations, 17 min) and Colophon (15, 25 min), drawn as a family; nothing uploaded to the pets service. Both final sheets and Colophon's lamp clip are kept as assets of chapter 7's doc (`d2c048f8…`, `d0782166…`, `6f01832d…`), since the container can be wiped |
| F20 | Merged: the makers' page after the guardians (`collection.py --pets`); checked in Chromium by Claude |
| F21 | Done: a read-only audit, twelve findings (three high: job-ID paths, huge numbers trap the Swift CLI, symlinked output children), split into F22 (Swift) and F23 (Python) |
| F23 | Merged: the audit's Python fixes; Claude fixed the guards' refusal of macOS's linked /tmp and /var |
| F22 | Merged: the audit's Swift fixes; hero and workers digests unchanged, engine 1.0.1; 138 Python tests pass on the merged tree |
| F24 | Merged: SimctlDriver and the mailbox contract (`pieces/play/README.md`) for M2's Swift test; tested against a fake xcrun only |
| F25 | Codex's provider stopped it as a possible cybersecurity risk; not reworded to get past the filter. A Claude agent reviewed the decoders by reading (its fuzzing never ran): the template reader is sound; two app traps on damaged data (painting time, refinement points) confirmed by Claude and queued as F28 (waits on CI); a validator overflow is F27 |
| F26 | Done, report only: the six corpus photos in classic, book and Auto give identical template bytes (and stats, apart from timings) at 1, 2, 3 and 4 cores; 144 generations, all valid. Note for any future gate: `taskset` alone leaves Foundation's `activeProcessorCount` (so `Parallel.bandCount`) unchanged on Linux; Codex varied it with an external shim |
| F19 | Merged (Codex hit the two-hour limit in final verification; Claude committed and tested it). Two full renders: 8,112 byte-identical frames; the movie runs 338 s, the worker is 7.5% of the photo, and in line art the worker inks a straight line across the drawing: all for the Lamp's review. Output: `/root/factory-out/F19/first/` |
| F27 | Merged: Int counts and bounded validation work; templates byte-identical, no timing change measured |
| Loop | Claude made the taste loop's JSON writes atomic after a half-written job file failed one test run |
| F11 | Waits on CI minutes |


App work now branches from `main` (runner `run_codex.sh <ID> <slug> main <prompt>`; prompts in
Claude's scratchpad). Codex commits with `[skip ci]`; Claude pushes a merge to a `claude/` branch
for CI, feeds errors back, and merges to `main` only with Paul's go. Claude's own usage is tight
(Paul's plan is shared): no Lamp runs, no Claude subagents, short reviews.

| App item | State |
| --- | --- |
| Marginarium v1 (73a9600) | On `main`, build 1.0.294 in SideStore: Pip and one passage per chapter |
| F29 Marginarium v2 | Running (Codex): people-first intro, Colophon, How the Lamp works |
| F28 Damaged data never traps | Running (Codex) |
| F30 Play harness, app half | Running (Codex): Debug hook, mailbox UI test, CI self-test |

## Waiting on Paul

- Chapter 7, Two More Pets: https://claude.ai/code/artifact/a112d638-0555-4f24-9a6a-6a3fc5476adf.
  Claude kept Colophon's eyes (a taste call, Paul's to veto).
- CI minutes for F28 (the app traps on damaged data) batched with F11.
- `pieces/color-names/drops.json`, the gallery's drop schedule; Okudzhava's Late Sunlight question.
- The pets' style sheet: Paul's call who decides it (people he invites, or the Lamp as a proposal).
- The making-of's look (Paul's call; the Lamp only if he wants its notes): 338 s long, a small worker, and a straight
  ink line across the drawing in the line-art stage.
