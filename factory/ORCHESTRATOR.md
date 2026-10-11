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
- Taste decisions are not Codex's: the Lamp and Paul decide (`ARCHITECTURE.md`).
- Paul's veto stands over everything but the Lamp's own name.
- Credentials: Codex is signed in to Paul's ChatGPT plan in this container only; never print or
  copy its auth file.

## State of play

| Item | State |
| --- | --- |
| v0 engine (8c5683e) | Merged. Claude checked: builds, 17 tests, checks pass, byte-identical renders. Its review is F1 in the backlog; the Charter credit doesn't break AboutTests (drift only, fixed in F1) |
| F2 (2f65485) | Merged. Claude checked: 37 taste tests pass, both recorded runs replay byte for byte; `nina` is now `robber-girl` with an alias |
| F4 (d704433) | Merged. Claude checked: 271 tests; the v1 SHA-256 pin matches the base table; parrots pin unchanged; `pbn vocab check` works. The pin test shells out to `sha256sum`/`shasum` (Linux and macOS only) |
| F1, F13, F6 | Running (Codex, gpt-6.1-sol, high) |
| F5, F8 | Ready (next) |
| F12 | Ready after F13 (both build gallery pages) |
| F7 | Claude runs it outside the sandbox: Codex sessions have no network, and the pilot needs `codex exec` itself |
| F3, F9, F10 | Need a spec from Claude |
| F11 | Waits on CI minutes |

## Waiting on Paul

- The chapter 2 checkpoint, colors 26–36: https://claude.ai/artifact/SeP74EBkMZVVtmXrp9Ao8k.
  Then export his picks to `pieces/color-names/run/checkpoint.json`, replace vetoed names with
  their runners-up, and write chapter 2 as a doc (chapter 1:
  https://claude.ai/code/artifact/8007efa4-596c-476e-a087-accdeaba6355).
- The pets' style sheet run needs the F7 pilot first.
